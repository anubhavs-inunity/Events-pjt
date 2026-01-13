# FCM Push Notification Testing Guide

## Testing on Same Phone (Admin → Student)

### Method 1: Test with App in Foreground (Easiest)

**Step-by-Step:**

1. **Start Backend Server**
   ```bash
   cd Backend
   go run .
   ```
   Check for: `✅ FCM initialized successfully`

2. **Login as Admin**
   - Open the app
   - Login as admin
   - Check console/logs for: `📱 FCM Token: ...`
   - Check console for: `✅ FCM token saved to backend`

3. **Login as Student (in another session or different device)**
   - **Option A**: Use a different phone/emulator for student
   - **Option B**: Continue with same phone (see Method 2)

4. **Send Broadcast Message as Admin**
   - Go to admin dashboard
   - Click "Send Broadcast Message"
   - Enter title and message
   - Select "Send to All Students" or specific group
   - Click "Send"

5. **Check Student Device**
   - If app is **open (foreground)**: You'll see the animated letter popup
   - If app is **in background**: You'll see a push notification
   - If app is **closed**: You'll see a push notification

### Method 2: Test on Same Phone (Admin → Student)

**Important Note**: When you send a message as admin, it goes to **students only**. So you need to:

**Option A: Two-Step Test (Message Already Sent)**
1. Login as **Admin**
2. Send a broadcast message to students
3. **Logout** (FCM token cleared)
4. Login as **Student**
5. The message will appear via **polling** (not FCM, since it was sent before you logged in as student)
6. Check messages page - message should be there

**Option B: Real-Time Test (Best for FCM)**
1. Login as **Student FIRST**
   - This registers FCM token for student
   - Keep app open or minimize it
2. **On another device/computer**: Login as Admin (or use web interface if available)
3. Send broadcast message from admin
4. **Student device should receive push notification immediately**

### Method 3: Test Different App States

#### Test 1: App in Foreground
1. Login as student
2. Keep app open on student dashboard
3. Send message from admin
4. **Expected**: Animated letter popup appears immediately

#### Test 2: App in Background
1. Login as student
2. Press home button (minimize app, don't close)
3. Send message from admin
4. **Expected**: Push notification appears in notification tray
5. Tap notification → App opens → Message popup appears

#### Test 3: App Closed/Terminated
1. Login as student
2. Close app completely (swipe away from recent apps)
3. Send message from admin
4. **Expected**: Push notification appears
5. Tap notification → App opens → Message appears

## Debugging & Verification

### Check Backend Logs
When you send a message, look for:
```
✅ FCM sent successfully: [Title] - [Message]
```
If you see errors:
```
❌ Error sending FCM to token ...: [error details]
```

### Check Frontend Logs
In Flutter console, look for:
- `📱 FCM Token: ...` (on login)
- `✅ FCM token saved to backend` (after login)
- `🔔 FCM message received in dashboard` (when notification arrives)
- `📬 Broadcast message detected, showing notification`

### Verify FCM Token Registration

**Check Database:**
```sql
SELECT * FROM fcm_tokens 
WHERE user_type = 'student' 
ORDER BY created_at DESC;
```

**Check Backend Cache:**
The backend logs will show token registration when student logs in.

## Common Issues & Solutions

### Issue 1: No Notification Received
**Possible Causes:**
- FCM token not registered (check logs)
- App permissions not granted (check notification settings)
- Backend FCM initialization failed (check backend logs)
- Token expired or invalid

**Solutions:**
1. Check notification permissions in phone settings
2. Verify backend shows: `✅ FCM initialized successfully`
3. Check if FCM token is saved in database
4. Try logging out and logging back in to refresh token

### Issue 2: Notification Received but No Popup
**Possible Causes:**
- App is in background (normal behavior - shows notification)
- Message notification state not set correctly

**Solutions:**
- Tap the notification to open app
- Check if `_showMessageNotification` is set to true in logs

### Issue 3: Duplicate Notifications
**Possible Causes:**
- Both FCM and polling triggering notifications
- Message ID tracking not working

**Solutions:**
- Check `_lastMessageId` tracking in student dashboard
- Verify message ID comparison logic

## Quick Test Checklist

- [ ] Backend starts without FCM errors
- [ ] Admin can login
- [ ] Student can login
- [ ] FCM token appears in logs on login
- [ ] FCM token saved to backend (check logs)
- [ ] Admin can send broadcast message
- [ ] Backend logs show: `✅ FCM sent successfully`
- [ ] Student receives notification (foreground/background/terminated)
- [ ] Tapping notification opens app
- [ ] Message appears in student's message list
- [ ] Animated popup appears when app is open

## Testing with Multiple Devices (Recommended)

**Best Setup:**
- **Device 1**: Admin (phone or emulator)
- **Device 2**: Student (phone or emulator)

This allows you to:
- See real-time notifications
- Test all app states properly
- Verify end-to-end flow

## Production Testing

Before deploying:
1. Test on real Android device
2. Test on real iOS device (if applicable)
3. Test with multiple students
4. Test with different message sizes
5. Test network conditions (WiFi, mobile data)
6. Test with app updates/restarts

---

**Note**: The same FCM token can be registered for different users. When you logout and login as a different user, the token is re-registered for that user. This is normal behavior.
