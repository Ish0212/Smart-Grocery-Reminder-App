# Phase 2 — Polish: plan

Status: **implemented** on branch `phase2-polish` (stacked on `phase1-firebase` / PR #2); CI verification pending.
Roadmap context: [PLAN.md](PLAN.md).

## Context

Phase 1 (PR #2) added Firebase Auth + Firestore. It loads the list and preferences once at sign-in, with one-shot reads. The PR #2 review found two merge blockers in that session code (see B1/B2 below). Phase 2's sync work rewrites the same code, so it fixes them.

PLAN.md lists four Phase 2 items: MapKit store search, widget / App Intents quick-add, Family Sharing lists (optional), and better offline persistence. There's no Mac for local builds, so every change is verified by the GitHub Actions macOS job (compile + unit tests on the mock backend). This plan favors work that:

1. Compiles and can be tested with the mock backend.
2. Needs no new build targets or entitlements.

## Scope

| Item | Decision | Why |
|---|---|---|
| Live, offline-first sync (Firestore snapshot listeners) | **In** | The list and preferences load from the local cache instantly (also offline) and update live across devices. Fixes B1/B2. |
| MapKit search for stores (and home) | **In** | Replaces entering coordinates by hand / the demo button. Pure-logic parts (limit, duplicates) are unit-testable. |
| App Intents quick-add (Siri, Shortcuts, Spotlight) | **In** | Runs in the app target, so no extension is needed. The logic lives in `AppState` and is unit-tested. |
| Home-screen widget | **Deferred** | Needs a WidgetKit extension target, an App Group entitlement and shared Firebase auth (keychain sharing). CI builds with `CODE_SIGNING_ALLOWED=NO`, so entitlements aren't applied and CI couldn't verify the data path. |
| Family Sharing lists | **Deferred** (optional in PLAN.md) | Needs a shared-list data model (`lists/{listId}` + members + invites) and new security rules. This conflicts with the per-user `users/{uid}` model and rules that Phase 1 just shipped, so it needs its own design. |

## Problems / gaps addressed

| # | Problem | Where (on `phase1-firebase`) |
|---|---|---|
| B1 | **PR #2 blocker:** `signOut` keeps the previous user's `shoppingList` and `preferences`. After an account switch, the new user sees them (including the old home location) until the fetch finishes. Edits in that window write the old items into the new account. | `AppState.swift` `signOut`, `signIn` |
| B2 | **PR #2 blocker:** if loading preferences fails (e.g. offline right after a reinstall), the app stays signed in with the San Francisco defaults. The next settings change saves them over the user's real preferences. Monitoring and permission requests are skipped too. | `AppState.swift` `restoreSession`, `loadSession`, `savePreferences` |
| G1 | List/preferences are read once; changes from another device never show up until the next sign-in. | `FirestoreShoppingListService` |
| G2 | Places can only be added from the current GPS location or a hardcoded demo store. | `LocationsView.swift` |
| G3 | iOS monitors at most 20 regions per app; nothing stops the user from saving more stores (extra geofences silently never fire). Duplicate stores are allowed. | `LocationsView.swift`, `LocationService.swift` |
| G4 | No way to add items without opening the app. | — |

## Steps

### 1. Session lifecycle + live sync (fixes B1, B2, G1)

**`Services/ServiceProtocols.swift`**
- Replace `fetchItems` and `fetchPreferences` with streams:
  - `observeItems(userId:) async -> AsyncThrowingStream<[GroceryItem], Error>`
  - `observePreferences(userId:) async -> AsyncThrowingStream<UserPreferences, Error>`
- Each stream emits the current value first and then every change.

**`Services/ShoppingListService.swift`**
- **Firestore:** use `addSnapshotListener`, with the listener removed in `continuation.onTermination`.
  - Items are ordered by `createdAt` (newest first). Documents that fail to decode are skipped, so one bad document can't blank the list.
  - Preferences use `includeMetadataChanges: true`.
    - A saved document is emitted.
    - A missing document is emitted as `.default` only when the server confirms it (`!metadata.isFromCache`).
    - A cache miss while offline emits nothing. The app waits instead of treating defaults as the user's data (B2).
- **Mock:** keep one stream continuation per observer. Emit the current value on subscribe, and again after `upsert` / `delete` / `savePreferences`. Unknown users start with an empty list (previously they got the sample data).

**`App/AppState.swift`**
- Add `startSession(for:)`, used by `signIn`, `signUp` and `restoreSession`. It:
  - sets the user,
  - starts sync,
  - requests notification and location permission.
- Add `startSync(for:)`:
  - one task iterates the items stream into `shoppingList`;
  - one task iterates the preferences stream into `preferences`, sets `preferencesLoaded = true` and restarts geofence monitoring.
  - Stream errors set `syncErrorMessage`.
- `signOut` cancels both tasks, which removes the Firestore listeners. It also resets `shoppingList = []`, `preferences = .default`, `preferencesLoaded = false` and `syncErrorMessage = nil` (B1).
- `savePreferences` does nothing until `preferencesLoaded` is true (B2).

**`Views/ShoppingListView.swift`**
- Show `syncErrorMessage` as a warning row when set.

### 2. MapKit place search (G2, G3)

- **New `Services/PlaceSearchService.swift`:**
  - Runs `MKLocalSearch`. Stores use `resultTypes = .pointOfInterest` filtered to `.foodMarket`; home uses `.address`. Results are biased to a 20 km region around the current location (or home).
  - Maps results to `PlaceSearchResult` (name, address, coordinate), which converts to a `GeoPlace`.
- **New `Views/PlaceSearchView.swift`:** a sheet with `.searchable` and `.task(id: query)`. The query is debounced 300 ms, needs at least 2 characters, and shows "No matches" / "Search failed" states.
- **`App/AppState.swift`:**
  - `addStore(_:) -> AddStoreResult` (`.added`, `.duplicate` if within 50 m of a saved store, `.limitReached` at `maxStores = 19` because one of the 20 regions is reserved for home).
  - `setHome(_:)`.
- **`Models/Models.swift`:** add `GeoPlace.distance(to:)`.
- **`Views/LocationsView.swift`:**
  - Add "Search for a store" and "Search for home address" buttons.
  - Show an alert for duplicate or limit-reached results, plus a "N of 19 stores" footer.
  - "Use current location as home" goes through `setHome`.
  - Keep the demo-store button for the simulator.

### 3. App Intents quick-add (G4)

- **New `Intents/AddGroceryItemIntent.swift`:**
  - `AddGroceryItemIntent` has one `String` parameter (Siri asks "What do you need to buy?"). It runs in the app process and replies with a dialog.
  - `GroceryShortcuts: AppShortcutsProvider` registers the phrases "Add an item to Smart Grocery" / "Add to my Smart Grocery list".
  - `QuickAddError` (`notSignedIn`, `emptyItem`) has user-facing messages.
- **`App/AppState.swift`:**
  - `static weak var shared` is set by `AppDelegate`. With `@UIApplicationDelegateAdaptor`, `UIApplication.shared.delegate` is SwiftUI's own delegate, not ours, so the intent can't reach `AppState` through it.
  - `quickAdd(_:) async throws -> String` trims the title, rejects empty input, requires a signed-in user, and adds the item.

### 4. Docs

- PLAN.md: status table + Phase 2 section. README: feature list and a "Siri & Shortcuts" note.

## Tests (unit, mock backend — run in CI)

- **Mock service:** `observeItems` emits the current list and again after upsert/delete; `observePreferences` emits defaults for unknown users and again after save.
- **`AppState` sync:** `startSync` delivers mock changes into `shoppingList`; after `signOut` further changes don't arrive and the list stays empty.
- **B1:** `signOut` clears the list and resets preferences.
- **B2:** `savePreferences` before preferences load doesn't write.
- **Places:** `addStore` adds, rejects a store within 50 m, and stops at 19; `setHome` replaces home.
- **Quick-add:** `quickAdd` rejects blank input, rejects when signed out, and trims + inserts at the top when signed in.

Existing tests that used `fetchItems` / `fetchPreferences` move to the streams.

## Verification

1. CI green on the PR (`xcodegen` + `xcodebuild build test`). Expect ~40 tests.
2. What CI does **not** exercise:
   - real Firestore listeners (no `GoogleService-Info.plist` in CI);
   - `MKLocalSearch` (needs Apple Maps network access);
   - Siri / Shortcuts invocation.
   These need a Mac or device:
   - **Firebase:** sign in on two simulators and edit on one; the other updates live.
   - **Offline:** turn on Airplane Mode and relaunch; the list still shows from the cache.
   - **Place search:** search "Safeway" in Places → Search for a store.
   - **Shortcuts:** in the Shortcuts app, run "Add Grocery Item".

## Risks

- **App Intents metadata** is extracted at build time; a malformed intent fails the build. Mitigation: keep the intent minimal (one `String` parameter, literal titles).
- **Stream isolation (Swift 5 mode):** the Firestore listener fires on the main thread; `AppState` consumes the streams in `@MainActor` tasks.
- **Region budget:** the 19-store cap assumes no other app code monitors regions.
- **Out of scope, noted for Phase 3:** a geofence event delivered right after a background relaunch can arrive before the list/preferences stream emits. It is then handled with an empty list (no reminder).
