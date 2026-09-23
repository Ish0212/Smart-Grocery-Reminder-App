# Testing on an iPhone (from Windows, no Mac)

How to install the app on your own iPhone with **Sideloadly** and field-test the home-arrival reminder.

## 1. Get the app file (.ipa)

CI builds an unsigned `.ipa` that Sideloadly signs with your Apple ID.

- **Ask Claude:** "build me a fresh iPhone build". It runs the build and downloads the file to `build/ipa-download/SmartGroceryReminder-unsigned.ipa`.
- **Or do it yourself:**
  1. GitHub → **Actions** → **iOS CI** → **Run workflow**.
  2. Pick the branch and tick **device_ipa**.
  3. Download the `SmartGroceryReminder-unsigned-ipa` artifact and unzip it.
- **From a terminal:** `gh workflow run ios-ci.yml --ref <branch> -f device_ipa=true`, then `gh run download <run-id> -n SmartGroceryReminder-unsigned-ipa -D build/ipa-download`.

Builds without a `GoogleService-Info.plist` use the **mock backend**. Sign in with the demo account `demo@grocery.app` / `demo123`.

## 2. Set up the PC (one time)

1. Go to **https://sideloadly.io** and download **Sideloadly for Windows**.
2. Install **iTunes** and **iCloud** using the links on Sideloadly's page.
   - Use the website versions. The **Microsoft Store versions don't work** with Sideloadly.
3. Install iTunes, then iCloud, then Sideloadly. Restart the PC if asked.

## 3. Install on the phone

1. Plug the iPhone into the PC with a USB cable, unlock it, tap **Trust** and enter your passcode.
2. Open **Sideloadly**. Your iPhone appears in the **iDevice** list.
3. Drag the `.ipa` onto the **IPA** icon.
4. Enter your Apple ID email in **Apple account** and click **Start**.
   - Enter your password and the 2FA code when asked, then wait for **Done**.
   - A free Apple ID works. If you'd rather not use your main one, a secondary Apple ID is fine.
   - If you get a **bundle ID** error: open **Advanced options**, tick **Change bundle ID**, enter e.g. `com.ishan.smartgrocery`, and click **Start** again.
5. On the iPhone:
   - Settings → **Privacy & Security** → **Developer Mode** → on. The phone restarts; tap **Turn On** afterwards.
   - Settings → **General** → **VPN & Device Management** → under **Developer App**, tap your Apple ID → **Trust**.
6. Open **Smart Grocery** and sign in.
   - Allow notifications.
   - Choose **Always Allow** for location.
   - Keep **Precise Location** on: Settings → Smart Grocery → Location. Geofences don't work with approximate location.

**The install expires after 7 days.** Repeat step 3 to renew it; your phone settings stay as they are. You can unplug the phone as soon as the install finishes, because the app runs on its own.

## 4. Field test: the "unload the car" reminder

**Before you leave (at home):**
1. **Places** tab → **Use current location as home**. The Status section should list "Home" under Monitoring.
2. **Arrival** tab → pick the shortest delay (**5 min**).
3. Keep **at least one item unchecked** on the list. The reminder only counts items you haven't ticked off; if everything is checked, nothing is sent.
4. Lock the phone with the side button.
   - **Don't swipe the app away** in the app switcher.
   - In builds before Phase 3, the mock backend forgets the sign-in when the app is fully closed, and the arrival is then ignored.

**The test:**
1. Walk or drive **at least 300–500 m** away (well outside the 120 m home zone) and stay out a few minutes.
2. Come home. iOS usually notices within a few minutes; having Wi-Fi on helps.
3. About **5 minutes after arriving**, the "Groceries still in the car?" notification should appear.
4. Tap **All brought in** to clear it, or **Remind again** to snooze.

**Quick check without leaving:** Arrival tab → **Simulate arrive home** starts the same countdown and reminder.

## 5. If nothing arrives

- Open the app → **Places**. The last line of the Status section shows the most recent location event (e.g. "Entered home geofence"). Screenshot it and send it to Claude.
- Check Settings → Smart Grocery:
  - Location = **Always**;
  - **Precise Location** on;
  - Notifications allowed.
- **Low Power Mode** and a disabled **Background App Refresh** can delay or block location wake-ups.
- **Known gap:** after iOS relaunches the app in the background, the Arrival tab may show "Ready for arrival" even though the reminder is still scheduled. Wait for the notification.

## 6. What Phase 3 changes here

Phase 3 (see [phase-3-plan.md](phase-3-plan.md)):
- makes the reminder survive iOS closing the app;
- makes the demo backend save its data on the phone;
- adds a **Diagnostics** screen with a "Reminder health" checklist and a shareable event log.

With a Phase 3 build, use Diagnostics instead of the Status line in step 5: check that everything is green before leaving, and share the log if anything goes wrong.
