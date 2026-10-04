import CoreLocation
@testable import SmartGroceryReminder

/// Stands in for `CLLocationManager`. Like iOS, it accepts every region it's asked to monitor
/// straight away; failures (a scripted id, or going over the region limit) are reported later,
/// when a test calls `deliverMonitoringFailures(to:)`.
final class FakeLocationManager: LocationManaging {
    weak var delegate: CLLocationManagerDelegate?
    var desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    var authorizationStatus: CLAuthorizationStatus = .authorizedAlways
    var accuracyAuthorization: CLAccuracyAuthorization = .fullAccuracy
    private(set) var monitoredRegions: Set<CLRegion> = []

    /// iOS lets one app monitor at most 20 regions.
    var regionLimit = 20
    /// Region identifiers iOS will refuse to monitor.
    var failingRegionIds: Set<String> = []
    /// Apple doesn't document whether a refused region is still listed when the failure is
    /// reported; `true` reports it first and drops it afterwards.
    var reportsFailuresBeforeDroppingRegions = false

    private(set) var startCalls: [String] = []
    private(set) var stopCalls: [String] = []
    private(set) var stateRequests: [String] = []
    private(set) var locationRequests = 0
    private(set) var authorizationRequests = 0

    func requestAlwaysAuthorization() { authorizationRequests += 1 }
    func requestLocation() { locationRequests += 1 }

    func startMonitoring(for region: CLRegion) {
        startCalls.append(region.identifier)
        monitoredRegions.insert(region)
    }

    func stopMonitoring(for region: CLRegion) {
        stopCalls.append(region.identifier)
        monitoredRegions = monitoredRegions.filter { $0.identifier != region.identifier }
    }

    func requestState(for region: CLRegion) { stateRequests.append(region.identifier) }

    /// Regions iOS would refuse: scripted failures, then any over the limit (in start order).
    var regionsThatWillFail: [CLRegion] {
        let ordered = startCalls.compactMap { id in monitoredRegions.first { $0.identifier == id } }
        var unique: [CLRegion] = []
        for region in ordered where !unique.contains(where: { $0.identifier == region.identifier }) {
            unique.append(region)
        }
        let scripted = unique.filter { failingRegionIds.contains($0.identifier) }
        let rest = unique.filter { !failingRegionIds.contains($0.identifier) }
        return scripted + rest.dropFirst(regionLimit)
    }
}

@MainActor
extension FakeLocationManager {
    /// Drops the regions iOS refuses and reports each failure, the way `monitoringDidFailFor` would.
    func deliverMonitoringFailures(to service: LocationService) {
        for region in regionsThatWillFail {
            let drop = { self.monitoredRegions = self.monitoredRegions.filter { $0.identifier != region.identifier } }
            if !reportsFailuresBeforeDroppingRegions { drop() }
            service.handleMonitoringFailure(identifier: region.identifier, message: "The operation couldn't be completed.")
            if reportsFailuresBeforeDroppingRegions { drop() }
        }
    }

    /// The user changes access in Settings; iOS then calls `locationManagerDidChangeAuthorization`.
    func changeAuthorization(to status: CLAuthorizationStatus, accuracy: CLAccuracyAuthorization = .fullAccuracy, on service: LocationService) {
        authorizationStatus = status
        accuracyAuthorization = accuracy
        service.handleAuthorizationChange(status: status, accuracy: accuracy)
    }

    /// iOS reports crossing into `place`'s geofence.
    func deliverEnter(_ place: GeoPlace, at date: Date = Date(), to service: LocationService) {
        service.handleRegionTransition(identifier: RegionID.make(for: place), transition: .enter, date: date)
    }

    func deliverExit(_ place: GeoPlace, at date: Date = Date(), to service: LocationService) {
        service.handleRegionTransition(identifier: RegionID.make(for: place), transition: .exit, date: date)
    }
}
