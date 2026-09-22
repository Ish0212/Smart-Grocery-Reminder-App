import Foundation
import CoreLocation
import Combine

@MainActor
final class LocationService: NSObject, ObservableObject {
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var currentLocation: CLLocationCoordinate2D?
    @Published var monitoredRegions: [String] = []
    @Published var lastEventDescription: String = "Idle"
    @Published var didArriveHome = false
    @Published var didEnterGroceryStore = false

    private let manager = CLLocationManager()
    private var homeRegionId: String?
    private var storeRegionIds = Set<String>()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorizationStatus = manager.authorizationStatus
    }

    func requestAuthorization() {
        manager.requestAlwaysAuthorization()
        manager.startUpdatingLocation()
    }

    func startMonitoring(home: GeoPlace?, stores: [GeoPlace]) {
        stopMonitoring()

        if let home {
            let region = makeRegion(for: home)
            homeRegionId = region.identifier
            manager.startMonitoring(for: region)
            monitoredRegions.append(home.name)
        }

        for store in stores {
            let region = makeRegion(for: store)
            storeRegionIds.insert(region.identifier)
            manager.startMonitoring(for: region)
            monitoredRegions.append(store.name)
        }

        lastEventDescription = monitoredRegions.isEmpty
            ? "No geofences configured"
            : "Monitoring \(monitoredRegions.count) place(s)"
    }

    func stopMonitoring() {
        for region in manager.monitoredRegions {
            manager.stopMonitoring(for: region)
        }
        monitoredRegions.removeAll()
        homeRegionId = nil
        storeRegionIds.removeAll()
    }

    /// Simulator / preview helper to exercise home-arrival flow without leaving the desk.
    func simulateArriveHome() {
        didArriveHome = false
        didArriveHome = true
        lastEventDescription = "Simulated: arrived home"
    }

    func simulateEnterStore(named name: String = "Grocery store") {
        didEnterGroceryStore = false
        didEnterGroceryStore = true
        lastEventDescription = "Simulated: entered \(name)"
    }

    private func makeRegion(for place: GeoPlace) -> CLCircularRegion {
        let center = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
        let region = CLCircularRegion(center: center, radius: place.radiusMeters, identifier: place.id)
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
        Task { @MainActor in
            if region.identifier == self.homeRegionId {
                self.didArriveHome = true
                self.lastEventDescription = "Entered home geofence"
            } else if self.storeRegionIds.contains(region.identifier) {
                self.didEnterGroceryStore = true
                self.lastEventDescription = "Entered store geofence"
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        Task { @MainActor in
            if region.identifier == self.homeRegionId {
                self.lastEventDescription = "Left home geofence"
            }
        }
    }
}
