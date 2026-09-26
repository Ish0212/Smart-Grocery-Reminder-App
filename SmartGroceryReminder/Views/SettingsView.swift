import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var notificationService: NotificationService

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    if let user = appState.currentUser {
                        LabeledContent("Name", value: user.displayName)
                        LabeledContent("Email", value: user.email)
                    }
                    LabeledContent("Backend", value: appState.useMockBackend ? "Mock (prototype)" : "Firebase")
                    Button("Sign Out", role: .destructive) {
                        appState.signOut()
                    }
                }

                SharedListSection()

                Section("Daily list reminder") {
                    Toggle("Enabled", isOn: $appState.preferences.dailyListReminderEnabled)
                    DatePicker(
                        "Time",
                        selection: reminderDateBinding,
                        displayedComponents: .hourAndMinute
                    )
                    .disabled(!appState.preferences.dailyListReminderEnabled)
                }

                Section("Location reminders") {
                    Toggle("When entering a grocery store", isOn: $appState.preferences.storeEntryReminderEnabled)
                    Toggle("Repeat car-unload reminder", isOn: $appState.preferences.repeatCarUnloadReminder)
                }

                Section("Notifications") {
                    LabeledContent("Permission", value: notificationService.authorizationStatus == .authorized ? "Granted" : "Not granted")
                    LabeledContent("Pending", value: "\(notificationService.pendingCount)")
                    Button("Request notification access") {
                        Task { await notificationService.requestAuthorization() }
                    }
                }

                ReminderStatsSection(diagnostics: appState.diagnostics)

                Section {
                    NavigationLink("Diagnostics") {
                        DiagnosticsView(diagnostics: appState.diagnostics)
                    }
                } header: {
                    Text("Troubleshooting")
                } footer: {
                    Text("Reminder health checklist and a log of location and reminder events.")
                }

                Section("About") {
                    Text("Prototype for location-aware grocery lists, home-arrival unload timers, and Firebase-ready sync.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .task { await notificationService.refreshAuthorizationStatus() }
            .onChange(of: appState.preferences) { _, _ in
                Task { await appState.savePreferences() }
            }
        }
    }

    private var reminderDateBinding: Binding<Date> {
        Binding {
            Calendar.current.date(
                from: DateComponents(
                    hour: appState.preferences.reminderHour,
                    minute: appState.preferences.reminderMinute
                )
            ) ?? Date()
        } set: { date in
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
            appState.preferences.reminderHour = components.hour ?? 17
            appState.preferences.reminderMinute = components.minute ?? 30
        }
    }
}

/// On-device stats from the diagnostics log; observes the log so it updates live.
private struct ReminderStatsSection: View {
    @ObservedObject var diagnostics: DiagnosticsLog

    var body: some View {
        let stats = ReminderStats.compute(from: diagnostics.entries)
        Section {
            LabeledContent("Unload reminders", value: "\(stats.unloadScheduled)")
            LabeledContent("Brought in", value: "\(stats.unloadDone)")
            LabeledContent("Snoozed", value: "\(stats.snoozed)")
            LabeledContent("Store reminders", value: "\(stats.storeRemindersSent)")
            LabeledContent("Done rate", value: stats.doneRate.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—")
            LabeledContent("Median time to done", value: stats.medianMinutesToDone.map { "\(Int($0.rounded())) min" } ?? "—")
        } header: {
            Text("Reminder stats")
        } footer: {
            Text("From the last \(diagnostics.entries.count) logged events. Computed on this iPhone; nothing is sent anywhere.")
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
        .environmentObject(NotificationService())
}
