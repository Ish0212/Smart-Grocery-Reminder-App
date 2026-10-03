import XCTest
@testable import SmartGroceryReminder

final class AppLinksTests: XCTestCase {
    func testTheWebsiteIsTheProjectsHostingSite() {
        let website = AppLinks.website(projectID: "smart-grocery-1a2b")
        XCTAssertEqual(website?.absoluteString, "https://smart-grocery-1a2b.web.app")
        XCTAssertEqual(website?.appendingPathComponent("privacy").absoluteString, "https://smart-grocery-1a2b.web.app/privacy")
    }

    func testTheDemoBuildHasNoWebsite() {
        XCTAssertNil(AppLinks.website(projectID: nil))
        XCTAssertNil(AppLinks.website(projectID: ""))
        // The test host runs without Firebase.
        XCTAssertNil(AppLinks.privacyPolicy)
    }
}
