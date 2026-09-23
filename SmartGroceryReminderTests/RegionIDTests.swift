import XCTest
import Combine
@testable import SmartGroceryReminder

final class RegionIDTests: XCTestCase {
    func testRegionIDRoundTrips() throws {
        let store = GeoPlace(id: "abc-123", name: "Safeway", latitude: 1, longitude: 2, kind: .groceryStore)
        let identifier = RegionID.make(for: store)
        XCTAssertEqual(identifier, "groceryStore:abc-123")

        let parsed = try XCTUnwrap(RegionID.parse(identifier))
        XCTAssertEqual(parsed.kind, .groceryStore)
        XCTAssertEqual(parsed.placeId, "abc-123")
    }

    func testPlaceIdMayContainColons() throws {
        let parsed = try XCTUnwrap(RegionID.parse("home:a:b"))
        XCTAssertEqual(parsed.kind, .home)
        XCTAssertEqual(parsed.placeId, "a:b")
    }

    func testOldAndUnknownIdentifiersDontParse() {
        XCTAssertNil(RegionID.parse("6F9619FF-8B86-D011-B42D-00C04FC964FF"))  // pre-Phase 3 bare UUID
        XCTAssertNil(RegionID.parse("office:1"))
        XCTAssertNil(RegionID.parse("home:"))
    }

    func testRegionDiff() {
        let diff = LocationService.regionDiff(current: ["home:1", "old-uuid", "groceryStore:2"], desired: ["home:1", "groceryStore:3"])
        XCTAssertEqual(diff.stop, ["old-uuid", "groceryStore:2"])
        XCTAssertEqual(diff.start, ["groceryStore:3"])

        let unchanged = LocationService.regionDiff(current: ["home:1"], desired: ["home:1"])
        XCTAssertTrue(unchanged.stop.isEmpty && unchanged.start.isEmpty)
    }

    @MainActor
    func testRegionTransitionIsPublishedAndLogged() {
        let diagnostics = DiagnosticsLog()
        let service = LocationService(diagnostics: diagnostics)
        var received: [LocationEvent] = []
        let subscription = service.events.sink { received.append($0) }
        defer { subscription.cancel() }
        let date = Date(timeIntervalSince1970: 1_000)

        service.handleRegionTransition(identifier: "home:default-home", transition: .enter, date: date)

        XCTAssertEqual(received, [LocationEvent(kind: .home, transition: .enter, placeId: "default-home", date: date)])
        XCTAssertEqual(diagnostics.entries.last?.kind, .regionEnter)
        XCTAssertEqual(diagnostics.entries.last?.placeId, "default-home")
    }

    @MainActor
    func testUnrecognizedRegionIsLoggedButNotPublished() {
        let diagnostics = DiagnosticsLog()
        let service = LocationService(diagnostics: diagnostics)
        var received: [LocationEvent] = []
        let subscription = service.events.sink { received.append($0) }
        defer { subscription.cancel() }

        service.handleRegionTransition(identifier: "6F9619FF-8B86-D011-B42D-00C04FC964FF", transition: .enter, date: Date())

        XCTAssertTrue(received.isEmpty)
        XCTAssertEqual(diagnostics.entries.last?.kind, .regionUnknown)
    }
}
