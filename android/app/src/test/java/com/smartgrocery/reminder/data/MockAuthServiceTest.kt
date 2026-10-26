package com.smartgrocery.reminder.data

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test

class MockAuthServiceTest {

    @Test
    fun demoAccountSignsInAndOut() = runBlocking {
        val auth = MockAuthService()

        auth.signIn("demo@grocery.app", "demo123")
        assertEquals("demo@grocery.app", auth.currentUser?.email)

        auth.signOut()
        assertNull(auth.currentUser)
    }

    @Test
    fun wrongPasswordIsRejected() = runBlocking {
        val auth = MockAuthService()

        val error = assertThrows(AuthException::class.java) {
            runBlocking { auth.signIn("demo@grocery.app", "nope") }
        }

        assertEquals("Wrong email or password.", error.message)
        assertNull(auth.currentUser)
    }

    @Test
    fun newAccountCanSignInAfterSignUp() = runBlocking {
        val auth = MockAuthService()

        auth.signUp("Ana@Example.com", "secret1", displayName = "")
        auth.signOut()
        auth.signIn("ana@example.com", "secret1")

        assertEquals("ana", auth.currentUser?.displayName)
    }

    @Test
    fun shortPasswordsAreRejectedAtSignUp() = runBlocking {
        val auth = MockAuthService()

        val error = assertThrows(AuthException::class.java) {
            runBlocking { auth.signUp("new@example.com", "123", displayName = "New") }
        }

        assertEquals("Password must be at least 6 characters.", error.message)
    }
}
