import Foundation

enum AuthError: LocalizedError {
    case invalidCredentials
    case emailInUse
    case weakPassword
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: return "Email or password is incorrect."
        case .emailInUse: return "An account with this email already exists."
        case .weakPassword: return "Password must be at least 6 characters."
        case .notConfigured: return "Firebase is not configured. Add GoogleService-Info.plist or use mock mode."
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

/// Soft Firebase bootstrap so the prototype runs in mock mode without a plist.
enum FirebaseBootstrap {
    static func configureIfAvailable() {
        // When ready for Firebase:
        // 1. Add Firebase iOS SDK via SPM (FirebaseAuth, FirebaseFirestore)
        // 2. Drop GoogleService-Info.plist into the app target
        // 3. Call FirebaseApp.configure() here
        // 4. Set AppState(useMockBackend: false)
    }
}
