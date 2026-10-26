# Google Play listing copy

**App name (30):** Smart Grocery Reminder

**Short description (80):** Shopping list that reminds you at the store, and to unload the car at home.

**Full description:**

Smart Grocery Reminder keeps your shopping list with you and uses the places you save to remind you at the right moment.

- At the store: walk into a saved grocery store and get a notification with how many items are still on your list.
- Back home: arrive home after a shopping trip and a timer starts (5–30 minutes). If you haven't marked the groceries as brought in, you get a reminder, and you can ask for another one in 10 minutes.
- Scan a receipt: take or choose a photo, and the app checks off the items you bought. The photo is read on your phone and isn't uploaded.
- Share one list with your household: invite people with a code, and everyone sees the same items. Reminders stay personal.
- Add stores and your home from Google Places search, or from where you are now.
- A widget on your home screen shows your open items and the unload timer.
- Your list syncs across your phones and works offline.

Privacy: your location is checked on your phone against the places you save. Only the places you save and your list are stored in your account. You can delete your account and everything in it from Settings.

**Category:** Productivity (secondary: Shopping)

**Content rating:** Everyone

**Tags / keywords:** grocery list, shopping list, reminder, geofence, store, unload car, receipt

**Privacy policy:** `https://<project-id>.web.app/privacy`

**Support:** `https://<project-id>.web.app/support`

## Reviewer notes (Play "App access" and location declaration)

- **Background location:** reminders fire when the user enters a saved grocery store or home, while the app is closed. The app uses geofences (up to 20 places: home plus 19 stores). It doesn't track the device continuously. Location is requested in two steps: while the app is in use, then "all the time", which the user can refuse.
- **Demo account:** provide a Firebase test account here before submitting (`demo@grocery.app` only exists in builds without google-services.json).
- **Test the reminders:** save a store or home from the Places tab (use the current location, or search). Enter the place, or use the Arrival tab's timer ("Start timer (I'm home)") to see the countdown and reminder.
- **Shared lists:** Settings → Shared list → "Create an invite code" on one account, and "Join a list with a code" on a second account.
- **Receipt scanning:** List tab → "Scan receipt". Choosing a photo needs no permission; the camera is the system camera app.
