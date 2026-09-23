import AppIntents

/// "Add an item to Smart Grocery" from Siri, Shortcuts or Spotlight, without opening the app.
/// Runs in the app's own process, so it uses the same `AppState` as the UI.
struct AddGroceryItemIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Grocery Item"

    @Parameter(title: "Item", requestValueDialog: IntentDialog("What do you need to buy?"))
    var item: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let appState = AppState.shared else { throw QuickAddError.notSignedIn }
        let title = try await appState.quickAdd(item)
        return .result(dialog: "Added \(title) to your grocery list.")
    }
}

struct GroceryShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddGroceryItemIntent(),
            phrases: [
                "Add an item to \(.applicationName)",
                "Add to my \(.applicationName) list"
            ],
            shortTitle: "Add Item",
            systemImageName: "cart.badge.plus"
        )
    }
}

enum QuickAddError: Error, Equatable, CustomLocalizedStringResourceConvertible {
    case notSignedIn
    case emptyItem

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notSignedIn: return "Open Smart Grocery and sign in first."
        case .emptyItem: return "Tell me which item to add."
        }
    }
}
