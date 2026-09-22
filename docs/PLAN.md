# Architecture & Product Plan

## Vision

An iOS app that keeps grocery lists handy and uses location to remind you:

1. **Near a store** — nudge with open list items
2. **Arriving home** — start a customizable unload timer, then notify so groceries don’t sit in the car

## Prototype scope (this repo)

| Area | Status |
|------|--------|
| SwiftUI list + add/complete/delete | Done (mock data) |
| Auth screens + mock sign-in | Done (`demo@grocery.app` / `demo123`) |
| Home-arrival timer + presets | Done |
| Core Location geofencing service | Done (plus simulate buttons) |
| Local notifications + actions | Done |
| Firebase Auth / Firestore | Stubbed interfaces ready to wire |
| Accessibility labels / Dynamic Type friendly layout | Baseline done |

## Architecture

```
Views (SwiftUI)
  └── AppState (ObservableObject orchestration)
        ├── AuthService (Mock | Firebase)
        ├── ShoppingListService (Mock | Firestore)
        ├── LocationService (Core Location geofences)
        ├── NotificationService (UNUserNotificationCenter)
        └── HomeArrivalTimerService
```

### Data model (Firestore-shaped)

```
users/{uid}
  email, displayName
  preferences/{doc}  → home, stores, reminder settings
  items/{itemId}     → title, notes, aisle, isCompleted, timestamps
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

### Phase 0 — Prototype (current)
- Mock auth/list, full UI, location + notification plumbing, simulator hooks

### Phase 1 — Firebase
- Add SPM Firebase packages + `GoogleService-Info.plist`
- Flip `useMockBackend` to `false`
- Security rules: users can only read/write their own `users/{uid}` tree

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
