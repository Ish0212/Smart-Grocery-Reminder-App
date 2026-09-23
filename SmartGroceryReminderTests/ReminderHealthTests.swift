import XCTest
import CoreLocation
import UserNotifications
import UIKit
@testable import SmartGroceryReminder

final class ReminderHealthTests: XCTestCase {
    private func check(
        authorization: CLAuthorizationStatus = .authorizedAlways,
        accuracy: CLAccuracyAuthorization = .fullAccuracy,
        notifications: UNAuthorizationStatus = .authorized,
        backgroundRefresh: UIBackgroundRefreshStatus = .available,
        lowPowerMode: Bool = false,
        hasHome: Bool = true,
        systemRegionCount: Int = 2,
        expectedRegionCount: Int = 2
    ) -> [HealthItem] {
        ReminderHealth.check(
            authorization: authorization,
            accuracy: accuracy,
            notifications: notifications,
            backgroundRefresh: backgroundRefresh,
            lowPowerMode: lowPowerMode,
            hasHome: hasHome,
            systemRegionCount: systemRegionCount,
            expectedRegionCount: expectedRegionCount
        )
    }

    private func item(_ id: String, in items: [HealthItem]) throws -> HealthItem {
        try XCTUnwrap(items.first { $0.id == id })
    }

    func testEverythingSetUpIsAllGreen() {
        let items = check()
        XCTAssertTrue(items.allSatisfy(\.isOK))
        XCTAssertTrue(items.allSatisfy { $0.fix == nil })
    }

    func testWhileUsingLocationNeedsFixing() throws {
        let location = try item("location", in: check(authorization: .authorizedWhenInUse))
        XCTAssertFalse(location.isOK)
        XCTAssertFalse(location.isWarningOnly)
        XCTAssertNotNil(location.fix)
    }

    func testApproximateLocationNeedsFixing() throws {
        XCTAssertFalse(try item("precise", in: check(accuracy: .reducedAccuracy)).isOK)
    }

    func testNotificationsMustBeFullyAllowed() throws {
        XCTAssertFalse(try item("notifications", in: check(notifications: .denied)).isOK)
        XCTAssertFalse(try item("notifications", in: check(notifications: .provisional)).isOK)
    }

    func testMissingRegionsNeedFixing() throws {
        XCTAssertFalse(try item("regions", in: check(systemRegionCount: 1, expectedRegionCount: 2)).isOK)
        XCTAssertFalse(try item("regions", in: check(hasHome: false, systemRegionCount: 0, expectedRegionCount: 0)).isOK)
        XCTAssertFalse(try item("home", in: check(hasHome: false)).isOK)
    }

    func testBackgroundRefreshAndLowPowerAreWarningsOnly() throws {
        let refresh = try item("backgroundRefresh", in: check(backgroundRefresh: .denied))
        XCTAssertFalse(refresh.isOK)
        XCTAssertTrue(refresh.isWarningOnly)

        let power = try item("lowPower", in: check(lowPowerMode: true))
        XCTAssertFalse(power.isOK)
        XCTAssertTrue(power.isWarningOnly)
    }
}
