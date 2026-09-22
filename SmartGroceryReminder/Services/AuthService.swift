import Foundation

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
}

/// Drop-in Firebase Auth implementation. Requires FirebaseAuth SPM package + GoogleService-Info.plist.
final class FirebaseAuthService: AuthServiceProtocol {
    func signIn(email: String, password: String) async throws -> AppUser {
        // FirebaseAuth wiring:
        // let result = try await Auth.auth().signIn(withEmail: email, password: password)
        // return AppUser(id: result.user.uid, email: email, displayName: result.user.displayName ?? "")
        throw AuthError.notConfigured
    }

    func signUp(email: String, password: String, displayName: String) async throws -> AppUser {
        throw AuthError.notConfigured
    }

    func signOut() {
        // try? Auth.auth().signOut()
    }
}
