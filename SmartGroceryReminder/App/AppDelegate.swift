import UIKit
import UserNotifications

/// Owns AppState so the notification delegate is in place before launch finishes.
/// That is required to receive an action (e.g. "All brought in") that cold-launched the app.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    let appState: AppState = {
        // Firebase must be configured before AppState picks its backend.
        FirebaseBootstrap.configureIfAvailable()
        return AppState(useMockBackend: !FirebaseBootstrap.isConfigured)
    }()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
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
        Task { @MainActor in
            await self.appState.handleNotificationAction(action, category: category)
            completionHandler()
        }
    }
}
