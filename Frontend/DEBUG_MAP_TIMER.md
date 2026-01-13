# Debugging Map & Timer Issues

## Quick Checklist

### 1. Check Backend is Running
```bash
cd Backend
./server
# Should see: "Server running on :8080"
```

### 2. Check API URL in Flutter App

**Important:** If testing on a **physical device** or **Android emulator**, `localhost:8080` won't work!

**Edit:** `Frontend/lib/config/api_config.dart`

**For Android Emulator:**
```dart
static const String baseUrl = 'http://10.0.2.2:8080';
```

**For Physical Device (same WiFi):**
```dart
// Replace with your computer's IP address
static const String baseUrl = 'http://192.168.1.XXX:8080';
```

**To find your IP:**
```bash
# Linux/Mac
ip addr show | grep "inet " | grep -v 127.0.0.1
# or
hostname -I
```

### 3. Test Backend Endpoints Manually

```bash
# Test admin location endpoint
curl http://localhost:8080/api/get-admin-location

# Test window status endpoint
curl http://localhost:8080/api/get-window-status
```

**Expected responses:**

**If admin location is set:**
```json
{
  "lat": 12.858163,
  "lon": 74.933862,
  "session_name": "Workshop_Day2",
  "threshold": 100,
  "window_active": true
}
```

**If admin location NOT set:**
```json
{
  "error": "Admin location not set"
}
```

### 4. Admin Must Do This First

1. **Login as admin**
2. **Record location** (click "RECORD MY LOCATION")
3. **Start window** (click "START 10-MIN WINDOW")

### 5. Check Student Dashboard

1. **Login as student**
2. **Look for:**
   - Refresh button (top right) - click it to manually refresh
   - Error messages (red card) - shows connection issues
   - Map should appear if admin location is set
   - Timer should appear if window is active

### 6. Common Issues

**Issue: "Connection error"**
- Backend not running
- Wrong API URL
- Firewall blocking port 8080

**Issue: "Admin location not set"**
- Admin didn't record location
- Backend was restarted (state lost)

**Issue: Map not showing**
- Check browser console for errors
- Verify `flutter_map` package is installed
- Check internet connection (needed for map tiles)

**Issue: Timer not showing**
- Admin didn't start window
- Window expired (10 minutes passed)
- Backend was restarted

### 7. Debug Steps

1. **Check Flutter console** for error messages
2. **Click refresh button** on student dashboard
3. **Check backend logs** for incoming requests
4. **Test endpoints** with curl commands above

