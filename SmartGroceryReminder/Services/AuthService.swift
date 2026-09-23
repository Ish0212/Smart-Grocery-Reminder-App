import Foundation
import FirebaseAuth

final class MockAuthService: AuthServiceProtocol {
    private var users: [String: (password: String, user: AppUser)] = [
        "demo@grocery.app": (
            "demo123",
            AppUser(id: "demo-user", email: "demo@grocery.app", displayName: "Demo Shopper")
        )
    ]

    func signIn(email: String, password: String) async throws -> AppUser {
        try await Task.sleep(nanoseconds: 350_000_000)
        guard let record = users[email.lowercased()], record.password == password else {
            throw AuthError.invalidCredentials
        }
        return record.user
    }

    func signUp(email: String, password: String, displayName: String) async throws -> AppUser {
        try await Task.sleep(nanoseconds: 350_000_000)
        let key = email.lowercased()
        guard password.count >= 6 else { throw AuthError.weakPassword }
        guard users[key] == nil else { throw AuthError.emailInUse }
        let user = AppUser(id: UUID().uuidString, email: key, displayName: displayName)
        users[key] = (password, user)
        return user
    }

    func signOut() {}

    /// Mock sessions live only in memory, so there is never one to restore.
    func restoreSession(_ onRestore: @escaping (AppUser) -> Void) {}
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
