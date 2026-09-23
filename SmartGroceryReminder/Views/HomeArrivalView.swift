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
            Label(timer.isActive ? "Unload timer running" : "Ready for arrival", systemImage: timer.isActive ? "timer" : "house")
                .font(.headline)
                .foregroundStyle(Color("AccentGreen"))

            if timer.isActive {
                Text(timer.formattedRemaining)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .accessibilityLabel("\(timer.remainingSeconds / 60) minutes \(timer.remainingSeconds % 60) seconds remaining")
            } else {
                Text("When you arrive home, a timer starts. After it ends, you'll get a reminder to bring groceries inside.")
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

    private var delayPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Remind me after")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 10)], spacing: 10) {
                ForEach(timer.presetDelays, id: \.seconds) { preset in
                    Button(preset.label) {
                        timer.selectedDelay = preset.seconds
                        appState.preferences.homeArrivalDelay = preset.seconds
                        Task { await appState.savePreferences() }
                    }
                    .buttonStyle(.bordered)
                    .tint(timer.selectedDelay == preset.seconds ? Color("AccentGreen") : .secondary)
                    .accessibilityLabel("Remind after \(preset.label)")
                    .accessibilityAddTraits(timer.selectedDelay == preset.seconds ? .isSelected : [])
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
        )
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                // AppState handles it like a real arrival: timer + reminder.
                locationService.simulateArriveHome()
            } label: {
                Label("Simulate arrive home", systemImage: "location.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color("AccentGreen"))

            if timer.isActive {
                Button(role: .destructive) {
                    appState.markUnloadComplete(source: "app")
                } label: {
                    Label("Mark groceries brought in", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How it works")
                .font(.headline)
            Text("1. Geofence detects arrival at your saved home.\n2. Your chosen delay starts counting down.\n3. A notification asks you to unload — with repeat + completion actions.")
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
