import XCTest

/// Takes the App Store screenshots. Runs against the demo build (no GoogleService-Info.plist),
/// which signs in to the demo account and starts with the sample list.
/// CI runs it on the largest iPhone simulator and exports the attachments (see app-store.yml).
final class AppStoreScreenshots: XCTestCase {
    private let app = XCUIApplication()
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUp() {
        continueAfterFailure = false
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
        openTab("Arrival", name: "2-Arrival")
        openTab("Places", name: "3-Places")
        openTab("Settings", name: "4-Settings")
    }

    private func openTab(_ label: String, name: String) {
        app.tabBars.buttons[label].tap()
        allowSystemAlerts()
        capture(name)
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

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
