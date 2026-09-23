import Foundation
import CryptoKit
import FirebaseAuth

struct MockAccount: Codable {
    /// SHA-256 of the password, so a demo sign-up never leaves a plain-text password on the device.
    var passwordHash: String
    var user: AppUser
}

struct MockAuthSnapshot: Codable {
    /// Keyed by lowercased email.
    var accounts: [String: MockAccount]
    var signedInUserId: String?
}

/// Local accounts for the demo backend. With a store, accounts and the signed-in user are saved
/// on the device, so the session survives iOS killing the app. Without one (tests, previews)
/// everything lives in memory.
final class MockAuthService: AuthServiceProtocol {
    static let demoUser = AppUser(id: "demo-user", email: "demo@grocery.app", displayName: "Demo Shopper")

    private var snapshot: MockAuthSnapshot
    private let store: JSONFileStore<MockAuthSnapshot>?
    /// False when a saved file exists but couldn't be read, so it is never overwritten.
    private let canSave: Bool

    init(store: JSONFileStore<MockAuthSnapshot>? = nil) {
        var snapshot = MockAuthSnapshot(accounts: [:], signedInUserId: nil)
        var canSave = store != nil
        if let store {
            switch store.load() {
            case .loaded(let saved): snapshot = saved
            case .missing, .corrupt: break
            case .unreadable: canSave = false
            }
        }
        if snapshot.accounts[Self.demoUser.email] == nil {
            snapshot.accounts[Self.demoUser.email] = MockAccount(passwordHash: Self.hash("demo123"), user: Self.demoUser)
        }
        self.snapshot = snapshot
        self.store = store
        self.canSave = canSave
    }

    func signIn(email: String, password: String) async throws -> AppUser {
        try await Task.sleep(nanoseconds: 350_000_000)
        guard let account = snapshot.accounts[email.lowercased()],
              account.passwordHash == Self.hash(password) else {
            throw AuthError.invalidCredentials
        }
        snapshot.signedInUserId = account.user.id
        save()
        return account.user
    }

    func signUp(email: String, password: String, displayName: String) async throws -> AppUser {
        try await Task.sleep(nanoseconds: 350_000_000)
        let key = email.lowercased()
        guard password.count >= 6 else { throw AuthError.weakPassword }
        guard snapshot.accounts[key] == nil else { throw AuthError.emailInUse }
        let user = AppUser(id: UUID().uuidString, email: key, displayName: displayName)
        snapshot.accounts[key] = MockAccount(passwordHash: Self.hash(password), user: user)
        snapshot.signedInUserId = user.id
        save()
        return user
    }

    func signOut() {
        snapshot.signedInUserId = nil
        save()
    }

    /// Restores the user saved on the device by a previous sign-in, if any.
    func restoreSession(_ onRestore: @escaping (AppUser) -> Void) {
        guard let userId = snapshot.signedInUserId,
              let account = snapshot.accounts.values.first(where: { $0.user.id == userId }) else { return }
        onRestore(account.user)
    }

    private func save() {
        guard canSave, let store else { return }
        try? store.save(snapshot)
    }

    private static func hash(_ password: String) -> String {
        SHA256.hash(data: Data(password.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Firebase Auth (email + password). Used when GoogleService-Info.plist is bundled.
final class FirebaseAuthService: AuthServiceProtocol {
    private var restoreListener: NSObjectProtocol?

    func signIn(email: String, password: String) async throws -> AppUser {
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            return AppUser(firebaseUser: result.user)
        } catch {
            throw Self.mapError(error)
        }
    }

    func signUp(email: String, password: String, displayName: String) async throws -> AppUser {
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            let profile = result.user.createProfileChangeRequest()
            profile.displayName = displayName
            try await profile.commitChanges()
            return AppUser(id: result.user.uid, email: result.user.email ?? email, displayName: displayName)
        } catch {
            throw Self.mapError(error)
        }
    }

    func signOut() {
        try? Auth.auth().signOut()
    }

    /// Firebase keeps users signed in across launches. If the app launched while the device was
    /// locked (e.g. woken by a geofence), Firebase only loads the saved user after unlock, so wait for it.
    func restoreSession(_ onRestore: @escaping (AppUser) -> Void) {
        if let user = Auth.auth().currentUser {
            onRestore(AppUser(firebaseUser: user))
            return
        }
        restoreListener = Auth.auth().addStateDidChangeListener { [weak self] auth, user in
            guard let user else { return }
            if let listener = self?.restoreListener {
                auth.removeStateDidChangeListener(listener)
                self?.restoreListener = nil
            }
            onRestore(AppUser(firebaseUser: user))
        }
    }

    /// Maps Firebase Auth errors onto the app's messages; anything else (e.g. network) passes through.
    static func mapError(_ error: Error) -> Error {
        let nsError = error as NSError
        guard nsError.domain == AuthErrors.domain,
              let code = AuthErrorCode(rawValue: nsError.code) else { return error }
        switch code {
        case .wrongPassword, .invalidCredential, .userNotFound: return AuthError.invalidCredentials
        case .emailAlreadyInUse: return AuthError.emailInUse
        case .weakPassword: return AuthError.weakPassword
        case .invalidEmail: return AuthError.invalidEmail
        default: return error
        }
    }
}

private extension AppUser {
    init(firebaseUser user: User) {
        self.init(id: user.uid, email: user.email ?? "", displayName: user.displayName ?? "")
    }
}
