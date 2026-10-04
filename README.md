# Smart Grocery Reminder App

SwiftUI app for location-aware grocery lists and home-arrival “unload the car” reminders. It runs on a built-in mock backend, and switches to Firebase Auth + Firestore automatically when a `GoogleService-Info.plist` is present. Releasing it to the App Store: [docs/app-store/release.md](docs/app-store/release.md).

## Features

- Shopping list with add / complete / delete
- Email/password sign-in: Firebase Auth, or the mock backend (`demo@grocery.app` / `demo123`), with a password reset email
- Account deletion in the app (Settings → Account → Delete Account): removes the list, places, settings and invites, then the account
- List and preferences synced live with Firestore (loads from the local cache offline, updates across devices), or saved on the device in mock mode
- Customizable home-arrival unload timer (5–30 minutes)
- Core Location geofencing service for home + grocery stores
- Apple Maps search to add grocery stores or set your home address (up to 19 stores, the iOS geofence limit)
- Siri / Shortcuts / Spotlight: “Add an item to Smart Grocery” without opening the app
- Home-screen widget: open items, or the unload countdown with a **Brought in** button
- Shared family lists: invite people into your list with a code (Settings → Shared list); reminders stay personal
- Local notifications: daily list, store entry, car-unload (+ repeat / completion actions)
- Settings for reminder preferences
- Reminders survive iOS closing the app: geofence wake-ups are recognized after a relaunch and wait for the list to load
- Diagnostics screen (Settings → Diagnostics): reminder-health checklist, geofence states and a shareable event log
- Simulator hooks to fake store entry and home arrival (demo and Debug builds only, never in the App Store build)
- Privacy policy and support pages (`site/`, served by Firebase Hosting), linked from Settings → About

## Requirements

- macOS with **Xcode 26.2+** (required by the Firebase SDK)
- iOS **17+** simulator or device
- (Optional) Firebase project for the real backend (see [Firebase](#firebase))

> This repo was scaffolded on Windows. Builds and tests run in GitHub Actions (see below), so you don't need a Mac to verify changes.

## Continuous integration

Every push to `main` and every pull request runs [`.github/workflows/ios-ci.yml`](.github/workflows/ios-ci.yml) on a macOS runner:

1. `xcodegen generate` from `project.yml` (the `.xcodeproj` is generated, not committed)
2. `xcodebuild build test` on an available iPhone simulator (Swift packages are cached between runs)

CI has no `GoogleService-Info.plist`, so it builds the Firebase code but runs the app and tests on the mock backend.

If a run fails, open it under the repo's **Actions** tab to read the log, or download the `xcresult` artifact and open it in Xcode.

## Reliability suite

Location reminders run when iOS decides, not when the app does, so the riskiest code is the code
that reacts to iOS. `SmartGroceryReminderTests/Reliability/` tests it scenario by scenario, with
a `FakeLocationManager` standing in for CoreLocation (behind the `LocationManaging` protocol):

| Risk | Scenarios |
|---|---|
| Permissions | Always downgraded to While Using, Precise Location off, access denied, the same change reported twice, access restored |
| Region monitoring | iOS refuses a geofence, more than 20 places, re-applying places touches nothing, region-state reports never become reminders |
| Duplicate events | the same enter twice, flapping at the home boundary, a replay while the list loads: one reminder each |
| Relaunch | the countdown and cooldowns survive the app being killed; an ended countdown and corrupt state files start clean |

The suite found two bugs: when iOS refused to monitor a place, Reminder health kept showing it as
watched; and an enter iOS reported twice within moments sent two unload reminders, because the
second was decided before the first had recorded its cooldown.

## Offline editing and conflicts

Edits are written to Firestore's local cache first, so the list works offline and changes sync
when the phone reconnects. If a change has waited more than 2 seconds for the server, the list
says "Saved on this iPhone. It will sync when you're back online."

An edit sends only the fields it changed (`ItemPatch`), never the whole item. So when family
members edit the same item offline, their changes merge field by field instead of the last one
overwriting everything:

| Situation | Outcome |
|---|---|
| Two people change different fields (one renames it, one checks it off) | Both changes survive |
| Two people change the same field | The last write to reach the server wins |
| One person deletes an item, another edits it | It stays deleted |
| Two people check off the same item | It stays checked off, credited to whoever synced last, so a check-off made offline can take over someone else's unload reminder |

What the tests prove: the app sends patches containing only the fields that changed
(`ItemPatchTests`, `ConflictReliabilityTests`); the demo backend merges them field by field;
and the security rules accept a partial update that leaves another member's `completedBy` alone
(`firestore-tests`). Merging per field on the server is Firestore's documented `updateData`
behaviour, which the suite relies on rather than exercises.

## Quick start (Mac)

### Option A — XcodeGen (recommended)

```bash
brew install xcodegen
cd SmartGroceryReminder
xcodegen generate
open SmartGroceryReminder.xcodeproj
```

### Option B — New Xcode project

1. Create an iOS App (SwiftUI, Swift) named `SmartGroceryReminder`
2. Replace the generated source with the `SmartGroceryReminder/` folder from this repo
3. Set the target’s Info.plist to `SmartGroceryReminder/Info.plist` (or merge the location usage strings)
4. Build & run

### Install on an iPhone from Windows (no Mac)

CI can build an unsigned `.ipa` that [Sideloadly](https://sideloadly.io) signs with your Apple ID and installs over USB. A free Apple ID works; the install expires after 7 days and must be re-signed.

1. **Build:** Actions tab → **iOS CI** → **Run workflow** → pick the branch, tick **device_ipa** (or `gh workflow run ios-ci.yml --ref <branch> -f device_ipa=true`). Download the `SmartGroceryReminder-unsigned-ipa` artifact and unzip it.
2. **Windows prerequisites:** install **iTunes** and **iCloud** from apple.com (not the Microsoft Store versions), then install Sideloadly.
3. **Install:** connect the iPhone by USB and tap **Trust**. In Sideloadly, pick the phone, enter your Apple ID, drop in the `.ipa` and press **Start** (enter the 2FA code when asked). If it says the bundle ID isn't available, open **Advanced options** and change the bundle ID (e.g. add your initials).
4. **On the iPhone:** Settings → Privacy & Security → **Developer Mode** → on (the phone restarts). Then Settings → General → **VPN & Device Management** → trust your Apple ID's developer app.
5. Open **Smart Grocery**. Without a `GoogleService-Info.plist` the build uses the mock backend: sign in with the demo account below. Allow notifications and choose **Always** for location so geofences work in the background.

For the full walkthrough, including the leave-home field test and troubleshooting with the Diagnostics screen, see [docs/iphone-testing.md](docs/iphone-testing.md).

### Running tests

```bash
xcodegen generate
xcodebuild -project SmartGroceryReminder.xcodeproj -scheme SmartGroceryReminder \
  -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Or press **⌘U** in Xcode.

### Firestore rules tests (any OS)

Needs Node 20+ and Java 21+. Starts the Firestore emulator, runs `firestore-tests/rules.test.js` against `firestore.rules`, then stops it:

```bash
cd firestore-tests
npm ci
npm test
```

CI runs the same job on Linux whenever the rules or these tests change (`.github/workflows/firestore-rules.yml`).

### Demo login (mock backend)

| Field | Value |
|-------|-------|
| Email | `demo@grocery.app` |
| Password | `demo123` |

## Project layout

```
SmartGroceryReminder/
  App/AppState.swift
  Models/Models.swift
  Services/          # auth, list sync, location, place search, notifications, timer
  Intents/           # Siri / Shortcuts (App Intents)
  Views/             # auth, list, arrival, places, settings
  Assets.xcassets
  Info.plist
SmartGroceryReminderTests/  # XCTest unit tests
SmartGroceryReminderUITests/  # takes the App Store screenshots
SmartGroceryWidget/  # home-screen widget
site/                # privacy policy and support pages (Firebase Hosting)
.github/workflows/   # iOS CI, Firestore rules tests, App Store screenshots and upload
docs/app-store/      # listing copy, privacy label, release steps
docs/PLAN.md         # architecture & phased roadmap
docs/phase-2-plan.md # Phase 2 (Polish) plan
project.yml          # XcodeGen spec
firestore.rules      # Firestore security rules
firebase.json        # Firebase CLI config (deploys the rules and the website)
```

## Firebase

The Firebase SDK (`FirebaseAuth`, `FirebaseFirestore`) is already a Swift package dependency in `project.yml`. At launch, `FirebaseBootstrap` configures Firebase only if `GoogleService-Info.plist` is in the app bundle; otherwise the app uses the mock backend. In demo and Debug builds, **Settings → Account → Backend** shows which one is active.

To use a real Firebase project:

1. In the [Firebase console](https://console.firebase.google.com), create a project and add an **iOS app** with bundle id `com.smartgrocery.reminder`
2. **Authentication** → enable the **Email/Password** provider
3. **Firestore Database** → create a database
4. Download `GoogleService-Info.plist` to `SmartGroceryReminder/GoogleService-Info.plist` (gitignored), then run `xcodegen generate`
5. Deploy the security rules and the privacy/support website: `firebase deploy --only firestore:rules,hosting` (with the [Firebase CLI](https://firebase.google.com/docs/cli))

With Firebase, users stay signed in across launches. Data is stored in `users/{uid}` (the active list, and `preferences/main` for reminder settings and saved places), `lists/{listId}` (members, and the shared `items/{itemId}`; a personal list's ID is its owner's uid) and `invites/{code}`. `firestore.rules` lets users reach only their own data and the lists they belong to; `firestore-tests/` tests the rules on the emulator.

See [docs/PLAN.md](docs/PLAN.md) for data shape, geofence flow, and privacy notes.

## Siri & Shortcuts

The app ships an App Intent, **Add Grocery Item**, plus App Shortcuts, so you can say “Add an item to Smart Grocery” (or run it from the Shortcuts app / Spotlight). Siri asks for the item and adds it to your list. It runs in the app's process without opening the app. You must be signed in: with Firebase the session is restored automatically; in mock mode the app must already be running and signed in.

## Privacy / permissions

The Info.plist requests:

- **When In Use** + **Always** location (geofences for stores & home)
- No location background mode: iOS region monitoring relaunches the app when a geofence is crossed
- Notification permission at runtime after sign-in

The App Store privacy answers are in [docs/app-store/privacy-label.md](docs/app-store/privacy-label.md) and match `SmartGroceryReminder/PrivacyInfo.xcprivacy`.

## License

Prototype — use and extend freely for your project.
