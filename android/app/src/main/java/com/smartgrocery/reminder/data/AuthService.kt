package com.smartgrocery.reminder.data

import kotlinx.coroutines.flow.Flow

data class AuthUser(
    val uid: String,
    val email: String,
    val displayName: String,
)

/** A message fit to show the user, such as a wrong password. */
class AuthException(message: String) : Exception(message)

interface AuthService {
    /** Emits the signed-in user, or null when signed out. */
    val user: Flow<AuthUser?>
    val currentUser: AuthUser?

    suspend fun signIn(email: String, password: String)
    suspend fun signUp(email: String, password: String, displayName: String)
    suspend fun sendPasswordReset(email: String)
    suspend fun signOut()

    /** Deletes the account itself. Firebase asks the user to sign in again if it's been too long. */
    suspend fun deleteAccount()
}
