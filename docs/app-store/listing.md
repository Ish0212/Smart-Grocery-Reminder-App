# App Store listing copy

**Name (30):** Smart Grocery Reminder

**Subtitle (30):** Lists that know where you are

**Promotional text (170):** Get your list when you walk into the store, and a nudge to unload the car when you get home, so the ice cream never melts in the trunk again.

**Description:**

Smart Grocery Reminder keeps your shopping list with you and uses your saved places to remind you at the right moment.

- At the store: walk into one of your saved grocery stores and get a notification with how many items are still on your list.
- Back home: arrive home after a shopping trip and a timer starts (5–30 minutes). If you haven't marked the groceries as brought in, you get a reminder, and you can ask for another one later.
- A daily list reminder at the time you choose.
- Add stores and your home from Apple Maps search.
- Add items with Siri or Shortcuts: "Add an item to Smart Grocery".
- Your list syncs across your devices and works offline.
- Share one list with your household: invite them with a code, and everyone sees the same items.

Privacy: your location is checked on the iPhone. Only the places you save and your list are stored in your account. Reminder stats are computed on the device.

**Keywords (100):** grocery,shopping list,reminder,geofence,store,home,unload,car,groceries,list,siri

**Category:** Productivity (secondary: Shopping)

**Age rating:** 4+

## App Review notes

- **Why "Always" location:** reminders fire when the user enters a saved store or arrives home, while the app is closed. The app uses iOS region monitoring (up to 20 regions: home plus up to 19 stores). It doesn't track the live location continuously and has no location background mode.
- **Demo account:** provide a Firebase test account here before submitting (the mock demo account `demo@grocery.app` / `demo123` only exists in builds without `GoogleService-Info.plist`).
- **How to test the reminders:** the "Simulate entering a store" (Places) and "Simulate arrive home" (Arrival) buttons exist only in the demo build (without `GoogleService-Info.plist`) and Debug builds, so they can't skew real reminder stats. In the review build, save a store and home near you from Places. Settings → Diagnostics shows the reminder health checklist and the event log.
- **Shared lists:** Settings → Shared list → "Invite someone" creates a code (valid 7 days) that a second account enters under "Join a list with a code". Both accounts then see and edit the same items; reminders stay on each phone. A member can leave with "Leave shared list".
- **Account deletion (guideline 5.1.1(v)):** Settings → Account → "Delete account". After the user confirms with their password, the app leaves any shared list, deletes the user's list, items, saved places, preferences and invite codes from Firestore, then deletes the Firebase account.
