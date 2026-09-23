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
}

protocol ShoppingListServiceProtocol {
    func fetchItems(userId: String) async throws -> [GroceryItem]
    func upsert(item: GroceryItem, userId: String) async throws
    func delete(itemId: String, userId: String) async throws
    func fetchPreferences(userId: String) async throws -> UserPreferences
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
