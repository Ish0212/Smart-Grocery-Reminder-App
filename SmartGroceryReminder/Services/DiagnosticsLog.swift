import Foundation

/// One line in the diagnostics log: something the app saw or did, and when.
struct DiagnosticEntry: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case launch, session
        case regionEnter, regionExit, regionState, regionUnknown
        case queued, dropped, skipped
        case unloadScheduled, storeReminderSent, unloadDone, snoozed
        case monitoring, permission, error
    }

    var id = UUID()
    let date: Date
    let kind: Kind
    let message: String
    var placeKind: GeoPlace.PlaceKind?
    var placeId: String?
}

/// A capped log of location and reminder events, so a field test can show what happened
/// while the phone was in a pocket. The default instance keeps entries in memory only.
@MainActor
final class DiagnosticsLog: ObservableObject {
    @Published private(set) var entries: [DiagnosticEntry]

    private let store: JSONFileStore<[DiagnosticEntry]>?
    private let capacity: Int
    /// False when the saved log exists but couldn't be read, so it is never overwritten.
    private let canSave: Bool

    init(store: JSONFileStore<[DiagnosticEntry]>? = nil, capacity: Int = 300) {
        self.store = store
        self.capacity = capacity
        var loaded: [DiagnosticEntry] = []
        var canSave = store != nil
        if let store {
            switch store.load() {
            case .loaded(let saved): loaded = saved
            case .missing, .corrupt: break
            case .unreadable: canSave = false
            }
        }
        self.entries = Array(loaded.suffix(capacity))
        self.canSave = canSave
    }

    func record(
        _ kind: DiagnosticEntry.Kind,
        _ message: String,
        placeKind: GeoPlace.PlaceKind? = nil,
        placeId: String? = nil,
        date: Date = Date()
    ) {
        entries.append(DiagnosticEntry(date: date, kind: kind, message: message, placeKind: placeKind, placeId: placeId))
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    /// Plain text for sharing, oldest first.
    func exportText() -> String {
        let formatter = ISO8601DateFormatter()
        return entries
            .map { "\(formatter.string(from: $0.date)) [\($0.kind.rawValue)] \($0.message)" }
            .joined(separator: "\n")
    }

    private func save() {
        guard canSave, let store else { return }
        try? store.save(entries)
    }
}
