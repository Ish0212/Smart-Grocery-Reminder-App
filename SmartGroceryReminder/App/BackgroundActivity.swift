import UIKit

/// Extra background time while a location wake-up waits for the list to load.
/// Behind a protocol so AppState stays testable without UIKit's app object.
@MainActor
protocol BackgroundActivityProviding: AnyObject {
    /// Returns a token for `end(_:)`. `onExpiration` runs on the main actor and must end the activity.
    func begin(name: String, onExpiration: @escaping @MainActor () -> Void) -> Int
    func end(_ token: Int)
}

/// Default for tests and previews: no system background time.
@MainActor
final class NoBackgroundActivity: BackgroundActivityProviding {
    func begin(name: String, onExpiration: @escaping @MainActor () -> Void) -> Int { 0 }
    func end(_ token: Int) {}
}

/// `UIApplication.beginBackgroundTask`, for the running app.
@MainActor
final class UIKitBackgroundActivity: BackgroundActivityProviding {
    func begin(name: String, onExpiration: @escaping @MainActor () -> Void) -> Int {
        let task = UIApplication.shared.beginBackgroundTask(withName: name) {
            // iOS calls this on the main thread; the activity must be ended before it returns.
            MainActor.assumeIsolated { onExpiration() }
        }
        return task.rawValue
    }

    func end(_ token: Int) {
        UIApplication.shared.endBackgroundTask(UIBackgroundTaskIdentifier(rawValue: token))
    }
}
