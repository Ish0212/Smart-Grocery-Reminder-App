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
    /// Checks the signed-in user's password again. Firebase deletes an account only after a recent sign-in.
    func reauthenticate(password: String) async throws
    /// Deletes the signed-in user's account. Delete their data first: afterwards the backend refuses them.
    func deleteAccount() async throws
    /// Emails a link to choose a new password. Succeeds for an unknown email too, so it can't be
    /// used to find out who has an account.
    func sendPasswordReset(email: String) async throws
}

protocol ShoppingListServiceProtocol {
    /// Emits the ID of the list the user shops from (their own list's ID is their uid), from the
    /// local cache first, then again when they join or leave a list. The first time, it creates
    /// the user's own list and moves their existing items into it.
    func observeActiveList(userId: String) async -> AsyncThrowingStream<String, Error>
    /// Emits the list's items (from the local cache first when offline), then again on every change.
    /// Fails with `SharedListError.removedFromList` when `userId` isn't (or stops being) a member.
    func observeItems(listId: String, userId: String) async -> AsyncThrowingStream<[GroceryItem], Error>
    func upsert(item: GroceryItem, listId: String) async throws
    /// Changes an item only if it still exists, so an edit can't bring back one someone else deleted.
    func update(item: GroceryItem, listId: String) async throws
    func delete(itemId: String, listId: String) async throws
    /// Emits the user's preferences once they are known, then again on every change.
    func observePreferences(userId: String) async -> AsyncThrowingStream<UserPreferences, Error>
    func savePreferences(_ preferences: UserPreferences, userId: String) async throws

    func listInfo(listId: String) async throws -> SharedListInfo
    /// A code that lets someone join the user's own list for `InviteCode.lifetime`.
    func createInvite(userId: String) async throws -> String
    /// Adds the user to the code's list and makes it their active list.
    func joinList(code: String, userId: String) async throws
    /// Leaves the active list (if it's someone else's) and goes back to the user's own list. Also
    /// works for someone the owner already removed.
    func leaveList(userId: String) async throws
    /// For account deletion: leaves a list the user joined, then deletes their own list with its
    /// items, their invites, preferences and user document. Members of their list lose access to it.
    func deleteAllData(userId: String) async throws
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
