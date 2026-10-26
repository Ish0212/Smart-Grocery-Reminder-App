# Releasing to Google Play

The repo already does the parts that can be automated: the signed bundle and emulator screenshots (`.github/workflows/android-release.yml`), the listing copy (`listing.md`) and the data-safety answers (`data-safety.md`). The steps below need your accounts, so only you can do them.

## 1. Accounts (once)

1. Create a Google Play Console developer account (US$25, one time): https://play.google.com/console/signup
2. In the Console, **Create app**: name "Smart Grocery Reminder", default language English, App, Free.
3. Complete the **App content** checklist: privacy policy URL (`https://<project-id>.web.app/privacy`), data safety (from `data-safety.md`), content rating questionnaire (answer "No" to everything: result is Everyone), target audience (18+), ads (No), and the **Location** declaration: background location is used for grocery store and home arrival reminders (copy from `listing.md`).

## 2. Firebase (production)

1. In the Firebase console (the same project as iOS, or a new one), add an **Android app** with package name `com.smartgrocery.reminder`, and download `google-services.json`.
2. Authentication → Email/Password, and Firestore (rules from `firestore.rules` are shared with iOS; deploy them with `firebase deploy --only firestore:rules,hosting`).
3. Replace `SUPPORT_EMAIL` in `site/` with the support address (already done for iOS if you did that step).

## 3. Keys

- **Signing key:** create one, once, and keep a backup. Play App Signing is the default, so Google keeps the app signing key and this key is only the upload key:
  ```bash
  keytool -genkeypair -v -keystore upload.keystore -alias upload -keyalg RSA -keysize 2048 -validity 10000
  ```
- **Maps / Places key:** Google Cloud console → APIs & Services → enable **Places API (New)** and **Maps SDK for Android**, then create an API key restricted to Android apps with the package name and signing certificate.

## 4. GitHub secrets (Settings → Secrets and variables → Actions)

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 upload.keystore` |
| `ANDROID_KEYSTORE_PASSWORD` | The keystore password |
| `ANDROID_KEY_ALIAS` | `upload` (or the alias you chose) |
| `ANDROID_KEY_PASSWORD` | The key password |
| `GOOGLE_SERVICES_JSON_BASE64` | `base64 -w0 google-services.json` |
| `MAPS_API_KEY` | The Maps key (optional; without it place search is off) |

## 5. Build

Actions → **Android release** → Run workflow. Tick **screenshots** for the Play Store images (a 6–8 minute emulator run; download the `play-screenshots` artifact). Tick **bundle** to build the signed `.aab` (download `smart-grocery-release-aab`). The version code is the run number, so each upload needs a new run.

## 6. Upload and submit

1. Play Console → Testing → **Internal testing** → Create release → upload the `.aab`. Test it on your phone from the internal track first.
2. Main store listing: paste the copy from `listing.md`, upload the screenshots (phone, at least 2 images).
3. Send for review, then roll out to production.

The first build from Windows needs the Gradle wrapper: run `gradle wrapper --gradle-version 8.10.2` once inside `android/` (with Gradle installed), then commit the `gradlew` files. The workflows install Gradle themselves, so they work without it.
