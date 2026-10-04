# Offline Editing and Conflict Handling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Item edits send only the fields they change, so offline edits by different family members merge instead of overwriting each other. Items become editable, offline deletes don't block, and the list shows when changes haven't synced.

**Architecture:** A pure `ItemPatch` value (a diff against what the editor saw). `ShoppingListServiceProtocol.update(itemId:patch:listId:)` replaces the whole-item update. Firestore writes only the patch's fields, and the mock applies them per field and records what it received. A new `observeSyncStatus` stream feeds a debounced `AppState.hasUnsyncedChanges`.

**Tech Stack:** Swift 5 mode, SwiftUI, Firebase Firestore iOS SDK, XCTest, Node `node:test` + Firestore emulator for rules.

**Spec:** `docs/superpowers/specs/2026-10-04-offline-editing-conflicts-design.md`

## Global Constraints

- No Mac locally: Swift tests run in CI (`ios-ci.yml`), which only runs on **pull_request**. Open a draft PR at Task 0. Rules tests run in `firestore-rules.yml` on PRs that touch `firestore-tests/**`.
- `AppState.forTesting` (mock backend, inert services) for every AppState test. No real network.
- `title` stays non-empty and at most 500 characters, `notes` at most 2000, `aisle` at most 200 (the rules' limits). Trim the title, and ignore an edit whose title is empty after trimming.
- A deleted item stays deleted after any later update (an existing contract, kept).
- Match the surrounding style: plain doc comments, `@MainActor` tests, `waitUntil` polling.

## Review Focus

1. **A completion-only patch must not carry `title`/`notes`/`aisle`.** This is the whole point. Pinned through the mock's `patchesForTesting` in Task 3.
2. **A `completedBy` of nil is encoded as a field delete, but only when completion changes.** When `completion` is nil, `completedBy` is absent. Pinned in Task 1.
3. **An edit to an item someone deleted while you were offline** doesn't bring it back. Pinned in Task 2.
4. **The unsynced notice doesn't flicker** on normal online writes, and doesn't survive sign-out or a list switch. Pinned in Task 4.
5. **Two people checking off the same item.** The last writer's `completedBy` wins. Documented in the README in Task 6, not changed.

---

### Task 0: Branch and draft PR

- [ ] `git checkout -b offline-editing-conflicts`. Commit the spec and plan, push, and run `gh pr create --draft`.

### Task 1: `ItemPatch`

**Files:** Create `SmartGroceryReminder/Models/ItemPatch.swift` and `SmartGroceryReminderTests/ItemPatchTests.swift`.

**Produces:** `ItemPatch { title, notes, aisle: String?; completion: Completion?; updatedAt: Date; isEmpty; static changes(from:to:at:) -> ItemPatch?; applied(to:) -> GroceryItem }`, and `ItemPatch.Completion { isCompleted: Bool; completedBy: String? }`.

- [ ] Write the tests first:
  - a title-only change gives `title` set and everything else nil;
  - a check-off gives `completion = (true, "u")` and no text fields;
  - nothing changed returns `nil`;
  - `applied` sets only patched fields and `updatedAt`;
  - `applied` with `completion(false, nil)` clears `completedBy`.
- [ ] Implement it.
- [ ] Commit.

The Firestore encoding (`firestoreFields(for:)`) goes in Task 2 with the service, as a `static` on `FirestoreShoppingListService`.

### Task 2: Protocol change, both services, offline delete

**Files:** Modify `Services/ServiceProtocols.swift`, `Services/ShoppingListService.swift`, `App/AppState.swift` (`toggleItem`), `SmartGroceryReminderTests/MockShoppingListServiceTests.swift:50-75`. Test file: `SmartGroceryReminderTests/ItemPatchTests.swift` (encoding).

**Produces:**
- `func update(itemId: String, patch: ItemPatch, listId: String) async throws` on the protocol;
- `MockShoppingListService.patchesForTesting: [(itemId: String, patch: ItemPatch)]`;
- `FirestoreShoppingListService.firestoreFields(for: ItemPatch) -> [String: Any]`.

- [ ] Replace `update(item:listId:)` in the protocol with `update(itemId:patch:listId:)`. Keep the doc comment: "Changes only the patched fields, and only if the item still exists, so an edit can't bring back one someone else deleted or overwrite fields it didn't touch."
- [ ] **Mock:** record the patch in `patchesForTesting`. If the item exists, store `patch.applied(to:)` and publish; otherwise do nothing.
- [ ] **Firestore:** `firestoreFields(for:)` maps `title`/`notes`/`aisle` when they're non-nil. For completion, it writes `isCompleted` plus `completedBy`, or `FieldValue.delete()` when nil, and leaves both keys out when completion is nil. `updatedAt` is `Timestamp(date:)`. `update` calls `updateWithoutWaiting(document, fields)`.
- [ ] **Firestore `delete`:** use the non-waiting overload (a `private func deleteWithoutWaiting(_ document: DocumentReference) { document.delete() }`, the same pattern as `updateWithoutWaiting`). The doc comment explains that an offline delete otherwise blocks the next one until the phone reconnects. This can't be unit-tested without the SDK; ledger it.
- [ ] **`AppState.toggleItem`:** build `ItemPatch(completion: .init(isCompleted: new, completedBy: new ? uid : nil), updatedAt: now)`, apply it locally, then send it.
- [ ] **Tests:**
  - convert the 2 mock tests to patches;
  - add encoding tests: completion-nil has no `isCompleted`/`completedBy` key, an uncheck has `completedBy is FieldValue`, `updatedAt is Timestamp`, a title-only patch has exactly `["title", "updatedAt"]`.
- [ ] Commit, push, CI green.

### Task 3: Editing (AppState and UI) and conflict scenarios

**Files:**
- Modify `App/AppState.swift` (add `editItem`) and `Views/ShoppingListView.swift`.
- Create `SmartGroceryReminderTests/Reliability/ConflictReliabilityTests.swift`.
- Add AppState tests to the same file.

**Produces:** `func editItem(_ item: GroceryItem, title: String, notes: String, aisle: String) async`.

- [ ] Write the tests first:
  - *Conflicts* (one `MockShoppingListService`, patches built with `ItemPatch.changes` from the **same base**): a rename by one person and a check-off by another both survive, in either order; last writer wins on the same field; an edit after a delete stays deleted; two check-offs leave the item completed with the last writer's `completedBy`.
  - *AppState*: `editItem` sends one patch containing only the changed text fields; an empty or whitespace title sends nothing and changes nothing; `toggleItem`'s patch has nil `title`/`notes`/`aisle`; the edit is visible locally straight away.
- [ ] Implement `editItem`: find the local item, build `edited` with the trimmed title, `notes` and `aisle`, then `guard let patch = ItemPatch.changes(from: local, to: edited, at: Date())`. Apply it locally and send `update(itemId:patch:listId:)` to `editableListId`.
- [ ] **UI:** `@State private var editing: GroceryItem?`. On both sections' rows, add `.swipeActions(edge: .leading) { Button("Edit") { editing = item }.tint(.blue) }` and a `.contextMenu` with an "Edit" button. Add `.sheet(item: $editing) { ItemEditor(item: $0) }`. Pull the add form into an `ItemForm` view used by both the add sheet and the edit sheet. The edit sheet's Save button is disabled when the trimmed title is empty.
- [ ] Commit, push, CI green.

### Task 4: Unsynced-changes notice

**Files:**
- Modify `Services/ServiceProtocols.swift`, `Services/ShoppingListService.swift`, `App/AppState.swift`, `Views/ShoppingListView.swift`, `SmartGroceryReminderTests/TestSupport.swift` (if needed).
- Test: `SmartGroceryReminderTests/Reliability/ConflictReliabilityTests.swift` (or a new `OfflineReliabilityTests.swift`).

**Produces:**
- `struct SyncStatus: Equatable { var hasPendingWrites: Bool }`;
- `func observeSyncStatus(listId: String) async -> AsyncStream<SyncStatus>` on the protocol;
- `MockShoppingListService.setPendingWritesForTesting(_ pending: Bool, listId: String)`;
- `AppState.hasUnsyncedChanges: Bool` (published, `private(set)`) and `AppState.unsyncedNoticeDelay: TimeInterval` (an instance `var`, default 2).

- [ ] Write the tests first:
  - with a delay of 0, pending → `hasUnsyncedChanges` becomes true, then synced → false;
  - with a delay of 0.5, pending then synced within 0.1 s → it never becomes true;
  - sign-out clears it;
  - switching lists clears it (if a list-switch test helper exists in `SharedListTests`, reuse its setup; otherwise sign-out only, and ledger it).
- [ ] **Firestore:** `itemsCollection(listId).addSnapshotListener(includeMetadataChanges: true)` yields `SyncStatus(hasPendingWrites: snapshot.metadata.hasPendingWrites)` without duplicates (track the last value). Errors end the stream quietly; the items stream already reports them.
- [ ] **Mock:** keep `syncObservers`. Yield the current value (default `false`) when observed. The setter yields to the observers of that list.
- [ ] **AppState:** in `observeItems(of:userId:)`, also start a `syncStatusTask` that iterates the stream. On pending, start a `unsyncedNoticeTask` that sleeps `unsyncedNoticeDelay` and then sets `hasUnsyncedChanges = true` if still pending. On synced, cancel that task and set it false. Cancel both tasks and reset the flag wherever `itemsSyncTask` is cancelled (sign-out, list switch).
- [ ] **UI:** at the top of the list, when `appState.hasUnsyncedChanges`, show `Label("Saved on this iPhone. It will sync when you're back online.", systemImage: "icloud.slash")` in footnote style, secondary colour.
- [ ] Commit, push, CI green.

### Task 5: Rules test for partial updates

**Files:** Modify `firestore-tests/lists.test.js` (the `describe("list items")` block).

- [ ] Add a test: "a partial update leaves the rest of the item, including someone else's completedBy". Seed `item-1` as completed by alice (use the existing `item()` helper and `seedSharedList`). Bob's `updateDoc(..., { title: "Oat milk", updatedAt: Timestamp.now() })` succeeds. `updateDoc` with `{ price: 2 }` fails. `updateDoc` with `{ completedBy: "alice", isCompleted: true }` as bob fails when the stored `completedBy` is different (or absent). Check how the existing tests import `updateDoc` and `Timestamp` before writing this.
- [ ] Commit, push, rules CI green.

### Task 6: README and finish

- [ ] **README:** add a section, "Offline editing and conflicts", with the spec's table. The two-check-offs row says the last writer is credited with the check-off, so a stale check-off can claim someone else's unload reminder. Be precise: the tests prove the app sends patches containing only the changed fields, that the mock merges per field, and that the rules accept a partial update. The per-field merge on the server is Firestore's documented `updateData` behaviour, not something the suite exercises.
- [ ] Final whole-branch review, fix pass, mark ready, merge on green.
