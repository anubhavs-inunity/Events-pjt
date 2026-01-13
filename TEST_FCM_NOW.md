# 🧪 Test FCM Right Now - Step by Step

## 📱 Step 1: Run on Android Device/Emulator

```bash
cd Frontend
flutter run -d android
```

**OR** if you have a specific device:
```bash
flutter devices  # List available devices
flutter run -d <device-id>
```

---

## ✅ Step 2: Check Console Logs

After the app starts, look for these messages in the console:

```
✅ Firebase initialized
✅ FCM initialized
✅ User granted notification permission
📱 FCM Token: <long-token-string>
```

**Copy the FCM Token** - you'll need it in the next step!

---

## 🔔 Step 3: Send Test Notification from Firebase Console

### A. Open Firebase Console
1. Go to: https://console.firebase.google.com
2. Select your project: **Events-pjt**

### B. Navigate to Cloud Messaging
1. Click **"Engage"** in left sidebar
2. Click **"Cloud Messaging"**
3. Click **"Send your first message"** or **"New campaign"**

### C. Create Test Notification
1. Select **"Firebase Notification messages"**
2. Fill in:
   - **Notification title**: "Test Notification"
   - **Notification text**: "Hello from Firebase! This is a test."
3. Click **"Send test message"** button

### D. Enter Your FCM Token
1. Paste the FCM token you copied from Step 2
2. Click **"Test"**

---

## 📲 Step 4: Check Your Device

### If App is in Foreground:
- You should see a **local notification** appear
- Notification shows title and body

### If App is in Background:
- You should see a **system notification** in the notification tray
- Swipe down to see it

### If App is Closed:
- You should see a **system notification** in the notification tray
- Tap it to open the app

---

## 🎯 Step 5: Test Different Scenarios

### Test 1: Foreground Notification
1. Keep app open and visible
2. Send notification from Firebase Console
3. ✅ Should see local notification

### Test 2: Background Notification
1. Press home button (minimize app)
2. Send notification from Firebase Console
3. ✅ Should see system notification in tray

### Test 3: Closed App Notification
1. Close the app completely
2. Send notification from Firebase Console
3. ✅ Should see system notification
4. Tap notification → app should open

### Test 4: Notification Tap
1. Send notification
2. Tap the notification
3. ✅ App should open
4. Check console for: `🔔 Notification tapped`

---

## 🐛 Troubleshooting

### No FCM Token?
- Check console for errors
- Verify `google-services.json` is in `Frontend/android/app/`
- Check internet connection
- Restart app

### No Notification Appears?
- Check device notification permissions:
  - Settings → Apps → Your App → Notifications → Enable
- Check console for errors
- Try with app in different states (foreground/background/closed)

### Token Not Saved to Backend?
- This is OK if backend endpoint doesn't exist yet
- Token is still generated and can be used for testing
- Implement `/api/save-fcm-token` endpoint later

---

## ✅ Success Checklist

- [ ] App runs on Android without errors
- [ ] FCM token appears in console
- [ ] Notification appears when app is in foreground
- [ ] Notification appears when app is in background
- [ ] Notification appears when app is closed
- [ ] Tapping notification opens the app
- [ ] Console shows notification events

---

## 🚀 Quick Test Command

```bash
# Run app and watch for FCM token
cd Frontend && flutter run -d android | grep -E "(FCM|Firebase|Token)"
```

---

## 📝 What to Look For

**In Console:**
```
✅ Firebase initialized
✅ FCM initialized  
✅ User granted notification permission
📱 FCM Token: <your-token-here>
✅ FCM token saved to backend (if endpoint exists)
```

**On Device:**
- Notification appears
- Notification is clickable
- App opens when notification is tapped

---

## 🎉 You're Done!

If you see notifications appearing, **FCM is working!** 🎊

Next steps:
1. Implement backend endpoint to save tokens
2. Send notifications from your backend
3. Integrate with attendance events

Happy Testing! 🚀

