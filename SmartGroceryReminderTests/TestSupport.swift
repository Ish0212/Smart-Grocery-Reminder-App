import XCTest

extension XCTestCase {
    /// A file URL inside a fresh temporary directory that is removed after the test.
    func temporaryFileURL(_ name: String = "store.json") -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory.appendingPathComponent(name)
    }

    /// Sync results arrive asynchronously; poll on the main actor until `condition` holds.
    @MainActor
    func waitUntil(_ condition: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for condition")
    }
}
