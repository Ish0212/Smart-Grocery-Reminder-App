import XCTest
import CoreLocation
@testable import SmartGroceryReminder

/// People change location access in Settings at any time, often without opening the app.
final class PermissionReliabilityTests: XCTestCase {
    @MainActor
    private func service(_ manager: FakeLocationManager) -> (LocationService, DiagnosticsLog) {
        let log = DiagnosticsLog()
        return (LocationService(diagnostics: log, manager: manager), log)
    }

    @MainActor
    func testDowngradingFromAlwaysToWhileUsingTurnsHealthRedAndIsLogged() {
        let manager = FakeLocationManager()
        let (service, log) = service(manager)
        service.startMonitoring(home: Reliability.home, stores: [Reliability.store])
        XCTAssertTrue(health(of: service)["location"]!.isOK)

        manager.changeAuthorization(to: .authorizedWhenInUse, on: service)

        XCTAssertEqual(service.authorizationStatus, .authorizedWhenInUse)
        XCTAssertFalse(health(of: service)["location"]!.isOK)
        XCTAssertNotNil(health(of: service)["location"]!.fix)
        XCTAssertTrue(log.entries.contains { $0.kind == .permission && $0.message.contains("While") })
    }

    @MainActor
    func testTurningOffPreciseLocationTurnsHealthRedEvenWithAlways() {
        let manager = FakeLocationManager()
        let (service, _) = service(manager)

        manager.changeAuthorization(to: .authorizedAlways, accuracy: .reducedAccuracy, on: service)

        XCTAssertTrue(health(of: service)["location"]!.isOK)
        XCTAssertFalse(health(of: service)["precise"]!.isOK)
    }

    @MainActor
    func testWithAccessDeniedNoLocationFixIsRequested() {
        let manager = FakeLocationManager()
        manager.authorizationStatus = .denied
        let (service, _) = service(manager)

        service.requestCurrentLocation()

        XCTAssertEqual(manager.locationRequests, 0)
    }

    @MainActor
    func testTheSameAuthorizationReportedTwiceIsLoggedOnce() {
        // iOS calls locationManagerDidChangeAuthorization on every launch, changed or not.
        let manager = FakeLocationManager()
        let (service, log) = service(manager)

        manager.changeAuthorization(to: .authorizedWhenInUse, on: service)
        manager.changeAuthorization(to: .authorizedWhenInUse, on: service)

        XCTAssertEqual(log.entries.filter { $0.kind == .permission }.count, 1)
    }

    @MainActor
    func testRestoringAlwaysTurnsHealthGreenAgain() {
        let manager = FakeLocationManager()
        let (service, _) = service(manager)
        service.startMonitoring(home: Reliability.home, stores: [Reliability.store])
        manager.changeAuthorization(to: .authorizedWhenInUse, on: service)

        manager.changeAuthorization(to: .authorizedAlways, on: service)

        XCTAssertTrue(health(of: service).values.filter { !$0.isWarningOnly }.allSatisfy(\.isOK))
    }
}
