# Smart Grocery Reminder App

SwiftUI prototype for location-aware grocery lists and home-arrival “unload the car” reminders. It runs on a built-in mock backend, and switches to Firebase Auth + Firestore automatically when a `GoogleService-Info.plist` is present.

## Features in this prototype

- Shopping list with add / complete / delete
- Email/password sign-in: Firebase Auth, or the mock backend (`demo@grocery.app` / `demo123`)
- List and preferences synced live with Firestore (loads from the local cache offline, updates across devices), or kept in memory in mock mode
- Customizable home-arrival unload timer (5–30 minutes)
- Core Location geofencing service for home + grocery stores
- Apple Maps search to add grocery stores or set your home address (up to 19 stores, the iOS geofence limit)
- Siri / Shortcuts / Spotlight: “Add an item to Smart Grocery” without opening the app
- Local notifications: daily list, store entry, car-unload (+ repeat / completion actions)
- Settings for reminder preferences
- Simulator hooks to fake store entry and home arrival

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

### Running tests

```bash
xcodegen generate
xcodebuild -project SmartGroceryReminder.xcodeproj -scheme SmartGroceryReminder \
  -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Or press **⌘U** in Xcode.

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
.github/workflows/   # iOS CI
docs/PLAN.md         # architecture & phased roadmap
docs/phase-2-plan.md # Phase 2 (Polish) plan
project.yml          # XcodeGen spec
firestore.rules      # Firestore security rules
firebase.json        # Firebase CLI config (deploys the rules)
```

## Firebase

The Firebase SDK (`FirebaseAuth`, `FirebaseFirestore`) is already a Swift package dependency in `project.yml`. At launch, `FirebaseBootstrap` configures Firebase only if `GoogleService-Info.plist` is in the app bundle; otherwise the app uses the mock backend. **Settings → Account → Backend** shows which one is active.

To use a real Firebase project:

1. In the [Firebase console](https://console.firebase.google.com), create a project and add an **iOS app** with bundle id `com.smartgrocery.reminder`
2. **Authentication** → enable the **Email/Password** provider
3. **Firestore Database** → create a database
4. Download `GoogleService-Info.plist` to `SmartGroceryReminder/GoogleService-Info.plist` (gitignored), then run `xcodegen generate`
5. Deploy the security rules: `firebase deploy --only firestore:rules` (with the [Firebase CLI](https://firebase.google.com/docs/cli)), or paste `firestore.rules` into the console's **Rules** tab

With Firebase, users stay signed in across launches. Data is stored under `users/{uid}`: `items/{itemId}` for list items and `preferences/main` for reminder settings. The rules only let a signed-in user read and write their own tree.

See [docs/PLAN.md](docs/PLAN.md) for data shape, geofence flow, and privacy notes.

## Siri & Shortcuts

The app ships an App Intent, **Add Grocery Item**, plus App Shortcuts, so you can say “Add an item to Smart Grocery” (or run it from the Shortcuts app / Spotlight). Siri asks for the item and adds it to your list. It runs in the app's process without opening the app. You must be signed in: with Firebase the session is restored automatically; in mock mode the app must already be running and signed in.

## Privacy / permissions

The Info.plist requests:

- **When In Use** + **Always** location (geofences for stores & home)
- Background location mode for region monitoring
- Notification permission at runtime after sign-in

## License

Prototype — use and extend freely for your project.
