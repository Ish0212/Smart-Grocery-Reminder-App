import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var notificationService: NotificationService

    @State private var isConfirmingDeletion = false
    @State private var deletionPassword = ""
    @State private var isDeletingAccount = false
    @State private var deletionError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    if let user = appState.currentUser {
                        LabeledContent("Name", value: user.displayName)
                        LabeledContent("Email", value: user.email)
                    }
                    if appState.showsTestTools {
                        LabeledContent("Backend", value: appState.useMockBackend ? "Mock (prototype)" : "Firebase")
                    }
                    Button("Sign Out", role: .destructive) {
                        appState.signOut()
                    }
                    .disabled(isDeletingAccount)
                    Button("Delete Account", role: .destructive) {
                        deletionPassword = ""
                        deletionError = nil
                        isConfirmingDeletion = true
                    }
                    .disabled(isDeletingAccount)
                    if isDeletingAccount {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Deleting your account…")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let deletionError {
                        Text(deletionError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                SharedListSection()

                Section("Daily list reminder") {
                    Toggle(isOn: $appState.preferences.dailyListReminderEnabled) {
                        Label { Text("Enabled") } icon: { IconBadge(systemImage: "list.bullet", color: .blue) }
                    }
                    DatePicker(
                        "Time",
                        selection: reminderDateBinding,
                        displayedComponents: .hourAndMinute
                    )
                    .disabled(!appState.preferences.dailyListReminderEnabled)
                }

                Section("Location reminders") {
                    Toggle(isOn: $appState.preferences.storeEntryReminderEnabled) {
                        Label { Text("When entering a grocery store") } icon: { IconBadge(systemImage: "cart.fill", color: .orange) }
                    }
                    Toggle(isOn: $appState.preferences.repeatCarUnloadReminder) {
                        Label { Text("Repeat car-unload reminder") } icon: { IconBadge(systemImage: "car.fill", color: .pink) }
                    }
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
                    NavigationLink {
                        DiagnosticsView(diagnostics: appState.diagnostics)
                    } label: {
                        Label { Text("Diagnostics") } icon: { IconBadge(systemImage: "stethoscope", color: .gray) }
                    }
                } header: {
                    Text("Troubleshooting")
                } footer: {
                    Text("Reminder health checklist and a log of location and reminder events.")
                }

                Section("About") {
                    LabeledContent("Version", value: Self.version)
                    if let privacyPolicy = AppLinks.privacyPolicy {
                        Link("Privacy Policy", destination: privacyPolicy)
                    }
                    if let support = AppLinks.support {
                        Link("Support", destination: support)
                    }
                }
            }
            .navigationTitle("Settings")
            .alert("Delete your account?", isPresented: $isConfirmingDeletion) {
                SecureField("Password", text: $deletionPassword)
                Button("Delete", role: .destructive, action: deleteAccount)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(deletionWarning)
            }
            .task {
                await notificationService.refreshAuthorizationStatus()
                // Reminders delivered since the count was last read are no longer pending.
                await notificationService.refreshPendingCount()
            }
            .onChange(of: appState.preferences) { _, _ in
                Task { await appState.savePreferences() }
            }
        }
    }

    private var deletionWarning: String {
        let userId = appState.currentUser?.id
        let onOwnList = appState.activeListId == nil || appState.activeListId == userId
        var warning = "This permanently deletes your account, your list, saved places and settings."
        if !onOwnList {
            warning += " You'll leave the list you joined; its owner keeps it."
        } else if appState.sharedList?.isShared == true {
            warning += " The people you share your list with will lose it too."
        }
        return warning + " Enter your password to confirm."
    }

    private func deleteAccount() {
        let password = deletionPassword
        deletionPassword = ""
        deletionError = nil
        isDeletingAccount = true
        Task {
            do {
                // On success the app returns to the sign-in screen.
                try await appState.deleteAccount(password: password)
            } catch {
                deletionError = "Couldn't delete your account: \(error.localizedDescription)"
            }
            isDeletingAccount = false
        }
    }

    /// e.g. "1.0 (12)": the marketing version and the build number.
    private static var version: String {
        let info = Bundle.main.infoDictionary
        let marketing = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(marketing) (\(build))"
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
