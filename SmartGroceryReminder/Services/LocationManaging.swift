import CoreLocation

/// The parts of `CLLocationManager` that `LocationService` uses, so tests can stand in a fake
/// that scripts permission changes, monitoring failures and region events.
protocol LocationManaging: AnyObject {
    var delegate: CLLocationManagerDelegate? { get set }
    var desiredAccuracy: CLLocationAccuracy { get set }
    var authorizationStatus: CLAuthorizationStatus { get }
    var accuracyAuthorization: CLAccuracyAuthorization { get }
    var monitoredRegions: Set<CLRegion> { get }
    func requestAlwaysAuthorization()
    func requestLocation()
    func startMonitoring(for region: CLRegion)
    func stopMonitoring(for region: CLRegion)
    func requestState(for region: CLRegion)
}

extension CLLocationManager: LocationManaging {}
