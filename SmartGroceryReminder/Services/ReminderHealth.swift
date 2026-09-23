import CoreLocation
import UIKit
import UserNotifications

/// One row of the "Reminder health" checklist.
struct HealthItem: Identifiable, Equatable {
    let id: String
    let title: String
    let isOK: Bool
    /// Worth fixing, but reminders can still work without it.
    let isWarningOnly: Bool
    /// Where to fix it, shown when not OK.
    let fix: String?
}

/// Everything iOS needs for location reminders to fire in the background, as a checklist.
enum ReminderHealth {
    static func check(
        authorization: CLAuthorizationStatus,
        accuracy: CLAccuracyAuthorization,
        notifications: UNAuthorizationStatus,
        backgroundRefresh: UIBackgroundRefreshStatus,
        lowPowerMode: Bool,
        hasHome: Bool,
        systemRegionCount: Int,
        expectedRegionCount: Int
    ) -> [HealthItem] {
        let alwaysLocation = authorization == .authorizedAlways
        let precise = accuracy == .fullAccuracy
        let notificationsAllowed = notifications == .authorized
        let regionsRegistered = expectedRegionCount > 0 && systemRegionCount >= expectedRegionCount
        let refreshOn = backgroundRefresh == .available
        return [
            HealthItem(
                id: "location",
                title: "Location access: Always",
                isOK: alwaysLocation,
                isWarningOnly: false,
                fix: alwaysLocation ? nil : "Settings → Smart Grocery → Location → Always"
            ),
            HealthItem(
                id: "precise",
                title: "Precise Location on",
                isOK: precise,
                isWarningOnly: false,
                fix: precise ? nil : "Settings → Smart Grocery → Location → Precise Location"
            ),
            HealthItem(
                id: "notifications",
                title: "Notifications allowed",
                isOK: notificationsAllowed,
                isWarningOnly: false,
                fix: notificationsAllowed ? nil : "Settings → Smart Grocery → Notifications → Allow Notifications"
            ),
            HealthItem(
                id: "home",
                title: "Home is set",
                isOK: hasHome,
                isWarningOnly: false,
                fix: hasHome ? nil : "Places → Use current location as home"
            ),
            HealthItem(
                id: "regions",
                title: "iOS is watching \(systemRegionCount) of \(expectedRegionCount) places",
                isOK: regionsRegistered,
                isWarningOnly: false,
                fix: regionsRegistered ? nil : "Allow location access, then open Places"
            ),
            HealthItem(
                id: "backgroundRefresh",
                title: "Background App Refresh on",
                isOK: refreshOn,
                isWarningOnly: true,
                fix: refreshOn ? nil : "Settings → General → Background App Refresh"
            ),
            HealthItem(
                id: "lowPower",
                title: "Low Power Mode off",
                isOK: !lowPowerMode,
                isWarningOnly: true,
                fix: lowPowerMode ? "Turn off Low Power Mode in Control Center" : nil
            )
        ]
    }
}
