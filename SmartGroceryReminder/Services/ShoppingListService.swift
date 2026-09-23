import Foundation
import FirebaseFirestore

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

/// Firestore storage under `users/{uid}`: `items/{itemId}` and `preferences/main`.
/// `setData(from:)` writes to the local cache and syncs later, so edits never wait on the network.
final class FirestoreShoppingListService: ShoppingListServiceProtocol {
    private func userDocument(_ userId: String) -> DocumentReference {
        Firestore.firestore().collection("users").document(userId)
    }

    private func itemsCollection(_ userId: String) -> CollectionReference {
        userDocument(userId).collection("items")
    }

    private func preferencesDocument(_ userId: String) -> DocumentReference {
        userDocument(userId).collection("preferences").document("main")
    }

    func fetchItems(userId: String) async throws -> [GroceryItem] {
        // Newest first, matching the mock's insert-at-front order.
        let snapshot = try await itemsCollection(userId)
            .order(by: "createdAt", descending: true)
            .getDocuments()
        return try snapshot.documents.map { try $0.data(as: GroceryItem.self) }
    }

    func upsert(item: GroceryItem, userId: String) async throws {
        try itemsCollection(userId).document(item.id).setData(from: item)
    }

    func delete(itemId: String, userId: String) async throws {
        try await itemsCollection(userId).document(itemId).delete()
    }

    func fetchPreferences(userId: String) async throws -> UserPreferences {
        let snapshot = try await preferencesDocument(userId).getDocument()
        guard snapshot.exists else { return .default }
        return try snapshot.data(as: UserPreferences.self)
    }

    func savePreferences(_ preferences: UserPreferences, userId: String) async throws {
        try preferencesDocument(userId).setData(from: preferences)
    }
}
