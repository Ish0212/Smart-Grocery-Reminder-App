# Data safety answers (Play Console)

Mirror of `docs/app-store/privacy-label.md`. Keep the two in step when the app changes.

**Does the app collect or share user data?** Yes, collects. Shares: no (Firebase is a processor for the app's own data, which Google's data safety form counts as collection, not sharing).

| Data type | Collected | Shared | Optional | Purpose | Notes |
|---|---|---|---|---|---|
| Email address | Yes | No | No | Account management | Firebase Auth |
| Name (display name) | Yes | No | Yes | Account management | Entered at sign up |
| Precise location | Yes | No | No | App functionality | Checked on the device against saved places; only the saved places are stored |
| Approximate location | Yes | No | No | App functionality | Same as above |
| App activity (list items) | Yes | No | No | App functionality | Stored in Firestore for the account, and shared only with invited list members |
| Photos (receipts) | Accessed, not collected | No | No | App functionality | Read on the device with ML Kit; not uploaded |
| App info and diagnostics | No | No | — | — | The Diagnostics log stays on the device |

**Is all data encrypted in transit?** Yes (HTTPS / Firebase TLS).

**Can users request deletion?** Yes: Settings → Delete account removes the list and the account.

**Data handling:** data is stored in Firebase (Firestore and Auth) and on the device (saved places, reminder log). Nothing is sold, and there are no ads or analytics SDKs.
