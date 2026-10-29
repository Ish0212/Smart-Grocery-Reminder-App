import XCTest
import SwiftUI
@testable import SmartGroceryReminder

final class AisleColorTests: XCTestCase {
    func testCommonAislesHaveFixedColors() {
        XCTAssertEqual(AisleColor.color(for: "Produce"), .green)
        XCTAssertEqual(AisleColor.color(for: " dairy "), .blue)
        XCTAssertEqual(AisleColor.color(for: "BAKERY"), .orange)
    }

    func testAnyOtherAisleAlwaysGetsTheSameColor() {
        let first = AisleColor.color(for: "International foods")
        XCTAssertNotNil(first)
        XCTAssertEqual(AisleColor.color(for: "international foods"), first)
    }

    func testNoAisleHasNoColor() {
        XCTAssertNil(AisleColor.color(for: ""))
        XCTAssertNil(AisleColor.color(for: "   "))
    }
}
