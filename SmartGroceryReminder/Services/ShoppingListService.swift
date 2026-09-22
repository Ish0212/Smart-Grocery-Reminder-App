import Foundation

actor MockShoppingListService: ShoppingListServiceProtocol {
    private var itemsByUser: [String: [GroceryItem]] = [
        "demo-user": SampleData.groceryItems
    ]
    private var preferencesByUser: [String: UserPreferences] = [
        "demo-user": .default
    ]

    func fetchItems(userId: String) async throws -> [GroceryItem] {
        itemsByUser[userId] ?? SampleData.groceryItems
    }

    func upsert(item: GroceryItem, userId: String) async throws {
        var items = itemsByUser[userId] ?? []
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.insert(item, at: 0)
        }
        itemsByUser[userId] = items
    }

    func delete(itemId: String, userId: String) async throws {
        itemsByUser[userId]?.removeAll { $0.id == itemId }
    }

    func fetchPreferences(userId: String) async throws -> UserPreferences {
        preferencesByUser[userId] ?? .default
    }

    func savePreferences(_ preferences: UserPreferences, userId: String) async throws {
        preferencesByUser[userId] = preferences
    }
}

/// Firestore-backed list storage. Requires FirebaseFirestore SPM package.
final class FirestoreShoppingListService: ShoppingListServiceProtocol {
    func fetchItems(userId: String) async throws -> [GroceryItem] {
        // let snapshot = try await Firestore.firestore()
        //     .collection("users").document(userId).collection("items").getDocuments()
        return SampleData.groceryItems
    }

    func upsert(item: GroceryItem, userId: String) async throws {
        // try await Firestore.firestore()
        //     .collection("users").document(userId).collection("items").document(item.id)
        //     .setData(from: item)
    }

    func delete(itemId: String, userId: String) async throws {
        // try await Firestore.firestore()
        //     .collection("users").document(userId).collection("items").document(itemId).delete()
    }

    func fetchPreferences(userId: String) async throws -> UserPreferences {
        .default
    }

    func savePreferences(_ preferences: UserPreferences, userId: String) async throws {}
}
