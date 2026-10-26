package com.smartgrocery.reminder.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random

class InviteCodeTest {

    @Test
    fun generatedCodesAreEightUnambiguousCharacters() {
        repeat(200) {
            val code = InviteCode.generate(Random(it))

            assertEquals(InviteCode.LENGTH, code.length)
            assertTrue(InviteCode.isWellFormed(code))
            assertFalse(code.any { it in "0O1IL" })
        }
    }

    @Test
    fun codesWithLookAlikeCharactersAreRejected() {
        assertFalse(InviteCode.isWellFormed("ABCD0FGH"))
        assertFalse(InviteCode.isWellFormed("SHORT"))
    }
}
