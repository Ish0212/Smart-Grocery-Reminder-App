import Foundation
import FirebaseFirestore

struct MockListSnapshot: Codable {
    struct SharedList: Codable, Equatable {
        var ownerId: String
        var memberIds: [String]
    }

    struct Invite: Codable, Equatable {
        var listId: String
        var expiresAt: Date
    }

    /// Items by list ID. A personal list's ID is its owner's uid, so files saved before shared
    /// lists existed load unchanged (hence the old key name).
    var itemsByUser: [String: [GroceryItem]]
    var preferencesByUser: [String: UserPreferences]
    // Optional so that files saved before shared lists existed still decode.
    var lists: [String: SharedList]? = nil
    var invites: [String: Invite]? = nil
    var activeListByUser: [String: String]? = nil

    /// What a fresh install starts with: the demo account's sample list.
    static let seed = MockListSnapshot(
        itemsByUser: ["demo-user": SampleData.groceryItems],
        preferencesByUser: ["demo-user": .default]
    )
}

/// Demo backend. With a store, lists and preferences are saved on the device; without one
/// (tests, previews) they live in memory. Observers stand in for Firestore snapshot listeners.
actor MockShoppingListService: ShoppingListServiceProtocol {
    private var itemsByList: [String: [GroceryItem]]
    private var preferencesByUser: [String: UserPreferences]
    private var lists: [String: MockListSnapshot.SharedList]
    private var invites: [String: MockListSnapshot.Invite]
    private var activeListByUser: [String: String]
    private let store: JSONFileStore<MockListSnapshot>?
    private let now: @Sendable () -> Date
    /// False when a saved file exists but couldn't be read, so it is never overwritten.
    private let canSave: Bool
    private var itemObservers: [(listId: String, readerId: String, continuation: AsyncThrowingStream<[GroceryItem], Error>.Continuation)] = []
    private var preferenceObservers: [(userId: String, continuation: AsyncThrowingStream<UserPreferences, Error>.Continuation)] = []
    private var activeListObservers: [(userId: String, continuation: AsyncThrowingStream<String, Error>.Continuation)] = []

    init(store: JSONFileStore<MockListSnapshot>? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
        var snapshot = MockListSnapshot.seed
        var canSave = store != nil
        if let store {
            switch store.load() {
            case .loaded(let saved): snapshot = saved
            case .missing, .corrupt: break
            case .unreadable: canSave = false
            }
        }
        itemsByList = snapshot.itemsByUser
        preferencesByUser = snapshot.preferencesByUser
        lists = snapshot.lists ?? [:]
        invites = snapshot.invites ?? [:]
        activeListByUser = snapshot.activeListByUser ?? [:]
        self.store = store
        self.now = now
        self.canSave = canSave
    }

    // MARK: - Lists

    func observeActiveList(userId: String) -> AsyncThrowingStream<String, Error> {
        ensureOwnList(userId)
        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream(bufferingPolicy: .bufferingNewest(1))
        activeListObservers.append((userId, continuation))
        continuation.yield(activeListId(for: userId))
        return stream
    }

    func listInfo(listId: String) -> SharedListInfo {
        lists[listId].map { SharedListInfo(ownerId: $0.ownerId, memberIds: $0.memberIds) } ?? .personal(listId)
    }

    func createInvite(userId: String) -> String {
        ensureOwnList(userId)
        let code = InviteCode.generate()
        invites[code] = MockListSnapshot.Invite(listId: userId, expiresAt: now().addingTimeInterval(InviteCode.lifetime))
        persist()
        return code
    }

    func joinList(code rawCode: String, userId: String) throws {
        let code = InviteCode.normalize(rawCode)
        guard code.count == InviteCode.length, let invite = invites[code], var list = lists[invite.listId] else {
            throw SharedListError.invalidCode
        }
        guard invite.expiresAt > now() else { throw SharedListError.expiredCode }
        if !list.memberIds.contains(userId) {
            guard list.memberIds.count < SharedListInfo.maxMembers else { throw SharedListError.listFull }
            list.memberIds.append(userId)
            lists[invite.listId] = list
        }
        setActiveList(invite.listId, for: userId)
    }

    func leaveList(userId: String) throws {
        let listId = activeListId(for: userId)
        guard listId != userId else { throw SharedListError.cannotLeaveOwnList }
        // Does nothing for someone the owner already removed.
        lists[listId]?.memberIds.removeAll { $0 == userId }
        setActiveList(userId, for: userId)
    }

    /// The owner takes someone off their list (the rules allow it; the app has no button for it
    /// yet). Like Firestore, that member's item listener is then denied.
    func removeMember(_ userId: String, fromList listId: String) {
        guard userId != listId else { return }
        lists[listId]?.memberIds.removeAll { $0 == userId }
        persist()
        itemObservers.removeAll { observer in
            guard observer.listId == listId, observer.readerId == userId else { return false }
            observer.continuation.finish(throwing: SharedListError.removedFromList)
            return true
        }
    }

    /// Like the rules: the owner and the members may read a list.
    private func canRead(_ listId: String, _ userId: String) -> Bool {
        listId == userId || lists[listId]?.memberIds.contains(userId) == true
    }

    private func activeListId(for userId: String) -> String {
        activeListByUser[userId] ?? userId
    }

    private func ensureOwnList(_ userId: String) {
        guard lists[userId] == nil else { return }
        lists[userId] = MockListSnapshot.SharedList(ownerId: userId, memberIds: [userId])
        persist()
    }

    private func setActiveList(_ listId: String, for userId: String) {
        activeListByUser[userId] = listId == userId ? nil : listId
        persist()
        for observer in activeListObservers where observer.userId == userId {
            observer.continuation.yield(listId)
        }
    }

    // MARK: - Items

    func observeItems(listId: String, userId: String) -> AsyncThrowingStream<[GroceryItem], Error> {
        let (stream, continuation) = AsyncThrowingStream<[GroceryItem], Error>.makeStream(bufferingPolicy: .bufferingNewest(1))
        guard canRead(listId, userId) else {
            continuation.finish(throwing: SharedListError.removedFromList)
            return stream
        }
        itemObservers.append((listId, userId, continuation))
        continuation.yield(itemsByList[listId] ?? [])
        return stream
    }

    func upsert(item: GroceryItem, listId: String) async throws {
        var items = itemsByList[listId] ?? []
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.insert(item, at: 0)
        }
        itemsByList[listId] = items
        persist()
        publishItems(for: listId)
    }

    func update(item: GroceryItem, listId: String) async throws {
        // Like Firestore's updateData, a deleted item stays deleted.
        guard let index = itemsByList[listId]?.firstIndex(where: { $0.id == item.id }) else { return }
        itemsByList[listId]?[index] = item
        persist()
        publishItems(for: listId)
    }

    func delete(itemId: String, listId: String) async throws {
        itemsByList[listId]?.removeAll { $0.id == itemId }
        persist()
        publishItems(for: listId)
    }

    // MARK: - Preferences

    func observePreferences(userId: String) -> AsyncThrowingStream<UserPreferences, Error> {
        let (stream, continuation) = AsyncThrowingStream<UserPreferences, Error>.makeStream(bufferingPolicy: .bufferingNewest(1))
        preferenceObservers.append((userId, continuation))
        continuation.yield(preferencesByUser[userId] ?? .default)
        return stream
    }

    func savePreferences(_ preferences: UserPreferences, userId: String) async throws {
        preferencesByUser[userId] = preferences
        persist()
        for observer in preferenceObservers where observer.userId == userId {
            observer.continuation.yield(preferences)
        }
    }

    private func persist() {
        guard canSave, let store else { return }
        try? store.save(MockListSnapshot(
            itemsByUser: itemsByList,
            preferencesByUser: preferencesByUser,
            lists: lists,
            invites: invites,
            activeListByUser: activeListByUser
        ))
    }

    private func publishItems(for listId: String) {
        let items = itemsByList[listId] ?? []
        // Yielding to a stream that has already ended is a no-op.
        for observer in itemObservers where observer.listId == listId {
            observer.continuation.yield(items)
        }
    }
}

/// Firestore storage:
/// - `users/{uid}`: `activeListId` and, after joining someone's list, the `joinCode` used (the rules' proof
///   of invite), plus `preferences/main` (and legacy `items/*`, migrated once);
/// - `lists/{listId}`: `ownerId`, `memberIds`, with the shared `items/{itemId}` (a list's ID is its owner's uid);
/// - `invites/{code}`: `listId`, `createdBy`, `expiresAt`.
/// Reads come from snapshot listeners, which serve the local cache first (also offline) and then live updates.
/// `setData(from:)` writes to the local cache and syncs later, so edits never wait on the network.
final class FirestoreShoppingListService: ShoppingListServiceProtocol {
    private var db: Firestore { Firestore.firestore() }

    private func userDocument(_ userId: String) -> DocumentReference {
        db.collection("users").document(userId)
    }

    private func listDocument(_ listId: String) -> DocumentReference {
        db.collection("lists").document(listId)
    }

    private func itemsCollection(_ listId: String) -> CollectionReference {
        listDocument(listId).collection("items")
    }

    private func preferencesDocument(_ userId: String) -> DocumentReference {
        userDocument(userId).collection("preferences").document("main")
    }

    // MARK: - Lists

    func observeActiveList(userId: String) -> AsyncThrowingStream<String, Error> {
        let document = userDocument(userId)
        return AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let migration = MigrationFlag()
            // Metadata changes are needed to hear when the server confirms the field is missing.
            let registration = document.addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
                if let error {
                    continuation.finish(throwing: error)
                    return
                }
                guard let snapshot else { return }
                if let listId = snapshot.get("activeListId") as? String {
                    continuation.yield(listId)
                } else if !snapshot.metadata.isFromCache, !migration.started {
                    // The server says this user predates shared lists (or is new). The migration sets
                    // activeListId, which this listener then reports.
                    migration.started = true
                    Task {
                        do {
                            try await self?.createOwnList(userId: userId)
                        } catch {
                            continuation.finish(throwing: error)
                        }
                    }
                }
                // A cache miss while offline says nothing about the server: wait, like the preferences.
            }
            continuation.onTermination = { _ in registration.remove() }
        }
    }

    /// In one batch: create `lists/{uid}`, copy the legacy `users/{uid}/items` into it, and set
    /// `activeListId`. Because it's atomic, a missing `activeListId` means the list doesn't exist yet.
    /// The legacy items are left in place. They're read from the server, since a partial cache would
    /// lose the rest, and each is cleaned up to pass the rules (see `migratableItem`): one item saved
    /// before the rules checked it must not fail the whole batch, every launch.
    private func createOwnList(userId: String) async throws {
        let legacy = try await userDocument(userId).collection("items").getDocuments(source: .server)
        let items = legacy.documents.compactMap { document in
            Self.migratableItem(document.data(), documentID: document.documentID, userId: userId)
                .map { (id: document.documentID, data: $0) }
        }
        let batch = db.batch()
        batch.setData(["ownerId": userId, "memberIds": [userId]], forDocument: listDocument(userId))
        // A batch holds at most 500 writes; a personal grocery list is far below that.
        for item in items.prefix(490) {
            batch.setData(item.data, forDocument: itemsCollection(userId).document(item.id))
        }
        batch.setData(["activeListId": userId], forDocument: userDocument(userId), merge: true)
        try await batch.commit()
    }

    /// A legacy item as the rules' `isValidItem` and `isHonestCompletedBy` accept it on create, or nil
    /// if it can't be made to pass: unknown fields are dropped, over-long text is cut to the limit,
    /// and a completedBy naming someone else is dropped. The rules measure text in UTF-16 units.
    static func migratableItem(
        _ data: [String: Any],
        documentID: String,
        userId: String,
        isTimestamp: (Any) -> Bool = { $0 is Timestamp }
    ) -> [String: Any]? {
        guard data["id"] as? String == documentID,
              let title = (data["title"] as? String).map({ trimmed($0, toUTF16: 500) }), !title.isEmpty,
              let isCompleted = data["isCompleted"], CFGetTypeID(isCompleted as CFTypeRef) == CFBooleanGetTypeID(),
              let createdAt = data["createdAt"], isTimestamp(createdAt),
              let updatedAt = data["updatedAt"], isTimestamp(updatedAt) else { return nil }
        var item: [String: Any] = [
            "id": documentID,
            "title": title,
            "isCompleted": isCompleted,
            "createdAt": createdAt,
            "updatedAt": updatedAt,
        ]
        for (key, limit) in [("notes", 2000), ("aisle", 200)] {
            guard let value = data[key] else { continue }
            guard let text = value as? String else { return nil }
            item[key] = trimmed(text, toUTF16: limit)
        }
        if data["completedBy"] as? String == userId {
            item["completedBy"] = userId
        }
        return item
    }

    /// The longest run of whole Unicode scalars from the start that fits in `limit` UTF-16 units.
    private static func trimmed(_ text: String, toUTF16 limit: Int) -> String {
        guard text.utf16.count > limit else { return text }
        var scalars = String.UnicodeScalarView()
        var length = 0
        for scalar in text.unicodeScalars {
            let width = scalar.value > 0xFFFF ? 2 : 1
            guard length + width <= limit else { break }
            scalars.append(scalar)
            length += width
        }
        return String(scalars)
    }

    func listInfo(listId: String) async throws -> SharedListInfo {
        let snapshot = try await listDocument(listId).getDocument()
        guard let ownerId = snapshot.get("ownerId") as? String,
              let memberIds = snapshot.get("memberIds") as? [String] else { return .personal(listId) }
        return SharedListInfo(ownerId: ownerId, memberIds: memberIds)
    }

    func createInvite(userId: String) async throws -> String {
        let code = InviteCode.generate()
        try await db.collection("invites").document(code).setData([
            "listId": userId,
            "createdBy": userId,
            "expiresAt": Timestamp(date: Date().addingTimeInterval(InviteCode.lifetime)),
        ])
        return code
    }

    func joinList(code rawCode: String, userId: String) async throws {
        let code = InviteCode.normalize(rawCode)
        guard code.count == InviteCode.length else { throw SharedListError.invalidCode }
        let invite = try await db.collection("invites").document(code).getDocument()
        guard let listId = invite.get("listId") as? String,
              let expiresAt = invite.get("expiresAt") as? Timestamp else { throw SharedListError.invalidCode }
        guard expiresAt.dateValue() > Date() else { throw SharedListError.expiredCode }

        guard listId != userId, !(await isMember(userId, of: listId)) else {
            // Your own list, or one you're already on: just switch to it.
            try await userDocument(userId).setData(["activeListId": listId], merge: true)
            return
        }
        // One batch: the rules allow adding only yourself, and check the `joinCode` in your own
        // user document (as it will be after this batch) against the invite.
        let batch = db.batch()
        batch.updateData(["memberIds": FieldValue.arrayUnion([userId])], forDocument: listDocument(listId))
        batch.setData(["activeListId": listId, "joinCode": code], forDocument: userDocument(userId), merge: true)
        do {
            try await batch.commit()
        } catch let error as FirestoreErrorCode where error.code == .permissionDenied {
            // The invite checked out, so a denial here means the list is full.
            throw SharedListError.listFull
        }
    }

    /// Asks the server, since a cached copy may predate being removed. Non-members can't read a
    /// list, so a denied read means "not a member". Any other failure (offline) also answers no,
    /// and the join write then decides.
    private func isMember(_ userId: String, of listId: String) async -> Bool {
        guard let snapshot = try? await listDocument(listId).getDocument(source: .server),
              let memberIds = snapshot.get("memberIds") as? [String] else { return false }
        return memberIds.contains(userId)
    }

    /// Switches back first, then leaves: someone the owner already removed can't take themselves off
    /// the list (the rules deny it), and must still get back to their own list.
    func leaveList(userId: String) async throws {
        let userSnapshot = try await userDocument(userId).getDocument()
        let listId = userSnapshot.get("activeListId") as? String ?? userId
        guard listId != userId else { throw SharedListError.cannotLeaveOwnList }
        // Clearing the invite code means coming back takes a code again.
        try await userDocument(userId).setData(["activeListId": userId, "joinCode": FieldValue.delete()], merge: true)
        do {
            try await listDocument(listId).updateData(["memberIds": FieldValue.arrayRemove([userId])])
        } catch let error as FirestoreErrorCode where error.code == .permissionDenied || error.code == .notFound {
            // Already removed, or the list is gone.
        }
    }

    // MARK: - Items

    /// The rules decide who may read, so `userId` isn't needed here.
    func observeItems(listId: String, userId: String) -> AsyncThrowingStream<[GroceryItem], Error> {
        // Newest first, matching the mock's insert-at-front order.
        let query = itemsCollection(listId).order(by: "createdAt", descending: true)
        return AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let registration = query.addSnapshotListener { snapshot, error in
                if let error {
                    if let firestoreError = error as? FirestoreErrorCode, firestoreError.code == .permissionDenied {
                        continuation.finish(throwing: SharedListError.removedFromList)
                    } else {
                        continuation.finish(throwing: error)
                    }
                    return
                }
                guard let snapshot else { return }
                // Skip documents that don't decode so one bad item can't blank the whole list.
                continuation.yield(snapshot.documents.compactMap { try? $0.data(as: GroceryItem.self) })
            }
            continuation.onTermination = { _ in registration.remove() }
        }
    }

    func upsert(item: GroceryItem, listId: String) async throws {
        try itemsCollection(listId).document(item.id).setData(from: item)
    }

    /// `updateData` fails on a deleted document instead of creating it. Like `setData(from:)` it
    /// doesn't wait for the server; a rejected update is rolled back in the local cache.
    func update(item: GroceryItem, listId: String) async throws {
        var fields = try Firestore.Encoder().encode(item)
        // The encoder leaves out a nil completedBy, which would keep the stored one.
        if item.completedBy == nil {
            fields["completedBy"] = FieldValue.delete()
        }
        updateWithoutWaiting(itemsCollection(listId).document(item.id), fields)
    }

    /// Outside an async function, `updateData` resolves to the call that doesn't wait for the server.
    private func updateWithoutWaiting(_ document: DocumentReference, _ fields: [String: Any]) {
        document.updateData(fields)
    }

    func delete(itemId: String, listId: String) async throws {
        try await itemsCollection(listId).document(itemId).delete()
    }

    // MARK: - Preferences

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

/// Snapshot listeners run one callback at a time on the main queue; this only stops a second
/// migration from starting while the first is in flight.
private final class MigrationFlag {
    var started = false
}
