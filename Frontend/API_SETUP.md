# Flutter App - API Configuration Guide

## ✅ What's Done:
- ✅ Admin login page now calls `/api/admin-login` endpoint
- ✅ Student login page now calls `/api/student-login` endpoint
- ✅ Both pages show loading indicators during API calls
- ✅ Error handling for network issues

## 🔧 Configuration Required:

### Step 1: Update API Base URL

Open `lib/config/api_config.dart` and update the `baseUrl`:

**For Android Emulator:**
```dart
static const String baseUrl = 'http://10.0.2.2:8080';
```

**For Physical Device (Same Network):**
```dart
// Replace YOUR_COMPUTER_IP with your actual IP address
// Find your IP: 
//   Linux/Mac: ifconfig or ip addr
//   Windows: ipconfig
static const String baseUrl = 'http://192.168.1.XXX:8080';
```

**For Local Testing (Web/Desktop):**
```dart
static const String baseUrl = 'http://localhost:8080';
```

### Step 2: Find Your Computer's IP Address

**Linux/Mac:**
```bash
# Option 1
ip addr show | grep "inet " | grep -v 127.0.0.1

# Option 2
hostname -I

# Option 3
ifconfig | grep "inet " | grep -v 127.0.0.1
```

**Windows:**
```cmd
ipconfig
# Look for "IPv4 Address" under your network adapter
```

### Step 3: Make Sure Backend Server is Running

```bash
cd Backend
./server
# or
go run .
```

### Step 4: Test the Connection

1. **Test from your computer:**
   ```bash
   curl http://localhost:8080/api/admin-login \
     -X POST \
     -d "username=admin" \
     -d "password=admin123"
   ```

2. **Test from your phone/device (same network):**
   - Make sure your phone is on the same WiFi network
   - Use your computer's IP address in the app

## 📱 Testing on Physical Device

1. **Update `api_config.dart`** with your computer's IP
2. **Make sure backend is running** on your computer
3. **Connect phone to same WiFi** as your computer
4. **Build and run the app:**
   ```bash
   cd Frontend
   flutter run
   ```

## 🔍 Troubleshooting

### "Connection error" message:
- ✅ Check backend server is running
- ✅ Verify IP address is correct
- ✅ Make sure phone and computer are on same network
- ✅ Check firewall isn't blocking port 8080

### "Invalid credentials":
- ✅ Verify admin exists in Supabase: `username=admin, password=admin123`
- ✅ Verify students exist in Supabase
- ✅ Check backend logs for errors

### Can't connect from device:
- ✅ Try `10.0.2.2:8080` for Android emulator
- ✅ For physical device, use your computer's actual IP (not localhost)
- ✅ Make sure backend CORS is enabled (it is by default)

## 🎯 Quick Test

After updating the API URL, test with:
- **Admin:** username=`admin`, password=`admin123`
- **Student:** ID=`ST001`, Name=`Anil Kumar`

