package com.smartgrocery.reminder

import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.hasClickAction
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.UiDevice
import org.junit.Rule
import org.junit.Test
import java.io.File

/**
 * Takes the Play Store screenshots on an emulator (see .github/workflows/android-release.yml).
 * Runs against the demo backend (no google-services.json), signing in to the demo account.
 */
class ScreenshotTest {

    @get:Rule
    val composeRule = createAndroidComposeRule<MainActivity>()

    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val device = UiDevice.getInstance(instrumentation)
    private val folder: File by lazy {
        instrumentation.targetContext.getExternalFilesDir("screenshots")!!.apply { mkdirs() }
    }

    @Test
    fun captureScreens() {
        composeRule.onAllNodes(hasSetTextAction())[0].performTextInput("demo@grocery.app")
        composeRule.onAllNodes(hasSetTextAction())[1].performTextInput("demo123")
        composeRule.onAllNodes(hasText("Sign in") and hasClickAction())[0].performClick()
        composeRule.waitForIdle()

        capture("1-List")
        composeRule.onNodeWithText("Arrival").performClick()
        composeRule.waitForIdle()
        capture("2-Arrival")
        composeRule.onNodeWithText("Places").performClick()
        composeRule.waitForIdle()
        capture("3-Places")
        composeRule.onNodeWithText("Settings").performClick()
        composeRule.waitForIdle()
        capture("4-Settings")
    }

    private fun capture(name: String) {
        composeRule.waitForIdle()
        device.takeScreenshot(File(folder, "$name.png"))
    }
}
