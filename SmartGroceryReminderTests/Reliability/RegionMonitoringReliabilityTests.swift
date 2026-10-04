import XCTest
import CoreLocation
@testable import SmartGroceryReminder

/// Geofences are the only thing that wakes the app at a store or at home. These scenarios cover
/// what iOS does to them behind the app's back.
final class RegionMonitoringReliabilityTests: XCTestCase {
    @MainActor
    func testASessionArmsHomeAndStoreOnTheLocationManager() async throws {
        let manager = FakeLocationManager()
        let state = try await reliabilitySession(manager: manager)

        try await waitUntil { manager.monitoredRegions.count == 2 }
        XCTAssertEqual(
            Set(manager.monitoredRegions.map(\.identifier)),
            [RegionID.make(for: Reliability.home), RegionID.make(for: Reliability.store)]
        )
        XCTAssertEqual(state.locationService.systemRegionCount, 2)
        state.signOut()
    }

    @MainActor
    func testARegionIOSRefusesToMonitorShowsInHealth() {
        let manager = FakeLocationManager()
        manager.failingRegionIds = [RegionID.make(for: Reliability.store)]
        let log = DiagnosticsLog()
        let service = LocationService(diagnostics: log, manager: manager)
        service.startMonitoring(home: Reliability.home, stores: [Reliability.store])
        XCTAssertEqual(service.systemRegionCount, 2) // iOS accepts it first...

        manager.deliverMonitoringFailures(to: service) // ...then reports the failure

        XCTAssertEqual(service.systemRegionCount, 1)
        XCTAssertFalse(health(of: service)["regions"]!.isOK)
        XCTAssertEqual(health(of: service)["regions"]!.title, "iOS is watching 1 of 2 places")
        XCTAssertTrue(log.entries.contains { $0.kind == .error })
    }

    @MainActor
    func testPlacesOverTheIOSLimitAreReportedNotSilentlyDropped() {
        let manager = FakeLocationManager()
        let service = LocationService(diagnostics: DiagnosticsLog(), manager: manager)
        let stores = (1...20).map {
            GeoPlace(id: "s\($0)", name: "Store \($0)", latitude: 40 + Double($0) / 100, longitude: -74, kind: .groceryStore)
        }
        service.startMonitoring(home: Reliability.home, stores: stores) // 21 places

        manager.deliverMonitoringFailures(to: service)

        XCTAssertEqual(service.systemRegionCount, 20)
        XCTAssertEqual(health(of: service, expectedRegionCount: 21)["regions"]!.title, "iOS is watching 20 of 21 places")
        XCTAssertFalse(health(of: service, expectedRegionCount: 21)["regions"]!.isOK)
    }

    @MainActor
    func testReapplyingTheSamePlacesTouchesNoGeofence() {
        let manager = FakeLocationManager()
        let service = LocationService(diagnostics: DiagnosticsLog(), manager: manager)
        service.startMonitoring(home: Reliability.home, stores: [Reliability.store])
        let starts = manager.startCalls.count

        service.startMonitoring(home: Reliability.home, stores: [Reliability.store])

        XCTAssertEqual(manager.startCalls.count, starts)
        XCTAssertTrue(manager.stopCalls.isEmpty)
    }

    @MainActor
    func testAddingAStoreStartsOnlyThatStore() {
        let manager = FakeLocationManager()
        let service = LocationService(diagnostics: DiagnosticsLog(), manager: manager)
        service.startMonitoring(home: Reliability.home, stores: [Reliability.store])
        let second = GeoPlace(id: "rel-store-2", name: "Corner shop", latitude: 40.72, longitude: -74.02, kind: .groceryStore)

        service.startMonitoring(home: Reliability.home, stores: [Reliability.store, second])

        XCTAssertEqual(manager.startCalls.last, RegionID.make(for: second))
        XCTAssertEqual(manager.startCalls.count, 3)
        XCTAssertTrue(manager.stopCalls.isEmpty)
    }

    @MainActor
    func testRegionStateReportsNeverBecomeEventsAndRepeatsAreLoggedOnce() {
        let log = DiagnosticsLog()
        let service = LocationService(diagnostics: log, manager: FakeLocationManager())
        var events: [LocationEvent] = []
        let subscription = service.events.sink { events.append($0) }
        let id = RegionID.make(for: Reliability.home)

        service.handleRegionState(.inside, identifier: id)
        service.handleRegionState(.inside, identifier: id)

        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(service.regionStates[id], .inside)
        XCTAssertEqual(log.entries.filter { $0.kind == .regionState }.count, 1)
        subscription.cancel()
    }

    @MainActor
    func testARefusedRegionStillListedWhenReportedIsNotCounted() {
        let manager = FakeLocationManager()
        manager.failingRegionIds = [RegionID.make(for: Reliability.store)]
        manager.reportsFailuresBeforeDroppingRegions = true
        let service = LocationService(diagnostics: DiagnosticsLog(), manager: manager)
        service.startMonitoring(home: Reliability.home, stores: [Reliability.store])

        manager.deliverMonitoringFailures(to: service)

        XCTAssertEqual(service.systemRegionCount, 1)
        XCTAssertFalse(health(of: service)["regions"]!.isOK)
    }
}
