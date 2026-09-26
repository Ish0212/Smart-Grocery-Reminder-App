import XCTest
@testable import SmartGroceryReminder

final class WidgetSnapshotTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testTitlesAreCappedButTheCountIsNot() {
        let titles = (1...7).map { "Item \($0)" }
        let snapshot = WidgetSnapshot(openTitles: titles, unloadEndDate: nil, now: now)
        XCTAssertEqual(snapshot.openCount, 7)
        XCTAssertEqual(snapshot.openTitles, ["Item 1", "Item 2", "Item 3", "Item 4"])
        XCTAssertTrue(snapshot.isSignedIn)
    }

    func testEndedCountdownIsDropped() {
        let ended = WidgetSnapshot(openTitles: [], unloadEndDate: now.addingTimeInterval(-1), now: now)
        XCTAssertNil(ended.unloadEndDate)

        let running = WidgetSnapshot(openTitles: [], unloadEndDate: now.addingTimeInterval(300), now: now)
        XCTAssertEqual(running.unloadEndDate, now.addingTimeInterval(300))
    }

    func testTimelineAddsAnEntryWhenTheCountdownEnds() {
        let end = now.addingTimeInterval(300)
        let snapshot = WidgetSnapshot(openTitles: ["Milk"], unloadEndDate: end, now: now)
        XCTAssertEqual(snapshot.timelineDates(now: now), [now, end])
        XCTAssertTrue(snapshot.isCountingDown(at: now))
        XCTAssertFalse(snapshot.isCountingDown(at: end))
        XCTAssertEqual(snapshot.timelineDates(now: end), [end])
    }

    func testSignedOutSnapshotShowsNothing() {
        XCTAssertFalse(WidgetSnapshot.signedOut.isSignedIn)
        XCTAssertTrue(WidgetSnapshot.signedOut.openTitles.isEmpty)
        XCTAssertEqual(WidgetSnapshot.signedOut.timelineDates(now: now), [now])
    }

    func testStoreRoundTrips() throws {
        let store = WidgetSnapshotStore(url: temporaryFileURL("widget-snapshot.json"))
        XCTAssertNil(store.load())
        let snapshot = WidgetSnapshot(openTitles: ["Milk", "Eggs"], unloadEndDate: now.addingTimeInterval(60), now: now)
        try store.save(snapshot)
        XCTAssertEqual(store.load(), snapshot)
    }

    func testStoreTreatsGarbageAsMissing() throws {
        let url = temporaryFileURL("widget-snapshot.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("nope".utf8).write(to: url)
        XCTAssertNil(WidgetSnapshotStore(url: url).load())
    }
}

final class AppTabTests: XCTestCase {
    func testWidgetLinksOpenTheirTab() throws {
        for tab in AppTab.allCases {
            let url = try XCTUnwrap(URL(string: "smartgrocery://\(tab.rawValue)"))
            XCTAssertEqual(AppTab(url: url), tab)
        }
    }

    func testOtherURLsAreRejected() throws {
        XCTAssertNil(AppTab(url: try XCTUnwrap(URL(string: "smartgrocery://checkout"))))
        XCTAssertNil(AppTab(url: try XCTUnwrap(URL(string: "https://list"))))
        XCTAssertNil(AppTab(url: try XCTUnwrap(URL(string: "smartgrocery:list"))))
    }
}

final class AppStateWidgetTests: XCTestCase {
    func testSnapshotListsOnlyOpenItems() {
        let items = [GroceryItem(title: "Milk"), GroceryItem(title: "Eggs", isCompleted: true), GroceryItem(title: "Bread")]
        let snapshot = AppState.widgetSnapshot(items: items, isSignedIn: true, unloadEndDate: nil)
        XCTAssertEqual(snapshot.openTitles, ["Milk", "Bread"])
        XCTAssertEqual(snapshot.openCount, 2)
    }

    func testSignedOutSnapshotHidesTheList() {
        let snapshot = AppState.widgetSnapshot(items: [GroceryItem(title: "Milk")], isSignedIn: false, unloadEndDate: nil)
        XCTAssertEqual(snapshot, .signedOut)
    }

    @MainActor
    func testAppWritesSnapshotsForTheListCountdownAndSignOut() async throws {
        let store = WidgetSnapshotStore(url: temporaryFileURL("widget-snapshot.json"))
        let state = AppState(widgetStore: store)
        let user = AppUser(id: "widget-user", email: "w@b.c", displayName: "W")
        state.currentUser = user
        state.isAuthenticated = true
        state.startSync(for: user)

        try await state.listService.upsert(item: GroceryItem(title: "Apples"), userId: user.id)
        try await waitUntil { store.load()?.openTitles == ["Apples"] }

        state.homeArrivalTimer.start(duration: 600)
        try await waitUntil { store.load()?.unloadEndDate != nil }

        state.markUnloadComplete(source: "test")
        try await waitUntil { store.load()?.unloadEndDate == nil }

        state.signOut()
        try await waitUntil { store.load() == .signedOut }
    }
}
