import Foundation
import UserNotifications

@MainActor
final class NotificationService: ObservableObject {
    @Published var isAuthorized = false
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var pendingCount = 0

    private let center = UNUserNotificationCenter.current()

    init() {
        registerCategories()
    }

    func requestAuthorization() async {
        registerCategories()
        do {
            isAuthorized = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            isAuthorized = false
        }
        await refreshAuthorizationStatus()
        await refreshPendingCount()
    }

    /// Reads the current permission without prompting (it can change in Settings at any time).
    func refreshAuthorizationStatus() async {
        let status = await center.notificationSettings().authorizationStatus
        authorizationStatus = status
        isAuthorized = status == .authorized
    }

    func scheduleHomeArrivalReminder(
        after delay: TimeInterval,
        itemCount: Int,
        repeats: Bool,
        repeatInterval: TimeInterval
    ) async {
        center.removePendingNotificationRequests(withIdentifiers: [
            NotificationID.carUnload,
            NotificationID.carUnloadRepeat
        ])

        let content = Self.carUnloadContent(itemCount: itemCount, isRepeat: false)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(delay, 5), repeats: false)
        let request = UNNotificationRequest(identifier: NotificationID.carUnload, content: content, trigger: trigger)
        try? await center.add(request)

        if repeats {
            let repeatContent = Self.carUnloadContent(itemCount: itemCount, isRepeat: true)
            let repeatTrigger = UNTimeIntervalNotificationTrigger(timeInterval: max(delay + repeatInterval, 60), repeats: false)
            let repeatRequest = UNNotificationRequest(
                identifier: NotificationID.carUnloadRepeat,
                content: repeatContent,
                trigger: repeatTrigger
            )
            try? await center.add(repeatRequest)
        }

        await refreshPendingCount()
    }

    /// The car-unload reminder. It carries the item count so "Remind again" works even when the
    /// action cold-launches the app before the list has loaded.
    static func carUnloadContent(itemCount: Int, isRepeat: Bool) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = isRepeat ? "Still need to unload?" : "Groceries still in the car?"
        content.body = itemCount == 1
            ? "You have 1 item waiting — don't forget to bring it inside."
            : "You have \(itemCount) items waiting — don't forget to bring them inside."
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.carUnload
        content.userInfo = [NotificationUserInfo.itemCount: itemCount]
        return content
    }

    func sendGroceryStoreReminder(itemCount: Int) async {
        guard itemCount > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "You're near a grocery store"
        content.body = "Your list has \(itemCount) open item\(itemCount == 1 ? "" : "s")."
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.storeVisit

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: NotificationID.storeVisit, content: content, trigger: trigger)
        try? await center.add(request)
        await refreshPendingCount()
    }

    func rescheduleRepeatingReminders(preferences: UserPreferences, items: [GroceryItem]) async {
        center.removePendingNotificationRequests(withIdentifiers: [NotificationID.dailyList])
        guard preferences.dailyListReminderEnabled else {
            await refreshPendingCount()
            return
        }

        var components = DateComponents()
        components.hour = preferences.reminderHour
        components.minute = preferences.reminderMinute

        let openCount = items.filter { !$0.isCompleted }.count
        let content = UNMutableNotificationContent()
        content.title = "Grocery list reminder"
        content.body = openCount == 0
            ? "Your list is clear — add anything you need for tomorrow."
            : "\(openCount) item\(openCount == 1 ? "" : "s") still on your list."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: NotificationID.dailyList, content: content, trigger: trigger)
        try? await center.add(request)
        await refreshPendingCount()
    }

    func markCarUnloadComplete() {
        center.removePendingNotificationRequests(withIdentifiers: [
            NotificationID.carUnload,
            NotificationID.carUnloadRepeat
        ])
        Task { await refreshPendingCount() }
    }

    private func registerCategories() {
        let done = UNNotificationAction(
            identifier: NotificationAction.markDone,
            title: "All brought in",
            options: [.foreground]
        )
        let snooze = UNNotificationAction(
            identifier: NotificationAction.snooze,
            title: "Remind again",
            options: []
        )
        let carUnload = UNNotificationCategory(
            identifier: NotificationCategory.carUnload,
            actions: [done, snooze],
            intentIdentifiers: []
        )
        let store = UNNotificationCategory(
            identifier: NotificationCategory.storeVisit,
            actions: [],
            intentIdentifiers: []
        )
        center.setNotificationCategories([carUnload, store])
    }

    private func refreshPendingCount() async {
        let requests = await center.pendingNotificationRequests()
        pendingCount = requests.count
    }
}

enum NotificationID {
    static let carUnload = "car-unload"
    static let carUnloadRepeat = "car-unload-repeat"
    static let storeVisit = "store-visit"
    static let dailyList = "daily-list"
}

enum NotificationCategory {
    static let carUnload = "CAR_UNLOAD"
    static let storeVisit = "STORE_VISIT"
}

enum NotificationUserInfo {
    static let itemCount = "itemCount"
}

enum NotificationAction {
    static let markDone = "MARK_DONE"
    static let snooze = "SNOOZE"
}
