# 📢 Broadcast Message System - Complete Logic Flow

## 🏗️ Architecture Overview

The broadcast message system allows **admins** to send messages to:
- **All students** in the system
- **Specific group** of students

Students can **view** these messages but **cannot reply**.

---

## 📊 Database Schema

### 1. `broadcast_messages` Table
Stores the actual messages sent by admins:
```sql
- id (UUID) - Primary key
- admin_id (UUID) - Who sent it
- group_id (UUID, nullable) - Which group (NULL = all students)
- title (VARCHAR) - Message title
- message (TEXT) - Message content
- sent_to_all (BOOLEAN) - true = all students, false = group only
- created_at (TIMESTAMP) - When sent
```

### 2. `message_recipients` Table
Links messages to students (many-to-many relationship):
```sql
- id (UUID) - Primary key
- message_id (UUID) - Which message
- student_id (UUID) - Which student received it
- is_read (BOOLEAN) - Has student read it?
- read_at (TIMESTAMP) - When read
- UNIQUE(message_id, student_id) - Prevents duplicates
```

### 3. `fcm_tokens` Table
Stores device tokens for push notifications:
```sql
- id (UUID) - Primary key
- user_id (UUID) - Student or admin UUID
- user_type (VARCHAR) - 'student' or 'admin'
- fcm_token (TEXT) - Device token
- device_type (VARCHAR) - 'mobile', 'web', etc.
```

---

## 🔄 Complete Flow

### **PHASE 1: Admin Sends Message** (Frontend → Backend)

#### Step 1: Admin fills form (`BroadcastMessagePage`)
```dart
- Title: "Important Announcement"
- Message: "Class cancelled tomorrow"
- Recipients: "All Students" OR "Group: CS101"
```

#### Step 2: Frontend sends POST request
```dart
POST /api/send-broadcast-message
{
  "admin_id": "admin-uuid",
  "group_id": null,  // or "group-uuid"
  "title": "Important Announcement",
  "message": "Class cancelled tomorrow",
  "send_to_all": true  // or false
}
```

---

### **PHASE 2: Backend Processing** (`sendBroadcastMessageHandler`)

#### Step 1: Validate Input
```go
✅ Check: admin_id, title, message are not empty
```

#### Step 2: Determine Recipients
```go
IF send_to_all == true OR group_id == "":
    → Query: SELECT id, student_id FROM students
    → Get ALL students in system
    
ELSE:
    → Query: SELECT student_id, students(id, student_id) 
             FROM group_students 
             WHERE group_id = ?
    → Get students in SPECIFIC group
```

**Result:** List of `studentUUIDs` (database IDs) and `studentIDs` (like "ST001")

#### Step 3: Save Message to Database
```go
INSERT INTO broadcast_messages (
    admin_id, group_id, title, message, sent_to_all
) VALUES (...)
RETURNING id  // Get the message UUID
```

**Result:** `messageID` (UUID of the created message)

#### Step 4: Create Message Recipients
```go
FOR EACH studentUUID:
    INSERT INTO message_recipients (
        message_id, student_id, is_read
    ) VALUES (
        messageID, studentUUID, false
    )
```

**This creates a record for EACH student** who should receive the message.

#### Step 5: Send FCM Push Notifications (Optional)
```go
1. Check in-memory cache for FCM tokens
2. Query database for missing tokens:
   SELECT fcm_token FROM fcm_tokens 
   WHERE user_type = 'student' 
   AND user_id IN (studentUUIDs...)
3. Send notification to each token
```

**Note:** Currently FCM sending is a placeholder - needs Firebase Admin SDK implementation.

#### Step 6: Return Success Response
```json
{
  "success": true,
  "message": "Broadcast message sent",
  "sent_count": 25,
  "total_students": 25,
  "recipients_created": 25,
  "message_id": "message-uuid"
}
```

---

### **PHASE 3: Student Views Messages** (Frontend → Backend)

#### Step 1: Student opens Messages page
```dart
StudentMessagesPage(studentId: "ST001")
```

#### Step 2: Frontend fetches messages
```dart
GET /api/get-messages?student_id=ST001
```

#### Step 3: Backend processes request (`getMessagesHandler`)

**Step 3a: Convert student_id to UUID**
```go
studentID = "ST001"
studentUUID = getStudentUUIDByID("ST001")
// Returns: "student-uuid-from-database"
```

**Step 3b: Get message recipients for this student**
```go
SELECT message_id, is_read 
FROM message_recipients 
WHERE student_id = studentUUID
```

**Result:** List of `{message_id, is_read}` records

**Step 3c: Get actual message details**
```go
SELECT id, title, message, created_at, admin_id, admins(username)
FROM broadcast_messages
WHERE id IN (message_id1, message_id2, ...)
ORDER BY created_at DESC
```

**Step 3d: Combine data**
```go
FOR EACH message:
    message['is_read'] = readStatus[message.id]
    message['admin_name'] = admin.username
```

#### Step 4: Return messages to frontend
```json
{
  "messages": [
    {
      "id": "msg-uuid",
      "title": "Important Announcement",
      "message": "Class cancelled tomorrow",
      "is_read": false,
      "created_at": "2024-01-15T10:30:00Z",
      "admin_name": "Dr. Smith"
    }
  ],
  "count": 1
}
```

#### Step 5: Frontend displays messages
- Shows list of messages
- Unread messages have blue background
- Clicking a message marks it as read

---

### **PHASE 4: Mark Message as Read**

#### Step 1: Student clicks on message
```dart
_markAsRead(messageId)
```

#### Step 2: Frontend sends request
```dart
POST /api/mark-message-read
{
  "student_id": "ST001",
  "message_id": "msg-uuid"
}
```

#### Step 3: Backend updates database
```go
UPDATE message_recipients
SET is_read = true, read_at = NOW()
WHERE student_id = studentUUID 
  AND message_id = messageID
```

---

## 🔑 Key Concepts

### 1. **Two ID Systems**
- **student_id**: Human-readable (e.g., "ST001") - used in frontend
- **student UUID**: Database primary key (e.g., "d2c59234-...") - used in database

The backend converts between them using `getStudentUUIDByID()`.

### 2. **Many-to-Many Relationship**
- One message → Many students (via `message_recipients`)
- One student → Many messages (via `message_recipients`)

### 3. **Read Status Tracking**
- Each student has their own `is_read` flag per message
- Stored in `message_recipients` table
- Allows per-student read tracking

### 4. **FCM Token Caching**
- Tokens stored in-memory cache for fast access
- Falls back to database if not in cache
- Allows push notifications (when implemented)

---

## 🐛 Debugging Tips

### Check if message was created:
```sql
SELECT * FROM broadcast_messages ORDER BY created_at DESC LIMIT 5;
```

### Check if recipients were created:
```sql
SELECT COUNT(*) FROM message_recipients 
WHERE message_id = 'your-message-id';
```

### Check if student can see messages:
```sql
SELECT mr.*, bm.title 
FROM message_recipients mr
JOIN broadcast_messages bm ON mr.message_id = bm.id
WHERE mr.student_id = 'student-uuid';
```

### Check student UUID mapping:
```sql
SELECT id, student_id FROM students WHERE student_id = 'ST001';
```

---

## 📝 API Endpoints Summary

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/send-broadcast-message` | POST | Admin sends message |
| `/api/get-messages?student_id=ST001` | GET | Student fetches messages |
| `/api/mark-message-read` | POST | Student marks message as read |
| `/api/save-fcm-token` | POST | Save device token for push notifications |

---

## 🚀 Future Enhancements

1. **FCM Implementation**: Complete Firebase Admin SDK integration
2. **Message Filtering**: Filter by read/unread, date range
3. **Message Search**: Search messages by title/content
4. **Rich Media**: Support images, links in messages
5. **Message Templates**: Pre-defined message templates for admins

