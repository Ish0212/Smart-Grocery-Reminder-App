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

    /// `Application Support/SmartGrocery/<fileName>` in the app's container.
    static func appSupport(_ fileName: String) -> JSONFileStore<Value> {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return JSONFileStore(
            url: base.appendingPathComponent("SmartGrocery", isDirectory: true).appendingPathComponent(fileName)
        )
    }
}
