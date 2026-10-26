package com.smartgrocery.reminder

import android.graphics.Bitmap
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import java.io.File
import java.io.FileOutputStream

/**
 * Takes the Play Store screenshots on an emulator (see .github/workflows/android-release.yml).
 * Runs against the demo backend (no google-services.json), signing in to the demo account.
 */
class ScreenshotTest {

    @get:Rule
    val composeRule = createAndroidComposeRule<MainActivity>()

    private val folder: File by lazy {
        InstrumentationRegistry.getInstrumentation().targetContext
            .getExternalFilesDir("screenshots")!!
            .apply { mkdirs() }
    }

    @Test
    fun captureScreens() {
        composeRule.onAllNodes(hasSetTextAction())[0].performTextInput("demo@grocery.app")
        composeRule.onAllNodes(hasSetTextAction())[1].performTextInput("demo123")
        composeRule.onAllNodes(hasText("Sign in") and hasClickAction())[0].performClick()
        composeRule.waitForIdle()

        capture("1-List")
        composeRule.onNodeWithText("Arrival").performClick()
        capture("2-Arrival")
        composeRule.onNodeWithText("Places").performClick()
        capture("3-Places")
        composeRule.onNodeWithText("Settings").performClick()
        capture("4-Settings")
    }

    /** Captured from the app's own process, so the file lands in the folder the workflow pulls from. */
    private fun capture(name: String) {
        composeRule.waitForIdle()
        val bitmap = composeRule.onRoot().captureToImage().asAndroidBitmap()
        val file = File(folder, "$name.png")
        FileOutputStream(file).use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        assertTrue("Empty screenshot: $name", file.length() > 0)
    }
}
