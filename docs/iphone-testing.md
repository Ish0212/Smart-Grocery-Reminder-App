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
2. **Settings → Diagnostics** (Phase 3 builds). Everything under **Reminder health** should be green; tap **Open iOS Settings** to fix anything red. Under **Geofences**, tap **Check now**: Home should say **inside**.
   - A home set while you're already inside it only fires after you leave and come back, which is exactly this test.
3. **Arrival** tab → pick the shortest delay (**5 min**).
4. Keep **at least one item unchecked** on the list. The reminder only counts items you haven't ticked off; if everything is checked, nothing is sent.
5. Lock the phone with the side button.
   - In builds **before Phase 3**, don't swipe the app away: the demo backend forgets the sign-in when the app is fully closed, and the arrival is then ignored.
   - Phase 3 builds save the sign-in and list on the phone. Once the basic test works, repeat it after swiping the app away to check that iOS relaunches it for the geofence.

**The test:**
1. Walk or drive **at least 300–500 m** away (well outside the 120 m home zone) and stay out a few minutes.
2. Come home. iOS usually notices within a few minutes; having Wi-Fi on helps.
3. About **5 minutes after arriving**, the "Groceries still in the car?" notification should appear.
4. Tap **All brought in** to clear it, or **Remind again** to snooze.

**Quick check without leaving:** Arrival tab → **Simulate arrive home** starts the same countdown and reminder.

## 5. If nothing arrives

- **Phase 3 builds:** Settings → **Diagnostics**. The event log shows each step: a launch "by a location event", "Entered home geofence", possibly "Waiting for your list to load", then "Unload reminder in 5 min". Tap the share button (top right) and send the log to Claude.
- **Older builds:** open the app → **Places**. The last line of the Status section shows the most recent location event (e.g. "Entered home geofence"). Screenshot it and send it to Claude.
- Check Settings → Smart Grocery:
  - Location = **Always**;
  - **Precise Location** on;
  - Notifications allowed.
- **Low Power Mode** and a disabled **Background App Refresh** can delay or block location wake-ups.
- **Known gap:** after iOS relaunches the app in the background, the Arrival tab may show "Ready for arrival" even though the reminder is still scheduled. Wait for the notification.

## 6. What Phase 3 builds change

See [phase-3-plan.md](phase-3-plan.md):
- the reminder survives iOS closing the app (the geofence is recognized after a relaunch and waits for the list to load);
- the demo backend saves its sign-in, list and places on the phone;
- a **Diagnostics** screen (Settings → Diagnostics, or Places → Diagnostics) shows the reminder-health checklist, what iOS thinks about each geofence, and a shareable event log.

## 7. What Phase 4 and 5 builds change

**Phase 4** ([phase-4-plan.md](phase-4-plan.md)):
- the unload reminder counts what you checked off in the last 3 hours, so you can check everything off at the store and still get it;
- walking in and out of the home geofence within 15 minutes (or after **All brought in**) doesn't re-arm the reminder;
- the Arrival countdown continues after iOS closes the app.

**Phase 5** ([phase-5-plan.md](phase-5-plan.md)): a home-screen widget. Long-press the home screen → **+** → **Smart Grocery**.
- It shows the open items, or the unload countdown with a **Brought in** button.
- It shares data with the app through an **App Group**. Sideloadly signs the widget along with the app; if you changed the bundle ID, it renames the widget's ID too.
- **If the widget only says "Open Smart Grocery to see your list"** while you're signed in, the free-account signing dropped the App Group. The app itself is unaffected; everything else in this guide still works. Try a Sideloadly update or a paid developer account if you want the widget.
