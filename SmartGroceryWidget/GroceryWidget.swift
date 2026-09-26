import AppIntents
import SwiftUI
import WidgetKit

@main
struct SmartGroceryWidgetBundle: WidgetBundle {
    var body: some Widget {
        GroceryWidget()
    }
}

struct GroceryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.groceries, provider: GroceryProvider()) { entry in
            GroceryWidgetView(entry: entry)
        }
        .configurationDisplayName("Grocery list")
        .description("What's still on your list, and the unload countdown after you get home.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct GroceryEntry: TimelineEntry {
    let date: Date
    /// Nil when the app hasn't written anything yet or the App Group is unavailable.
    let snapshot: WidgetSnapshot?
}

struct GroceryProvider: TimelineProvider {
    private static let preview = WidgetSnapshot(openTitles: ["Milk", "Sourdough bread", "Bananas"], unloadEndDate: nil)

    func placeholder(in context: Context) -> GroceryEntry {
        GroceryEntry(date: Date(), snapshot: Self.preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (GroceryEntry) -> Void) {
        let saved = WidgetSnapshotStore.shared()?.load()
        completion(GroceryEntry(date: Date(), snapshot: context.isPreview ? (saved ?? Self.preview) : saved))
    }

    /// The app reloads the timeline when anything changes; the only change the widget makes on its
    /// own is the countdown ending.
    func getTimeline(in context: Context, completion: @escaping (Timeline<GroceryEntry>) -> Void) {
        let snapshot = WidgetSnapshotStore.shared()?.load()
        let entries = (snapshot ?? .signedOut).timelineDates(now: Date())
            .map { GroceryEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .never))
    }
}

struct GroceryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GroceryEntry

    var body: some View {
        content
            .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = entry.snapshot, snapshot.isSignedIn {
            if snapshot.isCountingDown(at: entry.date), let end = snapshot.unloadEndDate {
                countdown(until: end, snapshot: snapshot)
                    .widgetURL(URL(string: "smartgrocery://arrival"))
            } else {
                list(snapshot)
                    .widgetURL(URL(string: "smartgrocery://list"))
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "cart")
                    .font(.title2)
                    .foregroundStyle(.green)
                Text("Open Smart Grocery to see your list")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func list(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("\(snapshot.openCount) to buy", systemImage: "cart")
                    .font(.headline)
                    .foregroundStyle(.green)
                Spacer(minLength: 0)
            }
            if snapshot.openTitles.isEmpty {
                Text("Your list is clear")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(snapshot.openTitles.prefix(family == .systemSmall ? 3 : WidgetSnapshot.maxTitles), id: \.self) { title in
                Text("• \(title)")
                    .font(.footnote)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private func countdown(until end: Date, snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Unload", systemImage: "car")
                .font(.headline)
                .foregroundStyle(.orange)
            Text(end, style: .timer)
                .font(.title2.monospacedDigit().bold())
            Spacer(minLength: 0)
            Button(intent: MarkBroughtInIntent()) {
                Label("Brought in", systemImage: "checkmark")
                    .font(.footnote.bold())
            }
            .tint(.green)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
