import Foundation
import CoreLocation
import Combine

/// Geofence identifiers carry the place kind (`"home:<id>"`, `"groceryStore:<id>"`), so an event
/// that relaunches the app can be classified before anything else has loaded.
enum RegionID {
    static func make(for place: GeoPlace) -> String {
        "\(place.kind.rawValue):\(place.id)"
    }

    static func parse(_ identifier: String) -> (kind: GeoPlace.PlaceKind, placeId: String)? {
        guard let separator = identifier.firstIndex(of: ":"),
              let kind = GeoPlace.PlaceKind(rawValue: String(identifier[..<separator])) else { return nil }
        let placeId = String(identifier[identifier.index(after: separator)...])
        return placeId.isEmpty ? nil : (kind, placeId)
    }
}

/// A geofence enter or exit, real or simulated.
struct LocationEvent: Equatable {
    enum Transition: String {
        case enter, exit
    }

    let kind: GeoPlace.PlaceKind
    let transition: Transition
    let placeId: String
    let date: Date
    var isSimulated = false
}

@MainActor
final class LocationService: NSObject, ObservableObject {
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    /// Geofences don't work with approximate location.
    @Published private(set) var accuracyAuthorization: CLAccuracyAuthorization = .fullAccuracy
    @Published var currentLocation: CLLocationCoordinate2D?
    /// How many regions iOS itself reports as monitored.
    @Published private(set) var systemRegionCount = 0
    /// Inside / outside per region identifier, as last reported by iOS.
    @Published private(set) var regionStates: [String: CLRegionState] = [:]
    /// Names of the places being monitored, for display.
    @Published var monitoredRegions: [String] = []
    @Published var lastEventDescription: String = "Idle"

    /// Region enters and exits for AppState to act on. Sent on the main actor.
    let events = PassthroughSubject<LocationEvent, Never>()

    /// `nil` when inert (tests): nothing reaches iOS and no permission is requested.
    private let manager: CLLocationManager?
    private let diagnostics: DiagnosticsLog
    /// Inert mode only: the regions iOS would be monitoring, by region identifier.
    private(set) var monitoredForTesting: [String: CLCircularRegion] = [:]

    /// - Parameters:
    ///   - diagnostics: `nil` keeps events in an in-memory log.
    ///   - manager: `nil` for an inert service that only records the regions it would monitor.
    init(diagnostics: DiagnosticsLog? = nil, manager: CLLocationManager? = CLLocationManager()) {
        self.diagnostics = diagnostics ?? DiagnosticsLog()
        self.manager = manager
        super.init()
        guard let manager else { return }
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorizationStatus = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization
        systemRegionCount = manager.monitoredRegions.count
    }

    var isInert: Bool { manager == nil }

    func requestAuthorization() {
        manager?.requestAlwaysAuthorization()
    }

    /// A single location fix, for "use current location" and nearby search. Geofences don't need
    /// continuous GPS, so nothing keeps location updates running.
    func requestCurrentLocation() {
        guard let manager else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        default:
            break
        }
    }

    /// Asks iOS whether the phone is inside each monitored region (answers arrive in regionStates).
    func refreshRegionStates() {
        systemRegionCount = currentRegions.count
        guard let manager else { return }
        for region in manager.monitoredRegions {
            manager.requestState(for: region)
        }
    }

    /// Makes iOS monitor exactly these places. Only the difference is applied, so regions iOS is
    /// already watching keep their state. Places are never edited in place (a new home or store
    /// gets a new id), so ids alone decide what changes.
    func startMonitoring(home: GeoPlace?, stores: [GeoPlace]) {
        let places = (home.map { [$0] } ?? []) + stores
        let desired = Dictionary(places.map { (RegionID.make(for: $0), $0) }, uniquingKeysWith: { first, _ in first })
        let diff = Self.regionDiff(
            current: Set(currentRegions.map(\.identifier)),
            desired: Set(desired.keys)
        )

        for region in currentRegions where diff.stop.contains(region.identifier) {
            stop(region)
        }
        for identifier in diff.start {
            if let place = desired[identifier] {
                start(makeRegion(for: place, identifier: identifier))
            }
        }

        monitoredRegions = places.map(\.name)
        systemRegionCount = currentRegions.count
        regionStates = regionStates.filter { desired[$0.key] != nil }
        lastEventDescription = places.isEmpty ? "No geofences configured" : "Monitoring \(places.count) place\(places.count == 1 ? "" : "s")"
        if !diff.start.isEmpty || !diff.stop.isEmpty {
            diagnostics.record(.monitoring, "Geofences updated: \(diff.start.count) added, \(diff.stop.count) removed, \(places.count) total")
        }
    }

    /// Regions to stop (monitored but no longer wanted, including old-format ids) and to start.
    nonisolated static func regionDiff(current: Set<String>, desired: Set<String>) -> (stop: Set<String>, start: Set<String>) {
        (current.subtracting(desired), desired.subtracting(current))
    }

    func stopMonitoring() {
        for region in currentRegions {
            stop(region)
        }
        monitoredRegions.removeAll()
        regionStates.removeAll()
        systemRegionCount = 0
    }

    /// Classifies a region event from its identifier alone, so it also works right after iOS
    /// relaunches the app in the background, and publishes it.
    func handleRegionTransition(identifier: String, transition: LocationEvent.Transition, date: Date) {
        let verb = transition == .enter ? "Entered" : "Left"
        guard let parsed = RegionID.parse(identifier) else {
            diagnostics.record(.regionUnknown, "\(verb) an unrecognized region (\(identifier))", date: date)
            return
        }
        let description = "\(verb) \(parsed.kind == .home ? "home" : "grocery store") geofence"
        lastEventDescription = description
        diagnostics.record(
            transition == .enter ? .regionEnter : .regionExit,
            description,
            placeKind: parsed.kind,
            placeId: parsed.placeId,
            date: date
        )
        events.send(LocationEvent(kind: parsed.kind, transition: transition, placeId: parsed.placeId, date: date))
    }

    /// Simulator / preview helper to exercise the home-arrival flow without leaving the desk.
    func simulateArriveHome() {
        lastEventDescription = "Simulated: arrived home"
        diagnostics.record(.regionEnter, "Simulated: arrived home", placeKind: .home)
        events.send(LocationEvent(kind: .home, transition: .enter, placeId: "simulated", date: Date(), isSimulated: true))
    }

    func simulateEnterStore(named name: String = "Grocery store") {
        lastEventDescription = "Simulated: entered \(name)"
        diagnostics.record(.regionEnter, "Simulated: entered \(name)", placeKind: .groceryStore)
        events.send(LocationEvent(kind: .groceryStore, transition: .enter, placeId: "simulated", date: Date(), isSimulated: true))
    }

    static func describe(regionIdentifier identifier: String) -> String {
        guard let parsed = RegionID.parse(identifier) else { return identifier }
        return parsed.kind == .home ? "Home" : "Grocery store"
    }

    static func describe(_ state: CLRegionState) -> String {
        switch state {
        case .inside: return "inside"
        case .outside: return "outside"
        case .unknown: return "unknown"
        @unknown default: return "unknown"
        }
    }

    static func describe(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .authorizedAlways: return "Always"
        case .authorizedWhenInUse: return "While Using"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not determined"
        @unknown default: return "Unknown"
        }
    }

    /// The regions iOS is monitoring, or in inert mode the ones it would be.
    private var currentRegions: [CLRegion] {
        guard let manager else { return monitoredForTesting.values.map { $0 } }
        return Array(manager.monitoredRegions)
    }

    private func start(_ region: CLCircularRegion) {
        guard let manager else {
            monitoredForTesting[region.identifier] = region
            return
        }
        manager.startMonitoring(for: region)
    }

    private func stop(_ region: CLRegion) {
        guard let manager else {
            monitoredForTesting[region.identifier] = nil
            return
        }
        manager.stopMonitoring(for: region)
    }

    private func makeRegion(for place: GeoPlace, identifier: String) -> CLCircularRegion {
        let center = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
        let region = CLCircularRegion(center: center, radius: place.radiusMeters, identifier: identifier)
        region.notifyOnEntry = true
        region.notifyOnExit = place.kind == .home
        return region
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let accuracy = manager.accuracyAuthorization
        Task { @MainActor in
            guard status != self.authorizationStatus || accuracy != self.accuracyAuthorization else { return }
            self.authorizationStatus = status
            self.accuracyAuthorization = accuracy
            self.diagnostics.record(
                .permission,
                "Location access: \(Self.describe(status)), \(accuracy == .fullAccuracy ? "precise" : "approximate")"
            )
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Required by requestLocation(). Transient "location unknown" errors are expected indoors.
        let message = error.localizedDescription
        Task { @MainActor in
            self.diagnostics.record(.error, "Location fix failed: \(message)")
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        let identifier = region?.identifier ?? "a region"
        let message = error.localizedDescription
        Task { @MainActor in
            self.diagnostics.record(.error, "Couldn't monitor \(Self.describe(regionIdentifier: identifier)): \(message)")
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
        manager.requestState(for: region)
        let count = manager.monitoredRegions.count
        Task { @MainActor in
            self.systemRegionCount = count
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        // Also reported alongside every enter/exit; only the state is recorded, never an event.
        let identifier = region.identifier
        Task { @MainActor in
            guard self.regionStates[identifier] != state else { return }
            self.regionStates[identifier] = state
            self.diagnostics.record(
                .regionState,
                "\(Self.describe(regionIdentifier: identifier)): \(Self.describe(state))",
                placeId: RegionID.parse(identifier)?.placeId
            )
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        Task { @MainActor in
            self.currentLocation = coordinate
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        let identifier = region.identifier
        let date = Date()
        Task { @MainActor in
            self.handleRegionTransition(identifier: identifier, transition: .enter, date: date)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        let identifier = region.identifier
        let date = Date()
        Task { @MainActor in
            self.handleRegionTransition(identifier: identifier, transition: .exit, date: date)
        }
    }
}
