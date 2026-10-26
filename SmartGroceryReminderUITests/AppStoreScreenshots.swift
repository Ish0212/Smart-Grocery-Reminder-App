import XCTest

/// Takes the App Store screenshots and the README demo. Runs against the demo build (no GoogleService-Info.plist),
/// which signs in to the demo account and starts with the sample list.
/// CI runs it on the largest iPhone simulator, records the run, and exports the attachments (see app-store.yml).
final class AppStoreScreenshots: XCTestCase {
    private let app = XCUIApplication()
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUp() {
        continueAfterFailure = false
        // Hides the simulate buttons and the demo store (AppState.showsTestTools).
        app.launchArguments = ["--app-store-screenshots"]
        app.launch()
    }

    func testCaptureScreenshots() {
        let signIn = app.buttons["Sign In"].firstMatch
        if signIn.waitForExistence(timeout: 10), signIn.isEnabled {
            signIn.tap()
        }
        XCTAssertTrue(app.navigationBars["Grocery List"].waitForExistence(timeout: 15))
        allowSystemAlerts()

        capture("1-List")
        toggleFirstItem()
        capture("2-Checked-Off")
        app.buttons["Add grocery item"].tap()
        XCTAssertTrue(app.navigationBars["New Item"].waitForExistence(timeout: 5))
        capture("3-Add-Item")
        app.navigationBars["New Item"].buttons["Cancel"].tap()
        openTab("Arrival", name: "4-Arrival")
        openTab("Places", name: "5-Places")
        openTab("Settings", name: "6-Settings")
        let diagnostics = app.buttons["Diagnostics"]
        for _ in 0..<5 where !diagnostics.isHittable {
            app.swipeUp()
        }
        diagnostics.tap()
        XCTAssertTrue(app.navigationBars["Diagnostics"].waitForExistence(timeout: 5))
        capture("7-Diagnostics")
    }

    private func openTab(_ label: String, name: String) {
        app.tabBars.buttons[label].tap()
        allowSystemAlerts()
        capture(name)
    }

    private func toggleFirstItem() {
        let row = app.buttons.containing(NSPredicate(format: "label ENDSWITH ', not completed'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
    }

    /// Notification and location prompts belong to SpringBoard; accept them so they're not in the shots.
    private func allowSystemAlerts() {
        for _ in 0..<3 {
            let alert = springboard.alerts.firstMatch
            guard alert.waitForExistence(timeout: 3) else { return }
            for label in ["Allow", "Allow While Using App", "Change to Always Allow", "OK"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                break
            }
        }
    }

    /// Pauses first so each screen settles on the video (the screenshots are unaffected).
    private func capture(_ name: String) {
        Thread.sleep(forTimeInterval: 1.5)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
