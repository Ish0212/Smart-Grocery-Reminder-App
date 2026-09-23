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
}
