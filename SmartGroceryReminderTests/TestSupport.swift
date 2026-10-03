import XCTest
@testable import SmartGroceryReminder

extension AppState {
    /// The demo backend with inert location and notification services: tests never touch the
    /// device's geofences or notifications, and never trigger a permission prompt. What the
    /// services would have done is in `monitoredForTesting` / `scheduledForTesting` / `removedForTesting`.
    static func forTesting(
        mockStorageDirectory: URL? = nil,
        diagnostics: DiagnosticsLog? = nil,
        backgroundActivity: BackgroundActivityProviding? = nil,
        stateDirectory: URL? = nil,
        widgetStore: WidgetSnapshotStore? = nil
    ) -> AppState {
        AppState(
            useMockBackend: true,
            mockStorageDirectory: mockStorageDirectory,
            diagnostics: diagnostics,
            backgroundActivity: backgroundActivity,
            stateDirectory: stateDirectory,
            widgetStore: widgetStore,
            systemServices: false
        )
    }
}

extension ShoppingListServiceProtocol {
    /// A list's items as its owner sees them (a list's ID is its owner's uid).
    func observeItems(listId: String) async -> AsyncThrowingStream<[GroceryItem], Error> {
        await observeItems(listId: listId, userId: listId)
    }
}

extension XCTestCase {
    /// A file URL inside a fresh temporary directory that is removed after the test.
    func temporaryFileURL(_ name: String = "store.json") -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory.appendingPathComponent(name)
    }

    /// Sync results arrive asynchronously; poll on the main actor until `condition` holds.
    /// - Parameter timeout: roughly how long to poll; longer for something debounced.
    @MainActor
    func waitUntil(timeout: TimeInterval = 2, _ condition: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<Int(timeout * 100) {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for condition")
    }
}
