import Foundation
import FirebaseCore

enum AuthError: LocalizedError {
    case invalidCredentials
    case emailInUse
    case weakPassword
    case invalidEmail

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: return "Email or password is incorrect."
        case .emailInUse: return "An account with this email already exists."
        case .weakPassword: return "Password must be at least 6 characters."
        case .invalidEmail: return "Enter a valid email address."
        }
    }
}

protocol AuthServiceProtocol {
    func signIn(email: String, password: String) async throws -> AppUser
    func signUp(email: String, password: String, displayName: String) async throws -> AppUser
    func signOut()
    /// Calls `onRestore` on the main thread with a user still signed in from a previous launch, if any.
    func restoreSession(_ onRestore: @escaping (AppUser) -> Void)
}

protocol ShoppingListServiceProtocol {
    /// Emits the user's items (from the local cache first when offline), then again on every change.
    func observeItems(userId: String) async -> AsyncThrowingStream<[GroceryItem], Error>
    func upsert(item: GroceryItem, userId: String) async throws
    func delete(itemId: String, userId: String) async throws
    /// Emits the user's preferences once they are known, then again on every change.
    func observePreferences(userId: String) async -> AsyncThrowingStream<UserPreferences, Error>
    func savePreferences(_ preferences: UserPreferences, userId: String) async throws
}

/// Configures Firebase only when GoogleService-Info.plist is bundled.
/// Without it (e.g. in CI) the app keeps running on the mock backend.
enum FirebaseBootstrap {
    static func configureIfAvailable() {
        guard FirebaseApp.app() == nil,
              Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return }
        FirebaseApp.configure()
    }

    static var isConfigured: Bool {
        FirebaseApp.app() != nil
    }
}
