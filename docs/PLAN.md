# Architecture & Product Plan

## Vision

An iOS app that keeps grocery lists handy and uses location to remind you:

1. **Near a store** — nudge with open list items
2. **Arriving home** — start a customizable unload timer, then notify so groceries don’t sit in the car

## Prototype scope (this repo)

| Area | Status |
|------|--------|
| SwiftUI list + add/complete/delete | Done (mock data) |
| Auth screens + sign-in | Done (Firebase email/password, or mock `demo@grocery.app` / `demo123`) |
| Home-arrival timer + presets | Done |
| Core Location geofencing service | Done (plus simulate buttons) |
| Local notifications + actions | Done (**All brought in** / **Remind again** handled via `AppDelegate`) |
| Reminder preferences (store toggle, repeat interval) | Done |
| Firebase Auth / Firestore | Implemented (used automatically when `GoogleService-Info.plist` is bundled; mock otherwise) |
| Live sync (Firestore snapshot listeners, offline cache) | Implemented (Phase 2) |
| Apple Maps place search (stores + home) | Implemented (Phase 2) |
| Siri / Shortcuts quick-add (App Intents) | Implemented (Phase 2) |
| Accessibility labels / Dynamic Type friendly layout | Baseline done |
| Background reliability (relaunch-safe geofences, event queue, saved demo backend) | Implemented (Phase 3, PR 1) |
| Diagnostics screen (reminder health + event log) | Implemented (Phase 3, PR 1) |
| Privacy manifest + App Store privacy label / listing copy | Implemented (Phase 3b) |
| On-device reminder stats (Settings) | Implemented (Phase 3b) |
| Firestore security rules tests (emulator, Linux CI) + item field validation | Implemented (Phase 3c) |
| Unit tests (XCTest) | Done (services, sync, places, quick-add, reminder policy, location events, persistence, diagnostics, reminder stats) |
| CI (GitHub Actions) | Done: macOS `xcodegen` + `xcodebuild build test`; Linux Firestore rules job on rules changes |

## Architecture

```
Views (SwiftUI)
  └── AppState (ObservableObject orchestration, owned by AppDelegate)
        ├── AuthService (Mock | Firebase)
        ├── ShoppingListService (Mock | Firestore)
        ├── LocationService (Core Location geofences)
        ├── NotificationService (UNUserNotificationCenter)
        └── HomeArrivalTimerService
```

### Data model (Firestore-shaped)

```
users/{uid}                  (profile: email + displayName live in Firebase Auth)
  preferences/main   → home, stores, reminder settings
  items/{itemId}     → title, notes, aisle, isCompleted, createdAt, updatedAt
```

### Geofencing flow

1. User saves **home** + **grocery store** places (lat/lng + radius)
2. `CLLocationManager` monitors `CLCircularRegion`s
3. **Enter store** → optional list reminder notification
4. **Enter home** → start `HomeArrivalTimerService` → schedule unload notification (optional repeat)
5. User taps **All brought in** → cancel pending unload notifications

### Notification design

- Daily calendar trigger (hour/minute from preferences)
- Store-entry one-shot
- Home-arrival delayed + optional follow-up
- Categories with **Mark done** / **Remind again** actions

## Build phases

### Phase 0 — Prototype (done)
- Mock auth/list, full UI, location + notification plumbing, simulator hooks

### Phase 1 — Firebase (implemented; needs a Firebase project to run)
- Firebase SDK 12 via SPM (`FirebaseAuth`, `FirebaseFirestore`), pinned in `project.yml`
- `FirebaseBootstrap` configures Firebase when `GoogleService-Info.plist` is bundled; `AppDelegate` then builds `AppState` with the Firebase services
- `FirebaseAuthService` (sign in / sign up / sign out, errors mapped to app messages) and `FirestoreShoppingListService` (items + preferences, offline-first writes)
- Security rules in `firestore.rules`: users can only read/write their own `users/{uid}` tree
- Signed-in users stay signed in across launches (`AppState.restoreSession()` at launch; waits for Firebase if the device was locked)
- Follow-ups (both done in Phase 3): rules unit tests with the Firebase emulator; background geofence wakeups wait for the list to load

### Phase 2 — Polish (implemented; needs a device to try Firebase sync, search and Siri — plan: [phase-2-plan.md](phase-2-plan.md))
- Live, offline-first sync with Firestore snapshot listeners (also fixes the PR #2 session blockers)
- MapKit search for stores and home address, with the 20-geofence limit enforced
- App Intents quick-add (Siri / Shortcuts / Spotlight)
- Deferred: home-screen widget (needs an extension + App Group), Family Sharing lists (needs a shared-list data model)

### Phase 3 — Hardening (in progress — plan: [phase-3-plan.md](phase-3-plan.md); device testing: [iphone-testing.md](iphone-testing.md))
- PR 1: background/relaunch reliability (region IDs survive relaunch, events wait for data, persisted mock backend) + Diagnostics screen
- PR 2 (Phase 3b, implemented): privacy manifest (CI checks it's bundled), removed the unused location background mode, [App Store docs](app-store/), on-device reminder stats in Settings
- PR 3 (Phase 3c, implemented): Firestore rules tests on the emulator in `firestore-tests/` (Linux CI job `firestore-rules.yml`), item field validation pinned by `ModelKeysTests`

## Privacy notes

- Location: Always authorization preferred for reliable geofence wakeups; copy explains grocery + home use only
- Data: lists and preferences stored per authenticated user
- Secrets: real Firebase plist is gitignored

## Demo path (simulator)

1. Sign in with demo account
2. Review sample list; add an item
3. **Places** → simulate entering a store
4. **Arrival** → pick delay → **Simulate arrive home**
5. Allow notifications; wait or shorten delay for testing
6. Mark groceries brought in to clear pending unload alerts
