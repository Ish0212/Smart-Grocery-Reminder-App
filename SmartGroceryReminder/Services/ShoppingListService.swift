import Foundation
import FirebaseFirestore

/// In-memory backend. Observers stand in for Firestore snapshot listeners.
actor MockShoppingListService: ShoppingListServiceProtocol {
    private var itemsByUser: [String: [GroceryItem]] = [
        "demo-user": SampleData.groceryItems
    ]
    private var preferencesByUser: [String: UserPreferences] = [
        "demo-user": .default
    ]
    private var itemObservers: [(userId: String, continuation: AsyncThrowingStream<[GroceryItem], Error>.Continuation)] = []
    private var preferenceObservers: [(userId: String, continuation: AsyncThrowingStream<UserPreferences, Error>.Continuation)] = []

    func observeItems(userId: String) -> AsyncThrowingStream<[GroceryItem], Error> {
        let (stream, continuation) = AsyncThrowingStream<[GroceryItem], Error>.makeStream(bufferingPolicy: .bufferingNewest(1))
        itemObservers.append((userId, continuation))
        continuation.yield(itemsByUser[userId] ?? [])
        return stream
    }

    func upsert(item: GroceryItem, userId: String) async throws {
        var items = itemsByUser[userId] ?? []
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.insert(item, at: 0)
        }
        itemsByUser[userId] = items
        publishItems(for: userId)
    }

    func delete(itemId: String, userId: String) async throws {
        itemsByUser[userId]?.removeAll { $0.id == itemId }
        publishItems(for: userId)
    }

    func observePreferences(userId: String) -> AsyncThrowingStream<UserPreferences, Error> {
        let (stream, continuation) = AsyncThrowingStream<UserPreferences, Error>.makeStream(bufferingPolicy: .bufferingNewest(1))
        preferenceObservers.append((userId, continuation))
        continuation.yield(preferencesByUser[userId] ?? .default)
        return stream
    }

    func savePreferences(_ preferences: UserPreferences, userId: String) async throws {
        preferencesByUser[userId] = preferences
        for observer in preferenceObservers where observer.userId == userId {
            observer.continuation.yield(preferences)
        }
    }

    private func publishItems(for userId: String) {
        let items = itemsByUser[userId] ?? []
        // Yielding to a stream that has already ended is a no-op.
        for observer in itemObservers where observer.userId == userId {
            observer.continuation.yield(items)
        }
    }
}

/// Firestore storage under `users/{uid}`: `items/{itemId}` and `preferences/main`.
/// Reads come from snapshot listeners, which serve the local cache first (also offline) and then live updates.
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

    func observeItems(userId: String) -> AsyncThrowingStream<[GroceryItem], Error> {
        // Newest first, matching the mock's insert-at-front order.
        let query = itemsCollection(userId).order(by: "createdAt", descending: true)
        return AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let registration = query.addSnapshotListener { snapshot, error in
                if let error {
                    continuation.finish(throwing: error)
                    return
                }
                guard let snapshot else { return }
                // Skip documents that don't decode so one bad item can't blank the whole list.
                continuation.yield(snapshot.documents.compactMap { try? $0.data(as: GroceryItem.self) })
            }
            continuation.onTermination = { _ in registration.remove() }
        }
    }

    func upsert(item: GroceryItem, userId: String) async throws {
        try itemsCollection(userId).document(item.id).setData(from: item)
    }

    func delete(itemId: String, userId: String) async throws {
        try await itemsCollection(userId).document(itemId).delete()
    }

    func observePreferences(userId: String) -> AsyncThrowingStream<UserPreferences, Error> {
        let document = preferencesDocument(userId)
        return AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            // Metadata changes are needed to hear when the server confirms a missing document.
            let registration = document.addSnapshotListener(includeMetadataChanges: true) { snapshot, error in
                if let error {
                    continuation.finish(throwing: error)
                    return
                }
                guard let snapshot else { return }
                if snapshot.exists {
                    do {
                        continuation.yield(try snapshot.data(as: UserPreferences.self))
                    } catch {
                        continuation.finish(throwing: error)
                    }
                } else if !snapshot.metadata.isFromCache {
                    // The server says nothing is saved yet.
                    continuation.yield(.default)
                }
                // A cache miss while offline says nothing about the server, so wait rather than
                // report defaults that a later save would write over the user's real preferences.
            }
            continuation.onTermination = { _ in registration.remove() }
        }
    }

    func savePreferences(_ preferences: UserPreferences, userId: String) async throws {
        try preferencesDocument(userId).setData(from: preferences)
    }
}
