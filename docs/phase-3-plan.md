# Phase 3 — Hardening: plan

Status: **PR 1 merged** (#4). **PR 2 implemented** as Phase 3b (#5). **PR 3 implemented** as Phase 3c.
Roadmap context: [PLAN.md](PLAN.md). Device testing: [iphone-testing.md](iphone-testing.md).

## Context

Phases 1–2 are coded (PRs #2 and #3 open, CI green) but haven't run on a real device. The first field test is a sideloaded **mock-backend** build on an iPhone.

A review of the relaunch/background path showed the headline feature is likely to fail in the real-world case: iOS kills the app, then a geofence relaunches it.

| # | Problem | Where |
|---|---|---|
| H1 | Region events after a relaunch are dropped: `LocationService` only knows which region is home from memory (`homeRegionId`, set only by `startMonitoring`). | `LocationService.swift` |
| H2 | The reminder is computed from `shoppingList` / `preferences` before sync has emitted (empty), so no reminder is sent. | `AppState.swift` sinks, `carUnloadReminderPlan` |
| H3 | The mock backend forgets the session and data when the app dies. | `MockAuthService`, `MockShoppingListService` |
| H4 | `startUpdatingLocation()` is never stopped (battery, location arrow). | `LocationService.requestAuthorization` |
| H5 | No monitoring-failure / state / error callbacks; no precise-location check. | `LocationService` delegate |
| H6 | No visibility during field tests: one status string, overwritten on every re-arm. | `LocationService.lastEventDescription` |
| R1 | "Remind again" after a cold launch counts an empty list. | `AppState.handleNotificationAction` |
| R3 | Every save or relaunch stops and restarts all regions. | `LocationService.startMonitoring` |
| R6 | The in-app "Mark groceries brought in" bypasses `AppState`, so it isn't logged. | `HomeArrivalView` |
| — | `UserPreferences.default` creates new place IDs on every launch. | `Models.swift` |

Decisions:
- "Analytics" means **on-device stats** only; nothing leaves the phone.
- The mock backend is **persisted on the device**.

## Delivery: three stacked PRs

The constraint is unchanged: CI (macOS) is the only build. Core logic must therefore be pure or mock-testable, and tests never trigger permission prompts.

### PR 1 — Field-test reliability (needed for the device test)

1. **Base pieces.**
   - Constant default place IDs.
   - `JSONFileStore<Value>`: atomic, protected until first unlock; `.unreadable` means stay in memory and never overwrite.
   - `DiagnosticsLog`: a capped, persisted event log.
2. **Persist the mock backend (H3).**
   - Mock auth and list snapshots are stored in Application Support, and the mock session is restored at launch.
   - The test host stays in memory.
3. **Region identity + events (H1, R3).**
   - Region identifiers are `"<kind>:<placeId>"`.
   - `LocationService` publishes `LocationEvent`s.
   - Monitoring changes are diffed, not reset.
4. **Queue events until data loads (H2, R1, R6).**
   - `AppState` queues location events until the list and preferences have loaded, inside a background task (at most 1 h old).
   - A pure `decision(for:preferences:items:now:)` decides what to do.
   - The countdown starts from the arrival time.
   - Snooze reads `itemCount` from the notification's `userInfo`.
   - `markUnloadComplete(source:)` handles every "done" path.
5. **Location hygiene (H4, H5).**
   - One-shot `requestLocation()` for the current location.
   - `didFailWithError`, `monitoringDidFailFor`, `didStartMonitoringFor` and `didDetermineState` callbacks.
   - Accuracy authorization and the number of regions iOS has registered are published.
6. **Diagnostics UI (H6).**
   - A "Reminder health" checklist: Always location, precise location, notifications, home region registered, plus Background App Refresh and Low Power Mode as warnings.
   - An "Open iOS Settings" button.
   - Region states.
   - A shareable event log.
7. **Docs, then a new `.ipa`** for the device test.

### PR 2 — App Store readiness + on-device stats (done: #5)
- **`PrivacyInfo.xcprivacy`:**
  - no tracking;
  - collected data: email, name, user ID, precise location of saved places, and the list — all linked to the user, used for App Functionality;
  - no required-reason APIs.
- **The device-build job** checks that the manifest is inside the app.
- **Remove the unused `UIBackgroundModes: location`.** Region monitoring doesn't need it, and it's an App Review risk.
- **`docs/app-store/`:** privacy nutrition label answers and listing copy.
- **Reminder stats in Settings,** computed from the diagnostics log: reminders scheduled, marked done, snoozed, done rate, median minutes to done.

### PR 3 — Firestore rules tests (done: Phase 3c)
- A Linux CI job (cheap minutes), filtered to rule changes, runs the Firestore emulator with `@firebase/rules-unit-testing`. It checks:
  - the owner is allowed;
  - another user is denied;
  - signed-out access is denied;
  - paths outside `users/` are denied.
- Items are validated (known keys only, `id` matches the document, typed and size-capped text). `ModelKeysTests.swift` pins `GroceryItem`'s keys so a model change fails CI until the rules are updated. Preferences aren't validated yet: they change in Phase 4.

## Deferred

| Item | Why |
|---|---|
| CLMonitor migration | API churn and iOS 17 delivery bugs; it fixes nothing that the ID prefix plus the event queue don't. |
| Rebuild the arrival timer after a relaunch (R4) | Cosmetic: the notification still fires. Wait for field data. |
| Enter/exit flapping cooldowns (R5) | Wait for the diagnostics log to show whether it happens. |
| Remind about checked-off items too (R2) | Product decision. |
| Firebase Analytics | On-device stats were chosen instead. |

## Verification

- **CI on each PR:** build + unit tests on the mock backend.
  - PR 2 also checks the privacy manifest is bundled.
  - PR 3 runs the rules job.
- **Device test with the PR 1 build** (see [iphone-testing.md](iphone-testing.md)):
  1. Diagnostics is all green.
  2. Set home while at home; "Check now" shows home = inside.
  3. Keep one item unchecked and use the 5-minute delay.
  4. Walk or drive 300–500 m away, then return.
  5. The log shows a background launch, then home enter, then the unload reminder scheduled; the notification arrives about 5 minutes later.
  6. Repeat after force-quitting the app.
  7. Sign-in and the list survive the app being killed.

## Phase 3b manual checks (device)

- Settings → **Reminder stats** shows counts after an arrival: scheduled goes up on home arrival; "Brought in" and the median update after tapping **All brought in**.
- Region-based reminders still wake the app with the location background mode removed (repeat the leave-home field test above).
- Before App Store submission: Xcode → Product → Archive → Generate Privacy Report, and compare it with [app-store/privacy-label.md](app-store/privacy-label.md).
