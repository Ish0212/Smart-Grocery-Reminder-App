import SwiftUI

@main
struct SmartGroceryReminderApp: App {
    @StateObject private var appState = AppState()

    init() {
        FirebaseBootstrap.configureIfAvailable()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(appState.locationService)
                .environmentObject(appState.notificationService)
                .environmentObject(appState.homeArrivalTimer)
        }
    }
}
