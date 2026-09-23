import SwiftUI
import UIKit

/// For field testing: is everything set up for background reminders, what does iOS think about
/// each geofence, and what happened while the phone was in a pocket.
struct DiagnosticsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var notificationService: NotificationService
    @ObservedObject var diagnostics: DiagnosticsLog
    @Environment(\.openURL) private var openURL

    @State private var backgroundRefresh: UIBackgroundRefreshStatus = .available
    @State private var lowPowerMode = false

    var body: some View {
        List {
            Section {
                ForEach(healthItems) { item in
                    healthRow(item)
                }
                Button("Open iOS Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
            } header: {
                Text("Reminder health")
            } footer: {
                Text("Everything should be green before a field test. Orange items can delay or block background wake-ups.")
            }

            Section {
                if locationService.regionStates.isEmpty {
                    Text("No answer from iOS yet. Tap Check now.")
                        .foregroundStyle(.secondary)
                }
                ForEach(locationService.regionStates.keys.sorted(), id: \.self) { identifier in
                    LabeledContent(
                        LocationService.describe(regionIdentifier: identifier),
                        value: LocationService.describe(locationService.regionStates[identifier] ?? .unknown)
                    )
                }
                Button("Check now") {
                    locationService.refreshRegionStates()
                }
            } header: {
                Text("Geofences")
            } footer: {
                Text("A place you are already inside when it is added only fires after you leave and come back.")
            }

            Section {
                Button("Copy log") {
                    UIPasteboard.general.string = diagnostics.exportText()
                }
                .disabled(diagnostics.entries.isEmpty)
                Button("Clear log", role: .destructive) {
                    diagnostics.clear()
                }
                .disabled(diagnostics.entries.isEmpty)

                if diagnostics.entries.isEmpty {
                    Text("No events yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(diagnostics.entries.reversed())) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.message)
                            .font(.subheadline)
                        Text("\(entry.date.formatted(date: .abbreviated, time: .standard)) · \(entry.kind.rawValue)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("Event log (newest first)")
            }
        }
        .navigationTitle("Diagnostics")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: diagnostics.exportText()) {
                    Label("Share log", systemImage: "square.and.arrow.up")
                }
            }
        }
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    private var healthItems: [HealthItem] {
        let prefs = appState.preferences
        return ReminderHealth.check(
            authorization: locationService.authorizationStatus,
            accuracy: locationService.accuracyAuthorization,
            notifications: notificationService.authorizationStatus,
            backgroundRefresh: backgroundRefresh,
            lowPowerMode: lowPowerMode,
            hasHome: prefs.homeLocation != nil,
            systemRegionCount: locationService.systemRegionCount,
            expectedRegionCount: (prefs.homeLocation == nil ? 0 : 1) + prefs.savedStores.count
        )
    }

    private func healthRow(_ item: HealthItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: item.isOK ? "checkmark.circle.fill" : (item.isWarningOnly ? "exclamationmark.triangle.fill" : "xmark.octagon.fill"))
                .foregroundStyle(item.isOK ? Color.green : (item.isWarningOnly ? Color.orange : Color.red))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                if !item.isOK, let fix = item.fix {
                    Text(fix)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(item.isOK ? "OK" : (item.isWarningOnly ? "Warning" : "Needs fixing"))
    }

    private func refresh() async {
        await notificationService.refreshAuthorizationStatus()
        backgroundRefresh = UIApplication.shared.backgroundRefreshStatus
        lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        locationService.refreshRegionStates()
    }
}

#Preview {
    let state = AppState()
    return NavigationStack {
        DiagnosticsView(diagnostics: state.diagnostics)
    }
    .environmentObject(state)
    .environmentObject(state.locationService)
    .environmentObject(state.notificationService)
}
