package com.smartgrocery.reminder.data

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import java.util.UUID

/** In-memory accounts for builds without google-services.json. The demo account is demo@grocery.app / demo123. */
class MockAuthService : AuthService {
    private class Account(val uid: String, val displayName: String, val password: String)

    private val accounts = mutableMapOf(
        "demo@grocery.app" to Account(uid = "demo-user", displayName = "Demo", password = "demo123"),
    )
    private val signedIn = MutableStateFlow<AuthUser?>(null)

    override val user: Flow<AuthUser?> = signedIn
    override val currentUser: AuthUser? get() = signedIn.value

    override suspend fun signIn(email: String, password: String) {
        val key = email.trim().lowercase()
        val account = accounts[key]
        if (account == null || account.password != password) {
            throw AuthException("Wrong email or password.")
        }
        signedIn.value = AuthUser(account.uid, key, account.displayName)
    }

    override suspend fun signUp(email: String, password: String, displayName: String) {
        val key = email.trim().lowercase()
        if (accounts.containsKey(key)) throw AuthException("An account already exists for that email.")
        if (password.length < 6) throw AuthException("Password must be at least 6 characters.")
        val account = Account(
            uid = UUID.randomUUID().toString(),
            displayName = displayName.trim().ifEmpty { key.substringBefore('@') },
            password = password,
        )
        accounts[key] = account
        signedIn.value = AuthUser(account.uid, key, account.displayName)
    }

    override suspend fun sendPasswordReset(email: String) {
        // Nothing is sent in the demo. Firebase never reveals whether an address has an account.
    }

    override suspend fun signOut() {
        signedIn.value = null
    }
}
