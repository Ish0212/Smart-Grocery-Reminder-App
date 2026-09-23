import XCTest
@testable import SmartGroceryReminder

// Only the error mapping is tested: sign-in itself needs a real Firebase project.
final class FirebaseAuthServiceTests: XCTestCase {
    /// Builds the NSError Firebase Auth throws. Codes are Firebase's documented `AuthErrorCode` values.
    private func firebaseAuthError(_ code: Int) -> NSError {
        NSError(domain: "FIRAuthErrorDomain", code: code)
    }

    func testCredentialErrorsMapToInvalidCredentials() {
        let codes = [17004 /* invalidCredential */, 17009 /* wrongPassword */, 17011 /* userNotFound */]
        for code in codes {
            let mapped = FirebaseAuthService.mapError(firebaseAuthError(code))
            XCTAssertEqual(mapped as? AuthError, .invalidCredentials, "code \(code)")
        }
    }

    func testSignUpErrorsMapToAppErrors() {
        XCTAssertEqual(FirebaseAuthService.mapError(firebaseAuthError(17007)) as? AuthError, .emailInUse)
        XCTAssertEqual(FirebaseAuthService.mapError(firebaseAuthError(17026)) as? AuthError, .weakPassword)
        XCTAssertEqual(FirebaseAuthService.mapError(firebaseAuthError(17008)) as? AuthError, .invalidEmail)
    }

    func testOtherErrorsPassThrough() {
        let network = firebaseAuthError(17020 /* networkError */)
        let otherDomain = NSError(domain: NSURLErrorDomain, code: 17009)

        for error in [network, otherDomain] {
            let mapped = FirebaseAuthService.mapError(error)
            XCTAssertNil(mapped as? AuthError)
            XCTAssertEqual((mapped as NSError).domain, error.domain)
            XCTAssertEqual((mapped as NSError).code, error.code)
        }
    }
}
