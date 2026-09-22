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
                    LabeledContent("Permission", value: notificationService.isAuthorized ? "Granted" : "Not granted")
                    LabeledContent("Pending", value: "\(notificationService.pendingCount)")
                    Button("Request notification access") {
                        Task { await notificationService.requestAuthorization() }
                    }
                }

                Section("About") {
                    Text("Prototype for location-aware grocery lists, home-arrival unload timers, and Firebase-ready sync.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
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

#Preview {
    SettingsView()
        .environmentObject(AppState())
        .environmentObject(NotificationService())
}
