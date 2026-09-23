import XCTest
@testable import SmartGroceryReminder

/// The demo backend saved on the device, so a sideloaded build survives iOS killing the app.
/// Service-level only: AppState.restoreSession with a saved user would request permissions.
final class MockPersistenceTests: XCTestCase {
    private func restoredUser(_ service: MockAuthService) -> AppUser? {
        var restored: AppUser?
        service.restoreSession { restored = $0 }
        return restored
    }

    func testSignedUpUserIsRestoredByANewInstance() async throws {
        let store = JSONFileStore<MockAuthSnapshot>(url: temporaryFileURL())
        let user = try await MockAuthService(store: store)
            .signUp(email: "new@grocery.app", password: "secret1", displayName: "New")

        XCTAssertEqual(restoredUser(MockAuthService(store: store)), user)
    }

    func testSignOutForgetsTheSession() async throws {
        let store = JSONFileStore<MockAuthSnapshot>(url: temporaryFileURL())
        let service = MockAuthService(store: store)
        _ = try await service.signIn(email: "demo@grocery.app", password: "demo123")
        service.signOut()

        XCTAssertNil(restoredUser(MockAuthService(store: store)))
    }

    func testAccountsSurviveANewInstance() async throws {
        let store = JSONFileStore<MockAuthSnapshot>(url: temporaryFileURL())
        let created = try await MockAuthService(store: store)
            .signUp(email: "shopper@grocery.app", password: "secret1", displayName: "Shopper")

        let signedIn = try await MockAuthService(store: store).signIn(email: "shopper@grocery.app", password: "secret1")
        XCTAssertEqual(signedIn, created)
    }

    func testPasswordsAreNotSavedInPlainText() async throws {
        let url = temporaryFileURL()
        _ = try await MockAuthService(store: JSONFileStore(url: url))
            .signUp(email: "shopper@grocery.app", password: "hunter22", displayName: "Shopper")

        let saved = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(saved.contains("hunter22"))
    }

    func testFreshInstallRestoresNobody() {
        XCTAssertNil(restoredUser(MockAuthService(store: JSONFileStore(url: temporaryFileURL()))))
    }

    func testItemsAndPreferencesSurviveANewInstance() async throws {
        let store = JSONFileStore<MockListSnapshot>(url: temporaryFileURL())
        let first = MockShoppingListService(store: store)
        let item = GroceryItem(title: "Apples")
        var prefs = UserPreferences.default
        prefs.homeArrivalDelay = 5 * 60
        try await first.upsert(item: item, userId: "u1")
        try await first.savePreferences(prefs, userId: "u1")

        let second = MockShoppingListService(store: store)
        let items = try await second.observeItems(userId: "u1").first { _ in true }
        let loadedPrefs = try await second.observePreferences(userId: "u1").first { _ in true }
        XCTAssertEqual(items, [item])
        XCTAssertEqual(loadedPrefs, prefs)
    }

    func testCorruptListFileStartsFromTheSeedAndIsReplaced() async throws {
        let url = temporaryFileURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        let service = MockShoppingListService(store: JSONFileStore(url: url))

        let demoItems = try await service.observeItems(userId: "demo-user").first { _ in true }
        XCTAssertEqual(demoItems, SampleData.groceryItems)

        try await service.upsert(item: GroceryItem(title: "Pears"), userId: "u1")
        guard case .loaded = JSONFileStore<MockListSnapshot>(url: url).load() else {
            return XCTFail("Expected the corrupt file to be replaced")
        }
    }

    func testUnreadableListFileIsNeverOverwritten() async throws {
        let url = temporaryFileURL()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let service = MockShoppingListService(store: JSONFileStore(url: url))

        try await service.upsert(item: GroceryItem(title: "Pears"), userId: "u1")

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }
}
