# Releasing to the App Store

Everything that can live in the repo is done: privacy manifest, privacy label answers (`privacy-label.md`), listing copy and review notes (`listing.md`), export compliance (`ITSAppUsesNonExemptEncryption = false` in Info.plist; the app only uses HTTPS), in-app account deletion and password reset, privacy policy and support pages (`site/`, linked in the app), test tools hidden from the App Store build, automated screenshots and a signed upload workflow (`.github/workflows/app-store.yml`).

The steps below need your accounts, so only you can do them.

## 1. Accounts (once)

1. Join the Apple Developer Program (US$99/year): https://developer.apple.com/programs/enroll/
2. To sell in the EU, App Store Connect → Business → complete the **Digital Services Act trader status** (as a trader, your contact details are shown on the EU store page; as a non-trader, the app isn't offered in the EU).
3. In App Store Connect → Apps → **+ New App**: platform iOS, name "Smart Grocery Reminder", bundle ID `com.smartgrocery.reminder`, SKU of your choice.
4. In Certificates, Identifiers & Profiles, register the App Group `group.com.smartgrocery.reminder` and turn on App Groups for both `com.smartgrocery.reminder` and `com.smartgrocery.reminder.widget` (automatic signing creates the IDs on the first archive, but the group must be enabled on them).

## 2. Firebase (production)

1. In the Firebase console, add an iOS app with bundle ID `com.smartgrocery.reminder` and download `GoogleService-Info.plist`.
2. Enable Authentication → Email/Password, and create Firestore. Optionally, under Authentication → Templates, set the sender name of the password reset email to "Smart Grocery Reminder".
3. Replace `SUPPORT_EMAIL` in `site/privacy.html` and `site/support.html` with the address you want users to write to.
4. Deploy the rules and the website: `firebase deploy --only firestore:rules,hosting`. The rules must be deployed before the new build is used: account deletion needs them.
5. Your privacy policy is then at `https://<project-id>.web.app/privacy` and support at `https://<project-id>.web.app/support`. The app links to these addresses itself (built from the project ID in `GoogleService-Info.plist`, see `SmartGroceryReminder/App/AppLinks.swift`). If you serve the site from a custom domain instead, change `AppLinks.website`.

## 3. GitHub secrets (Settings → Secrets and variables → Actions)

| Secret | Value |
|---|---|
| `APPLE_TEAM_ID` | Your 10-character Team ID (developer.apple.com → Membership) |
| `ASC_KEY_ID` | App Store Connect → Users and Access → Integrations → App Store Connect API → **Team Keys** → generate a key with the **Admin** role (cloud-managed distribution signing needs it) |
| `ASC_ISSUER_ID` | Shown above the keys list on the same page |
| `ASC_KEY_P8` | `base64 -i AuthKey_XXXX.p8` |
| `GOOGLE_SERVICE_INFO_PLIST` | `base64 -i GoogleService-Info.plist` |

## 4. Build and upload

`gh workflow run app-store.yml -f release=true`, or Actions → App Store → Run workflow → tick "release". The build number is the run number. After ~15 minutes the build shows up in App Store Connect → TestFlight.

This job can't be tried until the secrets above exist, so the first run is its test. It signs automatically: Xcode creates the certificates and profiles it needs through the API key. If a run fails with a certificate limit error, revoke the older "Apple Development" certificates the key created (Certificates, Identifiers & Profiles → Certificates) and run it again.

## 5. Fill in the listing in App Store Connect

- **Copy:** from `listing.md` (name, subtitle, promotional text, description, keywords, category).
- **Privacy Policy URL:** `https://<project-id>.web.app/privacy`; **Support URL:** `https://<project-id>.web.app/support`.
- **App Privacy:** answer as in `privacy-label.md`.
- **Age rating:** answer "None" to every content question (result: 4+). The only content people create is grocery lists, shared only with people they invite by code; there's no public content, chat or web browsing.
- **Screenshots:** download the `app-store-screenshots` artifact from the latest App Store workflow run: List, Arrival, Places and Settings on a 6.9" iPhone (1320×2868; the job fails at any other size). Upload them to the 6.9" slot; App Store Connect scales them for smaller iPhones.
- **App Review:** paste the review notes from `listing.md`, and create a real test account in Firebase (with a sample list) for the "Sign-in required" fields.
- **Pricing:** Free, availability of your choice.

## 6. Submit

Pick the TestFlight build on the version page, then **Add for Review** → **Submit**. Test it through TestFlight on your iPhone first.
