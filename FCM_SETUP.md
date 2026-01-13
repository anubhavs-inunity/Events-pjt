# FCM (Firebase Cloud Messaging) Setup Guide

## ✅ Completed Steps

### 1. Frontend Configuration
- ✅ Added FCM dependencies to `pubspec.yaml`:
  - `firebase_core: ^2.24.2`
  - `firebase_messaging: ^14.7.9`
  - `flutter_local_notifications: ^16.3.0`
  - `shared_preferences: ^2.2.2`

- ✅ Android Configuration:
  - Added Google Services plugin to `settings.gradle.kts`
  - Applied Google Services plugin in `app/build.gradle.kts`
  - Added notification permission to `AndroidManifest.xml`
  - Added FCM notification channel metadata

- ✅ Created FCM Service (`lib/services/fcm_service.dart`):
  - Handles foreground and background messages
  - Manages FCM token registration
  - Local notification support
  - User info management (admin/student)

- ✅ Updated `main.dart`:
  - Firebase initialization
  - FCM service initialization
  - Background message handler

- ✅ Configuration Files:
  - `google-services.json` ✅ (Android)
  - `GoogleService-Info.plist` ✅ (iOS)

## 📋 Next Steps

### 1. Backend Integration (Go)

You need to add an endpoint to save FCM tokens. Add this to `Backend/main.go`:

```go
// Store FCM tokens (in-memory or database)
var fcmTokens = make(map[string]string) // user_id -> fcm_token
var fcmTokensMutex sync.RWMutex

// Handler: POST /api/save-fcm-token
func saveFCMTokenHandler(w http.ResponseWriter, r *http.Request) {
    enableCORS(w)
    
    if r.Method != http.MethodPost {
        http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
        return
    }
    
    var data struct {
        FCMToken  string `json:"fcm_token"`
        UserID    string `json:"user_id"`
        UserType  string `json:"user_type"` // "admin" or "student"
    }
    
    if err := json.NewDecoder(r.Body).Decode(&data); err != nil {
        http.Error(w, "Invalid JSON", http.StatusBadRequest)
        return
    }
    
    // Store token (you can also save to database)
    key := fmt.Sprintf("%s_%s", data.UserType, data.UserID)
    fcmTokensMutex.Lock()
    fcmTokens[key] = data.FCMToken
    fcmTokensMutex.Unlock()
    
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(map[string]string{"status": "success"})
}

// Add to main() function:
// http.HandleFunc("/api/save-fcm-token", saveFCMTokenHandler)
```

### 2. Send Notifications from Backend

To send notifications, you'll need:
1. **Firebase Admin SDK for Go** or
2. **FCM HTTP v1 API** (recommended)

#### Option A: Using FCM HTTP v1 API (Recommended)

You'll need a service account key from Firebase Console:
1. Go to Firebase Console → Project Settings → Service Accounts
2. Generate a new private key
3. Use it to authenticate with FCM API

Example function to send notification:

```go
func sendFCMNotification(token string, title string, body string, data map[string]string) error {
    // Implementation using FCM HTTP v1 API
    // You'll need to use OAuth2 to authenticate
    // See: https://firebase.google.com/docs/cloud-messaging/send-message
}
```

#### Option B: Using Firebase Admin SDK

```bash
go get firebase.google.com/go/v4
```

### 3. Integration in Login Pages

Update your login pages to set user info after successful login:

**In `admin_dashboard_page.dart` (after login):**
```dart
// After successful admin login
await FCMService().setUserInfo(adminId, 'admin');
```

**In `student_dashboard_page.dart` (after login):**
```dart
// After successful student login
await FCMService().setUserInfo(studentId, 'student');
```

**On logout:**
```dart
await FCMService().clearUserInfo();
await FCMService().deleteToken();
```

### 4. Notification Use Cases

Consider implementing notifications for:
- ✅ **Attendance window started** → Notify all students
- ✅ **Attendance window ending soon** (5 min warning) → Notify students
- ✅ **Student submitted attendance** → Notify admin
- ✅ **Attendance window closed** → Notify students
- ✅ **New student joined group** → Notify admin

### 5. iOS APNs Configuration (Optional for now)

For iOS push notifications to work, you need to:
1. Upload APNs Authentication Key in Firebase Console
2. Or configure APNs Certificate

This can be done later - Android will work without it.

## 🧪 Testing

1. **Run the app:**
   ```bash
   cd Frontend
   flutter run
   ```

2. **Check logs for:**
   - `✅ Firebase initialized`
   - `✅ FCM initialized`
   - `📱 FCM Token: <token>`
   - `✅ FCM token saved to backend`

3. **Test notification:**
   - Use Firebase Console → Cloud Messaging → Send test message
   - Or send from your backend using FCM API

## 📝 Important Notes

1. **FCM Token**: Each device gets a unique token that needs to be saved to your backend
2. **Background Messages**: The background handler must be top-level (already done)
3. **Foreground Messages**: Handled by local notifications (already implemented)
4. **Token Refresh**: Automatically handled when token changes
5. **User Management**: Call `setUserInfo()` after login, `clearUserInfo()` on logout

## 🔧 Troubleshooting

- **No token received?** Check Firebase Console → Cloud Messaging → API is enabled
- **Notifications not showing?** Check notification permissions in device settings
- **Backend errors?** Ensure `/api/save-fcm-token` endpoint is implemented
- **iOS not working?** Upload APNs key in Firebase Console

## 📚 Resources

- [Firebase Cloud Messaging Docs](https://firebase.google.com/docs/cloud-messaging)
- [FCM HTTP v1 API](https://firebase.google.com/docs/cloud-messaging/send-message)
- [Flutter Firebase Messaging](https://firebase.flutter.dev/docs/messaging/overview)

