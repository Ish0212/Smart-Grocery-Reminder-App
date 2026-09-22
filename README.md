# Smart Grocery Reminder App

SwiftUI prototype for location-aware grocery lists and home-arrival “unload the car” reminders. Firebase Auth/Firestore is stubbed behind protocols so you can run with a mock backend first.

## Features in this prototype

- Shopping list with add / complete / delete
- Mock authentication (`demo@grocery.app` / `demo123`)
- Customizable home-arrival unload timer (5–30 minutes)
- Core Location geofencing service for home + grocery stores
- Local notifications: daily list, store entry, car-unload (+ repeat / completion actions)
- Settings for reminder preferences
- Simulator hooks to fake store entry and home arrival

## Requirements

- macOS with **Xcode 15+**
- iOS **17+** simulator or device
- (Optional) Firebase project for production backend

> This repo was scaffolded on Windows. Builds and tests run in GitHub Actions (see below), so you don't need a Mac to verify changes.

## Continuous integration

Every push to `main` and every pull request runs [`.github/workflows/ios-ci.yml`](.github/workflows/ios-ci.yml) on a macOS runner:

1. `xcodegen generate` from `project.yml` (the `.xcodeproj` is generated, not committed)
2. `xcodebuild build test` on an available iPhone simulator

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

### Demo login

| Field | Value |
|-------|-------|
| Email | `demo@grocery.app` |
| Password | `demo123` |

## Project layout

```
SmartGroceryReminder/
  App/AppState.swift
  Models/Models.swift
  Services/          # auth, list, location, notifications, timer
  Views/             # auth, list, arrival, places, settings
  Assets.xcassets
  Info.plist
SmartGroceryReminderTests/  # XCTest unit tests
.github/workflows/   # iOS CI
docs/PLAN.md         # architecture & phased roadmap
Config/GoogleService-Info.example.plist
project.yml          # XcodeGen spec
```

## Firebase (Phase 1)

1. Create a Firebase iOS app with bundle id `com.smartgrocery.reminder`
2. Download `GoogleService-Info.plist` into the app target (gitignored)
3. Add SPM package `https://github.com/firebase/firebase-ios-sdk` → `FirebaseAuth`, `FirebaseFirestore`
4. Call `FirebaseApp.configure()` in `FirebaseBootstrap`
5. Construct `AppState(useMockBackend: false)`

See [docs/PLAN.md](docs/PLAN.md) for data shape, geofence flow, and privacy notes.

## Privacy / permissions

The Info.plist requests:

- **When In Use** + **Always** location (geofences for stores & home)
- Background location mode for region monitoring
- Notification permission at runtime after sign-in

## License

Prototype — use and extend freely for your project.
