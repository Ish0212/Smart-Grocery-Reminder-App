# App Store privacy label ("App Privacy" in App Store Connect)

These answers match `SmartGroceryReminder/PrivacyInfo.xcprivacy`. Update both together.

**Do you or your third-party partners collect data from this app?** Yes (when the Firebase backend is used; the mock/demo build keeps everything on the device).

**Tracking:** No. The app doesn't link data with third-party data for advertising and has no tracking domains.

| Data type (App Store Connect name) | Collected | Linked to the user | Used for tracking | Purpose |
|---|---|---|---|---|
| Contact Info → Email Address | Yes | Yes | No | App Functionality (sign-in) |
| Contact Info → Name | Yes | Yes | No | App Functionality (display name) |
| Identifiers → User ID | Yes | Yes | No | App Functionality (Firebase user ID keys the user's data) |
| Location → Precise Location | Yes | Yes | No | App Functionality (saved home and store coordinates for geofences) |
| User Content → Other User Content | Yes | Yes | No | App Functionality (the grocery list) |

Not collected: health, financial info, contacts, browsing/search history, purchases, usage data, diagnostics, sensitive info.

Notes for the questionnaire:
- The user's **live** location isn't sent anywhere. iOS geofencing runs on the device; only the places the user saves (home, stores) sync to Firestore.
- Reminder stats and the diagnostics log are computed and stored **on the device only**, so they aren't "collected".
- Firebase Auth / Firestore ship their own privacy manifests inside the SDK; Xcode merges them into the privacy report.
- No required-reason APIs are used by the app's own code (`NSPrivacyAccessedAPITypes` is empty). Re-check this if `UserDefaults`, file timestamps, disk space or system boot time APIs are added.
