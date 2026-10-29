import SwiftUI

struct HomeArrivalView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var timer: HomeArrivalTimerService

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    statusCard
                    delayPicker
                    actions
                    explanation
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Home Arrival")
            .onAppear {
                timer.selectedDelay = appState.preferences.homeArrivalDelay
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(statusTitle, systemImage: statusIcon)
                .font(.headline)
                .foregroundStyle(Color("AccentGreen"))

            if timer.isActive {
                Text(timer.formattedRemaining)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .accessibilityLabel("\(timer.remainingSeconds / 60) minutes \(timer.remainingSeconds % 60) seconds remaining")
            } else if appState.unloadOutstanding {
                Text("Reminder sent — groceries still in the car?")
                    .foregroundStyle(.secondary)
            } else {
                Text("When you get home from shopping, a timer starts. After it ends, you'll get a reminder to bring groceries inside.")
                    .foregroundStyle(.secondary)
            }

            Text(locationService.lastEventDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
        )
    }

    private var statusTitle: String {
        if timer.isActive { return "Unload timer running" }
        return appState.unloadOutstanding ? "Reminder sent" : "Ready for arrival"
    }

    private var statusIcon: String {
        if timer.isActive { return "timer" }
        return appState.unloadOutstanding ? "bell.badge" : "house"
    }

    private var delayPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Remind me after")
                .font(.headline)

            // Segments never wrap, unlike buttons in a grid ("30 min" broke onto two lines).
            Picker("Remind me after", selection: delayBinding) {
                ForEach(timer.presetDelays, id: \.seconds) { preset in
                    Text(preset.label).tag(preset.seconds)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
        )
    }

    private var delayBinding: Binding<TimeInterval> {
        Binding {
            timer.selectedDelay
        } set: { seconds in
            timer.selectedDelay = seconds
            appState.preferences.homeArrivalDelay = seconds
            Task { await appState.savePreferences() }
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            if appState.showsTestTools {
                Button {
                    // AppState handles it like a real arrival: timer + reminder.
                    locationService.simulateArriveHome()
                } label: {
                    Label("Simulate arrive home", systemImage: "location.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .prominentGlassButtonStyle()
                .tint(Color("AccentGreen"))
            }

            // Also after the countdown ends, until the groceries are marked brought in.
            if timer.isActive || appState.unloadOutstanding {
                Button(role: .destructive) {
                    appState.markUnloadComplete(source: "app")
                } label: {
                    Label("Mark groceries brought in", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .glassButtonStyle()
            }
        }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How it works")
                .font(.headline)
            Text("1. Check off what you buy, or visit a saved store.\n2. When you get home, your chosen delay starts counting down.\n3. A notification asks you to unload. Tap it to come back here, or use Remind again or All brought in.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
    }
}

#Preview {
    let state = AppState()
    return HomeArrivalView()
        .environmentObject(state)
        .environmentObject(state.locationService)
        .environmentObject(state.homeArrivalTimer)
}
