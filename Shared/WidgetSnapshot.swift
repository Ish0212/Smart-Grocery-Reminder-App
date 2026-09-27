import Foundation

/// What the home-screen widget shows. The app writes it into the App Group container whenever
/// the list, sign-in, unload countdown or unload reminder changes; the widget only reads it.
struct WidgetSnapshot: Codable, Equatable {
    /// How many item titles the widget has room for.
    static let maxTitles = 4

    var isSignedIn: Bool
    var openCount: Int
    /// The first few unchecked items, in list order.
    var openTitles: [String]
    /// When the running unload countdown ends; nil when none is running.
    var unloadEndDate: Date?
    /// The unload reminder was scheduled (it may have fired already) and the groceries haven't
    /// been marked brought in.
    var unloadOutstanding: Bool

    static let signedOut = WidgetSnapshot(isSignedIn: false, openCount: 0, openTitles: [], unloadEndDate: nil)

    init(isSignedIn: Bool, openCount: Int, openTitles: [String], unloadEndDate: Date?, unloadOutstanding: Bool = false) {
        self.isSignedIn = isSignedIn
        self.openCount = openCount
        self.openTitles = openTitles
        self.unloadEndDate = unloadEndDate
        self.unloadOutstanding = unloadOutstanding
    }

    /// - Parameters:
    ///   - openTitles: every unchecked item's title, in list order.
    ///   - unloadEndDate: the countdown's end; dropped if it has already passed.
    init(openTitles: [String], unloadEndDate: Date?, unloadOutstanding: Bool = false, now: Date = Date()) {
        self.init(
            isSignedIn: true,
            openCount: openTitles.count,
            openTitles: Array(openTitles.prefix(Self.maxTitles)),
            unloadEndDate: unloadEndDate.flatMap { $0 > now ? $0 : nil },
            unloadOutstanding: unloadOutstanding
        )
    }

    private enum CodingKeys: String, CodingKey {
        case isSignedIn, openCount, openTitles, unloadEndDate, unloadOutstanding
    }

    /// A snapshot saved by an older version has no `unloadOutstanding`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isSignedIn = try container.decode(Bool.self, forKey: .isSignedIn)
        openCount = try container.decode(Int.self, forKey: .openCount)
        openTitles = try container.decode([String].self, forKey: .openTitles)
        unloadEndDate = try container.decodeIfPresent(Date.self, forKey: .unloadEndDate)
        unloadOutstanding = try container.decodeIfPresent(Bool.self, forKey: .unloadOutstanding) ?? false
    }

    func isCountingDown(at date: Date) -> Bool {
        unloadEndDate.map { $0 > date } ?? false
    }

    /// When the widget has to change on its own: now, and when the countdown ends.
    func timelineDates(now: Date) -> [Date] {
        guard let end = unloadEndDate, end > now else { return [now] }
        return [now, end]
    }
}

enum AppGroup {
    static let identifier = "group.com.smartgrocery.reminder"
}

enum WidgetKind {
    static let groceries = "GroceryWidget"
}

/// `widget-snapshot.json` in the App Group container, shared by the app and the widget.
struct WidgetSnapshotStore {
    let url: URL

    /// Nil when the App Group isn't available (e.g. a sideloaded build that lost the entitlement).
    static func shared() -> WidgetSnapshotStore? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)
            .map { WidgetSnapshotStore(url: $0.appendingPathComponent("widget-snapshot.json")) }
    }

    func load() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save(_ snapshot: WidgetSnapshot) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        // Readable while locked after the first unlock, so the widget can refresh on the lock screen.
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
