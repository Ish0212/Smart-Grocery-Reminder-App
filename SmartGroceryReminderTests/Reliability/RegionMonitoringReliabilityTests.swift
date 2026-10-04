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
}
