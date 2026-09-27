import Foundation
import UserNotifications

@MainActor
final class NotificationService: ObservableObject {
    @Published var isAuthorized = false
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var pendingCount = 0

    /// `nil` when inert (tests): nothing is scheduled and no permission is requested.
    private let center: UNUserNotificationCenter?
    /// Inert mode only: every request that would have been scheduled, in order.
    private(set) var scheduledForTesting: [UNNotificationRequest] = []
    /// Inert mode only: every pending identifier that would have been removed, in order.
    private(set) var removedForTesting: [String] = []
    /// Inert mode only: every delivered identifier that would have been removed from Notification Center, in order.
    private(set) var removedDeliveredForTesting: [String] = []
    /// Inert mode only: the identifiers that would still be pending.
    private var pendingForTesting: Set<String> = []
    /// Inert mode only: refuse every request, as iOS does when it can't schedule one.
    var refusesRequestsForTesting = false

    /// - Parameter center: `nil` for an inert service that only records what it would schedule and remove.
    init(center: UNUserNotificationCenter? = UNUserNotificationCenter.current()) {
        self.center = center
        registerCategories()
    }

    var isInert: Bool { center == nil }

    func requestAuthorization() async {
        guard let center else { return }
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
        guard let center else { return }
        let status = await center.notificationSettings().authorizationStatus
        authorizationStatus = status
        isAuthorized = status == .authorized
    }

    /// Returns false if iOS refused the reminder; the repeat is only added after the first one.
    /// `repeatInterval` is also stored in the reminder for "Remind again", even when `repeats` is false.
    /// Earlier car-unload reminders still in Notification Center are removed, so only this one can be acted on.
    @discardableResult
    func scheduleHomeArrivalReminder(
        after delay: TimeInterval,
        itemCount: Int,
        repeats: Bool,
        repeatInterval: TimeInterval,
        scheduledAt: Date = Date()
    ) async -> Bool {
        removePending(NotificationID.carUnloadReminders)
        removeDelivered(NotificationID.carUnloadReminders)

        let content = Self.carUnloadContent(
            itemCount: itemCount, isRepeat: false, repeatInterval: repeatInterval, scheduledAt: scheduledAt
        )
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(delay, 5), repeats: false)
        let request = UNNotificationRequest(identifier: NotificationID.carUnload, content: content, trigger: trigger)
        let added = await add(request)

        if repeats, added {
            let repeatContent = Self.carUnloadContent(
                itemCount: itemCount, isRepeat: true, repeatInterval: repeatInterval, scheduledAt: scheduledAt
            )
            let repeatTrigger = UNTimeIntervalNotificationTrigger(timeInterval: max(delay + repeatInterval, 60), repeats: false)
            let repeatRequest = UNNotificationRequest(
                identifier: NotificationID.carUnloadRepeat,
                content: repeatContent,
                trigger: repeatTrigger
            )
            await add(repeatRequest)
        }

        await refreshPendingCount()
        return added
    }

    /// The car-unload reminder. It carries the item count and the repeat interval so "Remind again"
    /// works even when the action cold-launches the app before the list and preferences have
    /// loaded, and when it was scheduled, so "Remind again" after "All brought in" does nothing.
    /// A count of 0 (a store visit with nothing on the list) asks about "your groceries".
    static func carUnloadContent(
        itemCount: Int,
        isRepeat: Bool,
        repeatInterval: TimeInterval,
        scheduledAt: Date
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = isRepeat ? "Still need to unload?" : "Groceries still in the car?"
        switch itemCount {
        case 0:
            content.body = "Don't forget to bring your groceries inside."
        case 1:
            content.body = "You have 1 item waiting — don't forget to bring it inside."
        default:
            content.body = "You have \(itemCount) items waiting — don't forget to bring them inside."
        }
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.carUnload
        content.userInfo = [
            NotificationUserInfo.itemCount: itemCount,
            NotificationUserInfo.repeatInterval: repeatInterval,
            NotificationUserInfo.scheduledAt: scheduledAt.timeIntervalSince1970,
        ]
        return content
    }

    /// Returns false if there was nothing to send or iOS refused it.
    @discardableResult
    func sendGroceryStoreReminder(itemCount: Int) async -> Bool {
        guard itemCount > 0 else { return false }
        let content = UNMutableNotificationContent()
        content.title = "You're near a grocery store"
        content.body = "Your list has \(itemCount) open item\(itemCount == 1 ? "" : "s")."
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.storeVisit

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: NotificationID.storeVisit, content: content, trigger: trigger)
        let added = await add(request)
        await refreshPendingCount()
        return added
    }

    func rescheduleRepeatingReminders(preferences: UserPreferences, items: [GroceryItem]) async {
        removePending([NotificationID.dailyList])
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
        await add(request)
        await refreshPendingCount()
    }

    /// Removes the car-unload reminders, including any already in Notification Center, so none of
    /// them can be snoozed afterwards.
    func markCarUnloadComplete() {
        removeReminders(NotificationID.carUnloadReminders)
    }

    /// On sign-out: nothing scheduled for this account may fire (or be acted on) after it.
    func removeAllReminders() {
        removeReminders(NotificationID.all)
    }

    /// Removes these reminders, whether still pending or already in Notification Center.
    func removeReminders(_ identifiers: [String]) {
        removePending(identifiers)
        removeDelivered(identifiers)
        Task { await refreshPendingCount() }
    }

    private func registerCategories() {
        guard let center else { return }
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
        guard let center else {
            pendingCount = pendingForTesting.count
            return
        }
        let requests = await center.pendingNotificationRequests()
        pendingCount = requests.count
    }

    /// Schedules the request, or when inert only records it. Returns false if iOS refused it.
    @discardableResult
    private func add(_ request: UNNotificationRequest) async -> Bool {
        guard let center else {
            guard !refusesRequestsForTesting else { return false }
            scheduledForTesting.append(request)
            pendingForTesting.insert(request.identifier)
            return true
        }
        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }

    private func removePending(_ identifiers: [String]) {
        guard let center else {
            removedForTesting.append(contentsOf: identifiers)
            pendingForTesting.subtract(identifiers)
            return
        }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private func removeDelivered(_ identifiers: [String]) {
        guard let center else {
            removedDeliveredForTesting.append(contentsOf: identifiers)
            return
        }
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}

enum NotificationID {
    static let carUnload = "car-unload"
    static let carUnloadRepeat = "car-unload-repeat"
    static let storeVisit = "store-visit"
    static let dailyList = "daily-list"

    static let carUnloadReminders = [carUnload, carUnloadRepeat]
    /// Every notification the app schedules.
    static let all = [carUnload, carUnloadRepeat, storeVisit, dailyList]
}

enum NotificationCategory {
    static let carUnload = "CAR_UNLOAD"
    static let storeVisit = "STORE_VISIT"
}

enum NotificationUserInfo {
    static let itemCount = "itemCount"
    /// Seconds until "Remind again" repeats the reminder.
    static let repeatInterval = "repeatInterval"
    /// When the reminder was scheduled, as seconds since 1970.
    static let scheduledAt = "scheduledAt"
}

enum NotificationAction {
    static let markDone = "MARK_DONE"
    static let snooze = "SNOOZE"
}
