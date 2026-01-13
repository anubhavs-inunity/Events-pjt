# 🚀 Quick FCM Testing Guide

## ⚡ Fastest Way to Test (5 minutes)

### Step 1: Run the App
```bash
cd Frontend
flutter run
```

### Step 2: Check Console Logs
Look for these messages:
```
✅ Firebase initialized
✅ FCM initialized
📱 FCM Token: <long-token-string>
```

### Step 3: Copy the FCM Token
- Copy the entire token from console (it's a long string)

### Step 4: Send Test Notification from Firebase Console

1. **Go to Firebase Console:**
   - https://console.firebase.google.com
   - Select project: **Events-pjt**

2. **Navigate to Cloud Messaging:**
   - Left sidebar → **Engage** → **Cloud Messaging**
   - Click **"Send your first message"**

3. **Create Notification:**
   - **Title**: "Test Notification"
   - **Text**: "Hello from Firebase!"
   - Click **"Send test message"**

4. **Enter Token:**
   - Paste your FCM token
   - Click **"Test"**

### Step 5: Check Your Device
- **Foreground**: Local notification appears
- **Background**: System notification in tray
- **Closed**: System notification in tray

---

## ✅ Success Indicators

If you see:
- ✅ FCM token in console
- ✅ Notification appears on device
- ✅ No errors in console

**Then FCM is working! 🎉**

---

## 🐛 Quick Troubleshooting

**No token?**
- Check Firebase Console → Cloud Messaging → API is enabled
- Verify `google-services.json` is in `Frontend/android/app/`

**No notification?**
- Check device notification permissions
- Try with app in background
- Check console for errors

**Token not saved?**
- This is OK if backend endpoint doesn't exist yet
- Token will be saved once you implement `/api/save-fcm-token`

---

## 📚 Full Testing Guide

For comprehensive testing, see: `FCM_TESTING_GUIDE.md`

---

## 🎯 Next Steps

1. ✅ Test basic notification (above)
2. Implement backend endpoint `/api/save-fcm-token`
3. Test user-specific notifications
4. Integrate with attendance events

Happy Testing! 🚀

