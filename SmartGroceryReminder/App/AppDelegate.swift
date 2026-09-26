import UIKit
import UserNotifications

/// Owns AppState so the notification delegate is in place before launch finishes.
/// That is required to receive an action (e.g. "All brought in") that cold-launched the app.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    let appState: AppState = {
        // Firebase must be configured before AppState picks its backend.
        FirebaseBootstrap.configureIfAvailable()
        // Under XCTest the host app keeps everything in memory, so tests never restore a saved
        // session (which would request permissions) or touch the device's saved data.
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let state = AppState(
            useMockBackend: !FirebaseBootstrap.isConfigured,
            mockStorageDirectory: isTesting ? nil : AppFiles.directory,
            diagnostics: DiagnosticsLog(store: isTesting ? nil : JSONFileStore<[DiagnosticEntry]>.appSupport("diagnostics.json")),
            backgroundActivity: isTesting ? NoBackgroundActivity() : UIKitBackgroundActivity(),
            stateDirectory: isTesting ? nil : AppFiles.directory,
            widgetStore: isTesting ? nil : WidgetSnapshotStore.shared()
        )
        // With @UIApplicationDelegateAdaptor, UIApplication.shared.delegate is SwiftUI's own
        // delegate, so App Intents reach this state through AppState.shared instead.
        AppState.shared = state
        return state
    }()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        let launchedForLocation = launchOptions?[.location] != nil
        let inBackground = application.applicationState == .background
        appState.diagnostics.record(
            .launch,
            launchedForLocation
                ? "Launched by a location event\(inBackground ? " (in the background)" : "")"
                : (inBackground ? "Launched in the background" : "Launched")
        )
        appState.restoreSession()
        return true
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show reminders even while the app is open.
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let action = response.actionIdentifier
        let category = response.notification.request.content.categoryIdentifier
        let itemCount = response.notification.request.content.userInfo[NotificationUserInfo.itemCount] as? Int
        Task { @MainActor in
            await self.appState.handleNotificationAction(action, category: category, itemCount: itemCount)
            completionHandler()
        }
    }
}
