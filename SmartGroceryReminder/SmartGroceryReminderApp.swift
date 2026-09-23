import SwiftUI

@main
struct SmartGroceryReminderApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(delegate.appState)
                .environmentObject(delegate.appState.locationService)
                .environmentObject(delegate.appState.notificationService)
                .environmentObject(delegate.appState.homeArrivalTimer)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                delegate.appState.homeArrivalTimer.refresh()
            }
        }
    }
}
