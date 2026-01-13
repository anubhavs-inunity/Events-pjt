# 📢 Broadcast Messaging System - Setup Guide

## ✅ What's Implemented

### Backend
- ✅ Database schema for FCM tokens and messages
- ✅ Endpoint: `POST /api/save-fcm-token` - Save FCM tokens
- ✅ Endpoint: `POST /api/send-broadcast-message` - Send broadcast messages
- ✅ Endpoint: `GET /api/get-messages?student_id=XXX` - Get messages for student
- ✅ Endpoint: `POST /api/mark-message-read` - Mark message as read
- ✅ Message storage in database
- ⚠️ FCM push notification sending (needs implementation - see FCM_SENDING_GUIDE.md)

### Frontend
- ✅ Admin UI: Broadcast Message page
- ✅ Student UI: Messages page
- ✅ Integration in admin sidebar
- ✅ Messages icon in student dashboard
- ✅ Auto-refresh for students (every 10 seconds)

## 📋 Setup Steps

### Step 1: Run Database Schema

1. Go to Supabase SQL Editor
2. Run the SQL from `Backend/SCHEMA_MESSAGES.sql`
3. This creates:
   - `fcm_tokens` table
   - `broadcast_messages` table
   - `message_recipients` table

### Step 2: Start Backend

```bash
cd Backend
./server
```

The new endpoints will be available:
- `POST /api/save-fcm-token`
- `POST /api/send-broadcast-message`
- `GET /api/get-messages`
- `POST /api/mark-message-read`

### Step 3: Test the System

#### Admin Side:
1. Login as admin
2. Open sidebar → Click "Broadcast Message"
3. Select recipients (All Students or specific group)
4. Enter title and message
5. Click "Send Broadcast Message"

#### Student Side:
1. Login as student
2. Click messages icon (📬) in top bar
3. View received messages
4. Tap message to read full content

## 🎯 How It Works

### Admin Sends Message:
1. Admin opens Broadcast Message page
2. Selects recipients (all students or group)
3. Enters title and message
4. Clicks send
5. Backend:
   - Saves message to database
   - Creates recipient records for all students
   - Sends FCM push notifications (when implemented)
   - Returns success

### Student Receives Message:
1. **Via Push Notification** (when FCM sending is implemented):
   - Student receives push notification
   - Taps notification → Opens messages page
   - Message is marked as read

2. **Via App** (current):
   - Student opens messages page
   - Messages are fetched from database
   - Unread messages show blue dot
   - Auto-refreshes every 10 seconds

## 📱 Features

### Admin Features:
- ✅ Send to all students
- ✅ Send to specific group
- ✅ Title and message fields
- ✅ See sent count
- ✅ Messages stored in database

### Student Features:
- ✅ View all messages
- ✅ Unread indicator (blue dot)
- ✅ Read/unread status
- ✅ Message details (title, body, sender, timestamp)
- ✅ Auto-refresh
- ✅ Pull to refresh
- ✅ Tap to read full message

## ⚠️ Current Limitations

1. **FCM Push Notifications**: 
   - Messages are stored and visible in UI
   - Push notifications need implementation (see FCM_SENDING_GUIDE.md)
   - Students need to open app to see messages (until FCM is implemented)

2. **No Reply Feature**:
   - Students can only view messages (as requested)
   - No reply functionality

## 🚀 Next Steps

1. **Implement FCM Sending** (see FCM_SENDING_GUIDE.md):
   - Get Firebase Service Account Key
   - Install Firebase Admin SDK
   - Update `sendFCMNotification()` function
   - Test push notifications

2. **Optional Enhancements**:
   - Unread message count badge
   - Message categories/types
   - Message search
   - Message deletion

## 🧪 Testing Checklist

- [ ] Database schema created
- [ ] Backend endpoints working
- [ ] Admin can send broadcast message
- [ ] Message appears in database
- [ ] Student can view messages
- [ ] Unread indicator works
- [ ] Mark as read works
- [ ] Auto-refresh works
- [ ] FCM push notifications (after implementation)

## 📝 API Endpoints

### Save FCM Token
```
POST /api/save-fcm-token
Body: {
  "fcm_token": "token",
  "user_id": "user_id",
  "user_type": "admin" | "student"
}
```

### Send Broadcast Message
```
POST /api/send-broadcast-message
Body: {
  "admin_id": "admin_id",
  "group_id": "group_id" (optional),
  "title": "Title",
  "message": "Message",
  "send_to_all": true/false
}
```

### Get Messages (Student)
```
GET /api/get-messages?student_id=STUDENT_ID
Response: {
  "messages": [...],
  "count": 5
}
```

### Mark Message Read
```
POST /api/mark-message-read
Body: {
  "student_id": "student_id",
  "message_id": "message_id"
}
```

---

**The system is ready to use!** Messages are stored and visible. Implement FCM sending to enable push notifications. 🎉

