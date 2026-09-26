import Foundation

enum FileLoadResult<Value> {
    case missing
    case loaded(Value)
    /// The file exists but doesn't decode. Starting fresh (and overwriting it) is safe.
    case corrupt
    /// The file exists but can't be read, e.g. when iOS relaunches the app for a location event
    /// before the first unlock after a reboot. Don't overwrite it: that would replace real data with defaults.
    case unreadable
}

/// A Codable value kept in one JSON file.
struct JSONFileStore<Value: Codable> {
    let url: URL

    func load() -> FileLoadResult<Value> {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return .missing
        } catch {
            return .unreadable
        }
        do {
            return .loaded(try JSONDecoder().decode(Value.self, from: data))
        } catch {
            return .corrupt
        }
    }

    func save(_ value: Value) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(value)
        // Readable after the first unlock, so background relaunches (device locked) can still load it.
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }

    /// A file in `AppFiles.directory`.
    static func appSupport(_ fileName: String) -> JSONFileStore<Value> {
        JSONFileStore(url: AppFiles.directory.appendingPathComponent(fileName))
    }
}

enum AppFiles {
    /// `Application Support/SmartGrocery/` in the app's container: the demo backend's data and the diagnostics log.
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SmartGrocery", isDirectory: true)
    }
}
