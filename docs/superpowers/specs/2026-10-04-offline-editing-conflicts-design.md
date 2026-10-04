# Offline Editing and Conflict Handling: Design

Date: 2026-10-04. This is item 2 of the pre-launch roadmap, after the reminder reliability suite (PR #14).

## Goal

Family members can edit a shared list while offline, and when everyone is back online **no edit is lost**, unless two people changed the same field. Then the last writer wins, a rule that is predictable and documented. People can see when their changes haven't synced yet.

For the resume, this shows sync semantics (merging per field), offline-first UX and conflict scenarios being tested.

## What exists today (from the code)

- Writes already go through Firestore's local cache (`setData(from:)` / `updateData` without awaiting the server), so offline edits are queued and replayed by the SDK. Reads come from the cache when offline.
- `ShoppingListServiceProtocol.update(item:listId:)` writes **every field** of the item. `AppState.toggleItem` is its only caller.
- Items can't be edited after they're added (no rename, no change to notes or aisle).
- Deleting wins over editing: `update` uses `updateData`, which fails on a deleted document.

## The problem

When a whole-item update is replayed from a stale copy, it overwrites fields the writer never touched. Once editing exists:

- Alice is offline and renames "Milk" to "Oat milk". Bob checks "Milk" off. Whoever syncs last overwrites the other's change: either the name reverts, or the item comes un-checked.

Even today, a check-off replays the stale `title`, `notes` and `aisle`.

## Design

### 1. `ItemPatch`: an update says only what it changes

```swift
struct ItemPatch: Equatable {
    var title: String?
    var notes: String?
    var aisle: String?
    var completion: Completion?          // isCompleted and completedBy always change together
    var updatedAt: Date
    struct Completion: Equatable { var isCompleted: Bool; var completedBy: String? }

    /// Fields that differ between `base` (what the editor saw) and `edited`.
    static func changes(from base: GroceryItem, to edited: GroceryItem, at date: Date) -> ItemPatch?
    func applied(to item: GroceryItem) -> GroceryItem
    var isEmpty: Bool
}
```

- `changes(from:to:at:)` returns `nil` when nothing the user can edit has changed.
- `applied(to:)` sets only the fields that aren't nil, plus `updatedAt`.
- It lives in `Models/ItemPatch.swift`, is pure, and is unit-tested.

### 2. Protocol: `update(itemId:patch:listId:)` replaces `update(item:listId:)`

- **Firestore:** `updateData` with only the fields in the patch. A `completedBy` of nil is written as `FieldValue.delete()`. The encoding is a pure `static func firestoreFields(for:) -> [String: Any]`, unit-tested. It still doesn't wait for the server, and a deleted item still stays deleted.
- **Mock:** applies the patch to the stored item if it still exists, otherwise does nothing (the same contract).
- **Rules:** none needed. `isValidItem` validates the merged document, and `isHonestCompletedBy` already allows leaving someone else's `completedBy` unchanged. A rules test pins that a partial update is allowed.

### 3. Editing an item

- `AppState.editItem(_ item: GroceryItem, title:notes:aisle:)` trims the title (an empty title is ignored, since it's invalid by the rules). It builds the patch against the local copy, applies it locally, and sends only that patch.
- `toggleItem` sends a completion-only patch.
- **UI:** in `ShoppingListView`, swiping right on a row, or using its context menu, offers **Edit**. That opens the same form as New Item, filled in, with a Save button.

### 4. Showing changes that haven't synced

- A new protocol method, `observeSyncStatus(listId:) -> AsyncStream<SyncStatus>`, where `SyncStatus { hasPendingWrites: Bool }`.
- **Firestore:** a listener on the items query with `includeMetadataChanges: true` yields `snapshot.metadata.hasPendingWrites`.
- **Mock:** a stream that emits `false`, plus `setPendingWritesForTesting(_:)` for tests and the demo.
- **`AppState.hasUnsyncedChanges`:** set to true only after pending writes have lasted `unsyncedNoticeDelay` (2 s, injectable). Online writes are pending for milliseconds, so the notice doesn't flicker. It clears as soon as the pending writes are gone, and resets on sign-out and on switching lists.
- **UI:** a row at the top of the list reading "Saved on this iPhone. It will sync when you're back online." with the `icloud.slash` symbol.

### 5. Conflict rules (documented in the README)

| Situation | Outcome |
|---|---|
| Two people change **different** fields of an item | Both changes survive |
| Two people change the **same** field | The last write to reach the server wins |
| One person deletes an item, another edits it | It stays deleted (unchanged) |
| Two people check off the same item | It stays checked; `completedBy` is the last writer |

## Testing

- **Unit (`ItemPatchTests`):** the diff finds only changed fields; no change returns nil; completion carries `completedBy`; `applied` leaves other fields untouched; Firestore field encoding, including deleting `completedBy`.
- **Conflict scenarios (`ConflictReliabilityTests`, in `SmartGroceryReminderTests/Reliability/`):** two editors start from the same base copy on a shared mock service. Covers: a rename and a check-off both survive, last writer wins on the same field, an edit after a delete stays deleted, and two check-offs.
- **AppState:** `editItem` sends only the changed fields; an empty title is ignored; `toggleItem` doesn't send the title; the unsynced notice appears only after the delay and clears when synced.
- **Rules (`firestore-tests/lists.test.js`):** a member's partial update that leaves someone else's `completedBy` alone is allowed; a partial update that adds an unknown key is denied.

## Out of scope

- Merging two edits to the same text field. Last writer wins.
- Two people adding the same item offline (duplicates). They can delete one.
- A counter of how many changes are pending (Firestore doesn't expose the count).
- Our own write queue. Firestore's is already persistent and ordered.
