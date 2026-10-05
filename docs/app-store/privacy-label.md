# App Store privacy label ("App Privacy" in App Store Connect)

The label covers the app's own code and the SDKs it ships. The app's own rows match `SmartGroceryReminder/PrivacyInfo.xcprivacy` (update both together). The diagnostics row comes from the Firebase SDKs' own privacy manifests (FirebaseAuth and FirebaseFirestore declare it), not from the app's manifest. Re-check it against Xcode's privacy report when the Firebase version changes.

**Do you or your third-party partners collect data from this app?** Yes (when the Firebase backend is used; the mock/demo build keeps everything on the device).

**Tracking:** No. The app doesn't link data with third-party data for advertising and has no tracking domains.

| Data type (App Store Connect name) | Collected | Linked to the user | Used for tracking | Purpose |
|---|---|---|---|---|
| Contact Info → Email Address | Yes | Yes | No | App Functionality (sign-in) |
| Contact Info → Name | Yes | Yes | No | App Functionality (display name) |
| Identifiers → User ID | Yes | Yes | No | App Functionality (Firebase user ID keys the user's data) |
| Location → Precise Location | Yes | Yes | No | App Functionality (saved home and store coordinates for geofences) |
| User Content → Other User Content | Yes | Yes | No | App Functionality (the grocery list) |
| Diagnostics → Other Diagnostic Data | Yes | No | No | Analytics (declared by the Firebase Auth and Firestore SDKs) |

Not collected: health, financial info, contacts, browsing/search history, purchases, usage data, crash data, performance data, sensitive info.

Notes for the questionnaire:
- The user's **live** location isn't stored or synced. iOS geofencing runs on the device; only the places the user saves (home, stores) sync to Firestore. One exception: when the user searches for a store or address, the Apple Maps search (MapKit) is sent with a region around the current location (or around home), so Apple receives an approximate location with the query. Apple processes it under its own privacy policy; the app doesn't keep it.
- **Shared lists:** when a user joins or shares a list, every member of that list can read and edit its items, see who checked an item off (as a user ID), and see the list's member user IDs. Saved places, preferences and reminders stay private to each user.
- **Receipt scanning** reads the photo on the device with Vision; the photo and prices are never uploaded or kept, so neither Photos nor Purchases is "collected". Items the user adds from a receipt are ordinary list items (User Content, above). The camera permission string is in `Info.plist`; choosing a photo uses `PhotosPicker`, which needs no permission.
- Reminder stats and the diagnostics log are computed and stored **on the device only**, so they aren't "collected".
- Firebase Auth / Firestore ship their own privacy manifests inside the SDK; Xcode merges them into the privacy report.
- No required-reason APIs are used by the app's own code (`NSPrivacyAccessedAPITypes` is empty). Re-check this if `UserDefaults`, file timestamps, disk space or system boot time APIs are added.
