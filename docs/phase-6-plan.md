# Phase 6 — Shared (family) lists: plan

Status: **implemented** on branch `phase6-shared-lists`.
Roadmap context: [PLAN.md](PLAN.md) (deferred from Phase 2: "needs a shared-list data model").

## Context

A household shops from one list. Today every list lives under `users/{uid}/items`, so two people can't see each other's items. This phase lets someone invite family into their list with a short code. Reminders stay personal: each phone uses its own home, stores and timer, but they count items from the shared list.

## Decisions

- **One list per user, with ID = their uid.** Sharing means inviting others into *your* list. Each user has exactly one *active* list: their own, or one they joined. There's no list picker, no renaming and no multiple lists.
- **Invite codes.** 8 characters from a 31-character alphabet (no 0/O/1/I/L) ≈ 40 bits, expiring after 7 days, one list per code. Codes are fetched by ID only; listing invites is denied.
- **Leaving** puts the member back on their own list, which still has their old items. The owner can't leave their own list, but they can join someone else's. Removing other members is out of scope.
- **At most 10 members** per list.
- **Preferences stay per user** in `users/{uid}/preferences/main`. The active list is stored in `users/{uid}` as `activeListId`.
- **The active list comes from a snapshot listener** on `users/{uid}`, not a one-off read. The cache is served immediately, so a geofence relaunch while locked or offline isn't held up by a server round trip (the Phase 3 "wait for the list" budget). Joining or leaving just changes `activeListId`, and the listener switches the items.
- **Migration is one atomic batch.** It runs only when the *server* confirms `activeListId` is missing: create `lists/{uid}` (`ownerId: uid, memberIds: [uid]`), copy `users/{uid}/items/*` into `lists/{uid}/items`, and set `activeListId`. Because the batch is atomic, "no `activeListId`" means "no `lists/{uid}`", so the app never has to read a list that may not exist (the rules would deny that read). Legacy items are left in place: rollback-safe, and the old rule still covers them.
- **Reminders stay personal on a shared list.** Items record `completedBy` when checked off. The unload reminder only counts *your* recent check-offs, plus older items with no `completedBy`, so a partner's shopping trip doesn't make your phone ask about groceries in your car.

## Data model

```
lists/{listId}                ownerId, memberIds[], joinCode?   (listId == ownerId)
  items/{itemId}              GroceryItem (validated as before)
invites/{code}                listId, createdBy, expiresAt
users/{uid}                   activeListId
  preferences/main            unchanged
  items/{itemId}              legacy, read for migration only
```

## Rules (`firestore.rules`)

- `lists/{listId}`:
  - **get:** members.
  - **create:** only `listId == auth.uid` with `ownerId == listId`, `memberIds == [listId]`.
  - **update:** one of three cases:
    - (a) the owner, who can't change `ownerId`;
    - (b) a member removing only themselves;
    - (c) a non-member adding only themselves (and setting `joinCode`), where `invites/{joinCode}` points at this list and hasn't expired, and the list stays at 10 members or fewer.
  - **delete:** never.
- `lists/{listId}/items/{itemId}`: the owner (`listId == auth.uid`, no lookup) or members of the list. Writes go through the existing `isValidItem`.
- `invites/{code}`:
  - **get:** any signed-in user.
  - **create:** only for your own list (`listId == createdBy == auth.uid`), with `expiresAt` within 8 days.
  - **delete:** the creator.
  - **list, update:** never.

## App changes

| Unit | Change |
|---|---|
| `ShoppingListServiceProtocol` | Item methods take `listId`. New: `observeActiveList(userId:)` (a stream; creates and migrates your own list the first time), `createInvite(userId:)`, `joinList(code:userId:)`, `leaveList(userId:)`, `listInfo(listId:)`. |
| `GroceryItem` | `completedBy: String?`, set by `toggleItem`. The rules and `ModelKeysTests` include it. |
| `MockShoppingListService` | In-memory + saved lists, invites and active list per user. Old saved files still decode (new keys are optional). Items stay keyed by list ID, and the personal list ID is the uid, so existing demo data keeps working. |
| `FirestoreShoppingListService` | Paths move to `lists/{listId}/items`. The migration batch; invite/join/leave as described above. Join uses `arrayUnion` plus `joinCode`, so the rules can check the invite. |
| `AppState` | `activeListId` and `sharedList` published. Items sync follows the active-list stream. `joinList(code:)` and `leaveSharedList()` stop the old items listener *before* the membership write (otherwise it reports "permission denied"), and resume it if the change fails. Edits go to the active list. The unload reminder passes the user's ID. |
| Settings | "Shared list" section: status (your list / shared with N / joined someone's), **Invite** (shows the code with a share sheet), **Join with a code**, **Leave**. |

## Tasks and tests

1. **Rules + emulator tests** (can run here locally):
   - creating your own list works; creating someone else's fails;
   - members read and write items; non-members can't;
   - joining works with a valid invite and fails with no invite, an expired invite, or another list's invite;
   - a joiner can't add anyone else;
   - a member can leave, but can't remove others;
   - the owner can't be changed;
   - an invite for your own list can be created, but not one for someone else's;
   - invites can't be listed;
   - the 10-member cap holds;
   - legacy `users/{uid}/items` stays readable by the owner;
   - **the migration batch, run as the user, succeeds.** Rules `get()` sees the state before a batch, so item writes can't depend on the list document the same batch creates. The owner is recognized by `listId == uid` instead. Someone else can't run the batch into your list.
2. **Mock service:**
   - resolve creates your own list and is idempotent;
   - invite → join → both users see the same items stream;
   - wrong or expired codes fail;
   - leave returns you to your own items;
   - the owner can't leave;
   - the member cap holds;
   - an old saved snapshot still loads.
3. **AppState:**
   - joining switches `shoppingList` to the shared items, and edits land in the shared list;
   - leaving switches back;
   - sign-out clears `activeListId`.
4. **Firestore service + Settings UI:** CI compiles them. The runtime check is manual (below).

## Manual checks (Firebase build, two accounts)

1. Account A → Settings → Shared list → **Invite**, and send the code.
2. Account B (another phone or a simulator) → **Join with a code**. B's list now shows A's items; adding on either phone appears on the other within seconds.
3. B → **Leave**: B sees their old list again.
4. An existing Firebase user's items are still there after updating (migration).
