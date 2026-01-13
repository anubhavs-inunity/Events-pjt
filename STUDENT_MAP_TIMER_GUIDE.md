# Student Map & Timer - How It Works

## ✅ Backend State Persistence

**Important:** The backend state is stored in **global variables** on the server, which means:

- ✅ **Logging out of admin does NOT clear the state**
- ✅ **Admin location and timer persist even after admin logs out**
- ✅ **Students can see location and timer even if admin is logged out**

## ⚠️ When State is Lost

The backend state is **only lost** when:
- ❌ Backend server is restarted
- ❌ Backend server crashes
- ❌ Server is shut down

## 📋 Required Flow

For students to see the map and timer:

1. **Admin must be logged in** and:
   - Record location (click "RECORD MY LOCATION")
   - Start attendance window (click "START 10-MIN WINDOW")

2. **After admin does this:**
   - State is saved on backend server
   - Admin can log out
   - Students will still see:
     - ✅ Map with admin location
     - ✅ Synchronized timer

## 🔍 Troubleshooting

### Student sees "Waiting for admin to set location..."

**Possible causes:**
1. Admin never recorded location
2. Backend server was restarted (state lost)
3. Backend server is not running

**Solution:**
- Admin needs to log in and record location
- Make sure backend server is running

### Student sees map but no timer

**Possible causes:**
1. Admin recorded location but didn't start window
2. Window timer expired (10 minutes passed)

**Solution:**
- Admin needs to click "START 10-MIN WINDOW"
- Timer will appear on student dashboard

### Map and timer not updating

**Possible causes:**
1. Backend server stopped
2. Network connection issue
3. API URL incorrect in Flutter app

**Solution:**
- Check backend is running: `curl http://localhost:8080/api/get-window-status`
- Verify API URL in `Frontend/lib/config/api_config.dart`
- Check network connection

## 🧪 Testing Steps

1. **Start backend:**
   ```bash
   cd Backend
   ./server
   ```

2. **Admin side:**
   - Login as admin
   - Record location → Map appears
   - Start window → Timer starts
   - **Logout** (state persists!)

3. **Student side:**
   - Login as student
   - Should see:
     - ✅ Map with admin location
     - ✅ Timer counting down (if window is active)

4. **Verify backend state:**
   ```bash
   # Check admin location
   curl http://localhost:8080/api/get-admin-location
   
   # Check window status
   curl http://localhost:8080/api/get-window-status
   ```

## 📝 Notes

- Backend state is **in-memory** (not saved to database)
- If you restart backend, admin needs to set location again
- Multiple students can see the same map and timer simultaneously
- Timer is synchronized across all student devices

