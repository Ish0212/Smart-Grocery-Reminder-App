import XCTest
@testable import SmartGroceryReminder

final class MockAuthServiceTests: XCTestCase {
    func testDemoCredentialsSignIn() async throws {
        let user = try await MockAuthService().signIn(email: "demo@grocery.app", password: "demo123")
        XCTAssertEqual(user.id, "demo-user")
        XCTAssertEqual(user.displayName, "Demo Shopper")
    }

    func testSignInIsCaseInsensitiveOnEmail() async throws {
        let user = try await MockAuthService().signIn(email: "DEMO@grocery.app", password: "demo123")
        XCTAssertEqual(user.id, "demo-user")
    }

    func testWrongPasswordThrowsInvalidCredentials() async {
        do {
            _ = try await MockAuthService().signIn(email: "demo@grocery.app", password: "nope")
            XCTFail("Expected invalidCredentials")
        } catch {
            XCTAssertEqual(error as? AuthError, .invalidCredentials)
        }
    }

    func testShortPasswordThrowsWeakPassword() async {
        do {
            _ = try await MockAuthService().signUp(email: "new@grocery.app", password: "12345", displayName: "New")
            XCTFail("Expected weakPassword")
        } catch {
            XCTAssertEqual(error as? AuthError, .weakPassword)
        }
    }

    func testDuplicateEmailThrowsEmailInUse() async {
        do {
            _ = try await MockAuthService().signUp(email: "demo@grocery.app", password: "123456", displayName: "Dup")
            XCTFail("Expected emailInUse")
        } catch {
            XCTAssertEqual(error as? AuthError, .emailInUse)
        }
    }

    func testSignUpThenSignInRoundTrips() async throws {
        let service = MockAuthService()
        let created = try await service.signUp(email: "Shopper@Grocery.app", password: "secret1", displayName: "Shopper")
        XCTAssertEqual(created.email, "shopper@grocery.app")

        let signedIn = try await service.signIn(email: "shopper@grocery.app", password: "secret1")
        XCTAssertEqual(signedIn, created)
    }
}
