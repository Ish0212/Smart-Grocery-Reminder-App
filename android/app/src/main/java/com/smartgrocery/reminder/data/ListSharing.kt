package com.smartgrocery.reminder.data

import com.google.firebase.Timestamp
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.SetOptions
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.tasks.await
import java.util.Date
import kotlin.random.Random

/**
 * Shared family lists. Each user owns one list (its ID is their uid). An invite code lets someone
 * else join it. Items live in the list, so members see the same items; reminders stay personal.
 */
interface ListSharing {
    /** The list this user is working in: their own uid, or the shared list they joined. */
    fun activeListId(uid: String): Flow<String>

    /** A code another user can enter to join [uid]'s list. Valid for seven days. */
    suspend fun createInvite(uid: String): String

    suspend fun join(uid: String, code: String)

    /** Goes back to the user's own list. */
    suspend fun leave(uid: String, listId: String)
}

class MockListSharing : ListSharing {
    override fun activeListId(uid: String): Flow<String> = flowOf(uid)

    override suspend fun createInvite(uid: String): String = throw AuthException(SHARING_NEEDS_FIREBASE)

    override suspend fun join(uid: String, code: String) = throw AuthException(SHARING_NEEDS_FIREBASE)

    override suspend fun leave(uid: String, listId: String) = throw AuthException(SHARING_NEEDS_FIREBASE)

    private companion object {
        const val SHARING_NEEDS_FIREBASE = "Sharing needs a Firebase project. The demo runs on one device."
    }
}

class FirestoreListSharing(private val firestore: FirebaseFirestore) : ListSharing {

    override fun activeListId(uid: String): Flow<String> = callbackFlow {
        val registration = firestore.collection("users").document(uid).addSnapshotListener { snapshot, error ->
            if (error != null) {
                close(error)
                return@addSnapshotListener
            }
            trySend(snapshot?.getString("activeListId") ?: uid)
        }
        awaitClose { registration.remove() }
    }

    override suspend fun createInvite(uid: String): String {
        // The owner's list document must exist before anyone can join it. create() fails harmlessly if it does.
        try {
            firestore.collection("lists").document(uid)
                .create(mapOf("ownerId" to uid, "memberIds" to listOf(uid)))
                .await()
        } catch (error: FirebaseFirestoreException) {
            if (error.code != FirebaseFirestoreException.Code.ALREADY_EXISTS) throw error
        }

        val code = InviteCode.generate()
        val expiresAt = Timestamp(Date(System.currentTimeMillis() + INVITE_LIFETIME_MS))
        firestore.collection("invites").document(code)
            .set(mapOf("listId" to uid, "createdBy" to uid, "expiresAt" to expiresAt))
            .await()
        return code
    }

    override suspend fun join(uid: String, code: String) {
        val invite = firestore.collection("invites").document(code).get().await()
        if (!invite.exists()) throw AuthException("That code doesn't match a list.")
        val expiresAt = invite.getTimestamp("expiresAt")?.toDate()?.time ?: 0L
        if (expiresAt <= System.currentTimeMillis()) throw AuthException("That code has expired. Ask for a new one.")
        val listId = invite.getString("listId") ?: throw AuthException("That code doesn't match a list.")
        if (listId == uid) throw AuthException("That's your own list.")

        // One batch: the rules accept the join only when the user's own document names the invite code.
        val batch = firestore.batch()
        batch.set(firestore.collection("users").document(uid), mapOf("joinCode" to code), SetOptions.merge())
        batch.update(firestore.collection("lists").document(listId), "memberIds", FieldValue.arrayUnion(uid))
        batch.set(firestore.collection("users").document(uid), mapOf("activeListId" to listId), SetOptions.merge())
        try {
            batch.commit().await()
        } catch (error: FirebaseFirestoreException) {
            throw AuthException("Couldn't join that list. It may be full (10 members maximum).")
        }
    }

    override suspend fun leave(uid: String, listId: String) {
        val batch = firestore.batch()
        batch.update(firestore.collection("lists").document(listId), "memberIds", FieldValue.arrayRemove(uid))
        batch.set(
            firestore.collection("users").document(uid),
            mapOf("activeListId" to uid, "joinCode" to FieldValue.delete()),
            SetOptions.merge(),
        )
        batch.commit().await()
    }

    private companion object {
        const val INVITE_LIFETIME_MS = 7 * 24 * 60 * 60 * 1000L
    }
}

object InviteCode {
    // No 0/O or 1/I/L, so a code read aloud or typed from a screen is unambiguous.
    private const val ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
    const val LENGTH = 8

    fun generate(random: Random = Random.Default): String =
        (1..LENGTH).map { ALPHABET[random.nextInt(ALPHABET.length)] }.joinToString("")

    fun isWellFormed(code: String): Boolean =
        code.length == LENGTH && code.all { it in ALPHABET }
}
