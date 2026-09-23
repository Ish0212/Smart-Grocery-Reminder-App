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
    @Published var currentLocation: CLLocationCoordinate2D?
    /// Names of the places being monitored, for display.
    @Published var monitoredRegions: [String] = []
    @Published var lastEventDescription: String = "Idle"

    /// Region enters and exits for AppState to act on. Sent on the main actor.
    let events = PassthroughSubject<LocationEvent, Never>()

    private let manager = CLLocationManager()
    private let diagnostics: DiagnosticsLog

    init(diagnostics: DiagnosticsLog = DiagnosticsLog()) {
        self.diagnostics = diagnostics
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorizationStatus = manager.authorizationStatus
    }

    func requestAuthorization() {
        manager.requestAlwaysAuthorization()
        manager.startUpdatingLocation()
    }

    /// Makes iOS monitor exactly these places. Only the difference is applied, so regions iOS is
    /// already watching keep their state. Places are never edited in place (a new home or store
    /// gets a new id), so ids alone decide what changes.
    func startMonitoring(home: GeoPlace?, stores: [GeoPlace]) {
        let places = (home.map { [$0] } ?? []) + stores
        let desired = Dictionary(places.map { (RegionID.make(for: $0), $0) }, uniquingKeysWith: { first, _ in first })
        let diff = Self.regionDiff(
            current: Set(manager.monitoredRegions.map(\.identifier)),
            desired: Set(desired.keys)
        )

        for region in manager.monitoredRegions where diff.stop.contains(region.identifier) {
            manager.stopMonitoring(for: region)
        }
        for identifier in diff.start {
            if let place = desired[identifier] {
                manager.startMonitoring(for: makeRegion(for: place, identifier: identifier))
            }
        }

        monitoredRegions = places.map(\.name)
        lastEventDescription = places.isEmpty ? "No geofences configured" : "Monitoring \(places.count) place(s)"
        if !diff.start.isEmpty || !diff.stop.isEmpty {
            diagnostics.record(.monitoring, "Geofences updated: \(diff.start.count) added, \(diff.stop.count) removed, \(places.count) total")
        }
    }

    /// Regions to stop (monitored but no longer wanted, including old-format ids) and to start.
    static func regionDiff(current: Set<String>, desired: Set<String>) -> (stop: Set<String>, start: Set<String>) {
        (current.subtracting(desired), desired.subtracting(current))
    }

    func stopMonitoring() {
        for region in manager.monitoredRegions {
            manager.stopMonitoring(for: region)
        }
        monitoredRegions.removeAll()
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
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
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
