# Phase 4 — Reminder tuning: plan

Status: **implemented** on branch `phase4-reminder-tuning`.
Roadmap context: [PLAN.md](PLAN.md). Picks up the items Phase 3 deferred ([phase-3-plan.md](phase-3-plan.md#deferred)).

## Context

The Phase 3 review left four reminder issues for later. Three of them change what the user sees and can be decided with pure, unit-tested logic; the fourth (CLMonitor) needs a decision, not code.

## Tasks

| # | Task | Acceptance criteria | Tests |
|---|---|---|---|
| R2 | **Remind about what you just bought.** Items checked off in the last 3 hours, and after the last "All brought in", count as "in the car". The unload reminder uses that count when there is one, otherwise the unchecked count (the old behavior). | Checking everything off at the store and driving home still sends the unload reminder. Items checked off long ago, or already brought in, don't. | `carUnloadReminderPlan` cases: recently bought, old purchases, already brought in, unchecked fallback, clock skew, nothing at all. |
| R4 | **Countdown survives a relaunch.** `HomeArrivalTimerService` saves the countdown's end date and restores it at launch. | After iOS kills and relaunches the app, the Arrival tab shows the remaining time instead of nothing. Finished or cancelled countdowns aren't restored. | Restore running; don't restore expired; cancel clears the file. |
| R5 | **Enter/exit flapping cooldown.** A real (not simulated) enter for a place already handled recently is ignored: 15 min for home (from the last arrival reminder or "All brought in", whichever is later), 60 min per store. Saved on the device. | GPS jitter at the edge of home doesn't restart the countdown or re-arm a reminder after "All brought in"; re-entering home later (walking the dog) doesn't ask about groceries already inside. Simulator buttons are never blocked. | Decision cases inside/outside the cooldown, per store, unload-done, walk-the-dog, simulated events, persistence across instances, sign-out. |
| — | **CLMonitor decision.** | A written note in this doc. | — |

## CLMonitor decision

**Not migrating.** `CLMonitor` (iOS 17) would replace `CLLocationManager` region monitoring with an async event stream and persisted conditions. What it would give this app — conditions that survive relaunch and a last-known state per region — is already covered by the `"<kind>:<placeId>"` region IDs, `didDetermineState`, and the event queue from Phase 3. The costs are real: a second API path for iOS 17.0–17.x where delivery bugs were reported, a rewrite of `LocationService` plus its tests, and the same 20-condition limit. Revisit if the deployment target moves to iOS 18+ and the field-test log shows missed region events.

## Design notes

- The cooldown, like the rest of the policy, is a parameter of the pure `AppState.decision(for:…, lastHandled:, lastUnloadDone:)`. `AppState` keeps `ReminderCooldowns` in `reminder-cooldowns.json`: the last reminder time per region ID (recorded only when a reminder is scheduled or sent) and one `lastUnloadDone` date.
- `lastUnloadDone` isn't keyed by place on purpose: "All brought in" can cold-launch the app from the notification before the preferences (and the real home ID) have loaded.
- Both new files live in `AppFiles.directory`, passed to `AppState` as `stateDirectory` (`nil` in tests keeps them in memory).
- No preference was added: the new unload rule only ever reminds in more cases than before, so there's nothing to opt out of yet.

## Manual checks (device)

1. Check off every item, simulate or drive home: the unload reminder still arrives, counting the checked-off items.
2. Start an arrival countdown, swipe the app away, reopen: the countdown continues.
3. Arrive home, tap **All brought in**, then walk to the edge of the home geofence and back within 15 minutes: Diagnostics shows the enter as skipped ("handled … min ago") and no new reminder.
