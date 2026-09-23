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
| Accessibility labels / Dynamic Type friendly layout | Baseline done |
| Unit tests (XCTest) | Done (services + reminder policy) |
| CI (GitHub Actions, macOS) | Done (`xcodegen` + `xcodebuild build test`) |

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
- Follow-ups: restore the Firebase session at launch (`Auth.auth().currentUser`) instead of showing sign-in every time; rules unit tests with the Firebase emulator

### Phase 2 — Polish
- MapKit search for store addresses
- Widget / App Intents for quick-add
- Family Sharing lists (optional)
- Better offline persistence with Firestore cache

### Phase 3 — Hardening
- Background location reliability testing
- Privacy nutrition labels / App Store copy
- Analytics (opt-in) for reminder effectiveness

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
