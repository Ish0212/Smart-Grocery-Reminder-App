# Phase 5 — Home-screen widget: plan

Status: **implemented** on branch `phase5-widget`.
Roadmap context: [PLAN.md](PLAN.md) (deferred from Phase 2: "needs an extension + App Group").

## Context

The two moments this app cares about are "what do I still need?" and "are the groceries in yet?". Both are glanceable, so they belong on the home screen: a small/medium widget with the open items and, while an unload countdown runs, the time left plus a **Brought in** button.

## Constraints

- **No Mac.** The widget must build in CI with signing off. Its logic has to be unit-testable from the app's test target.
- **App Groups may not survive sideloading** with a free Apple ID. The widget must degrade to a "Open Smart Grocery" placeholder when the shared container is missing, and the app must behave exactly as before.
- **The widget process can't touch the app's state or notifications** (different bundle ID). Anything that changes state has to run in the app's process.

## Design

| Unit | Where | What it does |
|---|---|---|
| `WidgetSnapshot` | `Shared/` (compiled into both targets) | Codable value: first few open item titles, open count, unload countdown end date, signed-in flag. Pure `make(items:unloadEndDate:isSignedIn:)` builds it. |
| `WidgetSnapshotStore` | `Shared/` | Reads/writes `widget-snapshot.json` in the App Group container (`group.com.smartgrocery.reminder`). Returns nil when the container is unavailable. |
| `AppState` → snapshot | app | When the list, sign-in or countdown changes, write a new snapshot (skipping identical ones) and call `WidgetCenter.shared.reloadAllTimelines()`. |
| `MarkBroughtInIntent` | `Shared/` | A `LiveActivityIntent`, so iOS runs `perform()` **in the app's process** even when the button is tapped in the widget. In the app it calls `AppState.markUnloadComplete(source: "widget")`; the widget target compiles a no-op stub (`WIDGET_EXTENSION` flag). |
| `SmartGroceryWidget` | `SmartGroceryWidget/` extension | Timeline provider reads the snapshot. One entry now, plus one at the countdown's end (so it flips to "done" without the app). Views: small (count + first items or countdown), medium (list + countdown + button). Tapping opens the app (`smartgrocery://list` / `smartgrocery://arrival`). |
| Deep links | app | `CFBundleURLTypes` scheme `smartgrocery`; `MainTabView` selects the tab from `onOpenURL`. Parsing is a pure `AppTab(url:)`. |

`project.yml`: new `app-extension` target `SmartGroceryWidget` (WidgetKit, SwiftUI), embedded in the app, bundle ID `com.smartgrocery.reminder.widget` (it must be a child of the app's). Both targets get the App Group entitlement through committed `.entitlements` files (`CODE_SIGN_ENTITLEMENTS`), and both compile `Shared/`.

The **Brought in** button is a convenience, not the only path. Tapping anywhere else on the widget opens the Arrival tab, where the in-app button works regardless.

Timer countdowns in the widget use `Text(endDate, style: .timer)`, which ticks on its own without timeline reloads.

## Tasks and tests

1. **Shared snapshot + store.** Tests: `make` caps the titles, counts only open items, and drops an ended countdown. The store round-trips through a temp directory, and a missing container gives nil.
2. **App writes snapshots.** Tests: an `AppState` built with a store in a temp dir writes a snapshot after adding an item and after `markUnloadComplete`. Signing out writes a signed-out snapshot, so the widget doesn't show the last user's list.
3. **Deep links.** Tests: `AppTab(url:)` maps `smartgrocery://list|arrival|places|settings` and rejects other URLs.
4. **Widget extension + intent.** CI compiles it. The runtime check is manual (below).
5. **CI.** Both the simulator job and the device-ipa job check that `PlugIns/SmartGroceryWidget.appex` is in the app bundle.

## Manual checks (device)

1. Add the widget (small and medium). It shows the open items; adding an item in the app updates it within a few seconds.
2. Simulate arrive home: the widget shows the countdown. Tap **Brought in** on the widget: the countdown stops and the pending unload notification is cancelled (Diagnostics shows "Groceries brought in (widget)").
3. Sign out: the widget shows "Open Smart Grocery".
4. If the sideloaded install drops the App Group, the widget shows the placeholder and the app still works. Note it in [iphone-testing.md](iphone-testing.md).
