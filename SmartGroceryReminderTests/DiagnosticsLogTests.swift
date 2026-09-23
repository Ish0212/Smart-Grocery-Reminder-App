import XCTest
@testable import SmartGroceryReminder

final class JSONFileStoreTests: XCTestCase {
    func testMissingFile() {
        let store = JSONFileStore<[String]>(url: temporaryFileURL())
        guard case .missing = store.load() else { return XCTFail("Expected .missing") }
    }

    func testSaveThenLoad() throws {
        let store = JSONFileStore<[String]>(url: temporaryFileURL())
        try store.save(["milk", "eggs"])
        guard case .loaded(let value) = store.load() else { return XCTFail("Expected .loaded") }
        XCTAssertEqual(value, ["milk", "eggs"])
    }

    func testGarbageIsCorrupt() throws {
        let url = temporaryFileURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        guard case .corrupt = JSONFileStore<[String]>(url: url).load() else { return XCTFail("Expected .corrupt") }
    }

    func testDirectoryIsUnreadable() throws {
        let url = temporaryFileURL()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        guard case .unreadable = JSONFileStore<[String]>(url: url).load() else { return XCTFail("Expected .unreadable") }
    }
}

final class DiagnosticsLogTests: XCTestCase {
    @MainActor
    func testCapacityDropsOldestEntries() {
        let log = DiagnosticsLog(capacity: 3)
        for index in 1...5 {
            log.record(.monitoring, "event \(index)")
        }
        XCTAssertEqual(log.entries.map(\.message), ["event 3", "event 4", "event 5"])
    }

    @MainActor
    func testEntriesSurviveANewInstance() {
        let store = JSONFileStore<[DiagnosticEntry]>(url: temporaryFileURL())
        let first = DiagnosticsLog(store: store)
        first.record(.regionEnter, "Entered Home", placeKind: .home, placeId: "default-home")

        let second = DiagnosticsLog(store: store)
        XCTAssertEqual(second.entries, first.entries)
        XCTAssertEqual(second.entries.first?.placeKind, .home)
    }

    @MainActor
    func testClearAlsoClearsTheFile() {
        let store = JSONFileStore<[DiagnosticEntry]>(url: temporaryFileURL())
        let log = DiagnosticsLog(store: store)
        log.record(.launch, "Launched")
        log.clear()

        XCTAssertTrue(log.entries.isEmpty)
        XCTAssertTrue(DiagnosticsLog(store: store).entries.isEmpty)
    }

    @MainActor
    func testUnreadableLogIsNeverOverwritten() throws {
        let url = temporaryFileURL()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let log = DiagnosticsLog(store: JSONFileStore(url: url))

        log.record(.launch, "Launched")

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertEqual(log.entries.count, 1)
    }

    @MainActor
    func testExportTextListsKindAndMessage() {
        let log = DiagnosticsLog()
        log.record(.unloadScheduled, "Unload reminder in 5 min")
        XCTAssertTrue(log.exportText().contains("[unloadScheduled] Unload reminder in 5 min"))
    }
}
