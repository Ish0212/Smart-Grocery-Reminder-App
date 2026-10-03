import UIKit
import UserNotifications

/// Owns AppState so the notification delegate is in place before launch finishes.
/// That is required to receive an action (e.g. "All brought in") that cold-launched the app.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Under XCTest the host app keeps everything in memory on the demo backend, with inert
    /// location and notification services, so tests never restore a saved session, request
    /// permissions, or touch the device's saved data, geofences or notifications.
    private static let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        || NSClassFromString("XCTestCase") != nil

    /// Set by the screenshot UI test (AppStoreScreenshots.swift). Read from the arguments, not
    /// UserDefaults, which the privacy manifest would have to declare.
    private static let isTakingScreenshots = ProcessInfo.processInfo.arguments.contains("--app-store-screenshots")

    #if DEBUG
    private static let isDebugBuild = true
    #else
    private static let isDebugBuild = false
    #endif

    let appState: AppState = {
        let isTesting = AppDelegate.isTesting
        // Firebase must be configured before AppState picks its backend.
        if !isTesting {
            FirebaseBootstrap.configureIfAvailable()
        }
        let useMockBackend = isTesting || !FirebaseBootstrap.isConfigured
        let state = AppState(
            useMockBackend: useMockBackend,
            mockStorageDirectory: isTesting ? nil : AppFiles.directory,
            diagnostics: DiagnosticsLog(store: isTesting ? nil : JSONFileStore<[DiagnosticEntry]>.appSupport("diagnostics.json")),
            backgroundActivity: isTesting ? NoBackgroundActivity() : UIKitBackgroundActivity(),
            stateDirectory: isTesting ? nil : AppFiles.directory,
            widgetStore: isTesting ? nil : WidgetSnapshotStore.shared(),
            systemServices: !isTesting,
            showsTestTools: AppState.showsTestTools(
                useMockBackend: useMockBackend,
                isDebugBuild: AppDelegate.isDebugBuild,
                takingScreenshots: AppDelegate.isTakingScreenshots
            )
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
        if !Self.isTesting {
            appState.restoreSession()
        }
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
        let userInfo = response.notification.request.content.userInfo
        let itemCount = userInfo[NotificationUserInfo.itemCount] as? Int
        let repeatInterval = userInfo[NotificationUserInfo.repeatInterval] as? TimeInterval
        let scheduledAt = (userInfo[NotificationUserInfo.scheduledAt] as? TimeInterval).map(Date.init(timeIntervalSince1970:))
        Task { @MainActor in
            await self.appState.handleNotificationAction(
                action,
                category: category,
                itemCount: itemCount,
                repeatInterval: repeatInterval,
                scheduledAt: scheduledAt
            )
            completionHandler()
        }
    }
}
