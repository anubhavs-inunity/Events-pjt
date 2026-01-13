# 🚀 Add Broadcast Messages Schema to Supabase

## ⚠️ IMPORTANT: You MUST add these tables for broadcast messages to work!

---

## 📋 Step-by-Step Instructions

### Step 1: Open Supabase Dashboard
1. Go to https://supabase.com/dashboard
2. Select your project
3. Click **"SQL Editor"** in the left sidebar
4. Click **"New query"** button

### Step 2: Copy the SQL Schema
1. Open the file: `Backend/SCHEMA_MESSAGES.sql` in your project
2. Copy **ALL** the SQL code (lines 1-53)

### Step 3: Paste and Run in Supabase
1. Paste the SQL into the Supabase SQL Editor
2. Click **"Run"** button (or press `Ctrl+Enter`)
3. Wait for **"Success"** message ✅

### Step 4: Verify Tables Created
Run this query in SQL Editor to verify:
```sql
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
AND table_name IN ('fcm_tokens', 'broadcast_messages', 'message_recipients');
```

You should see **3 rows**:
- `fcm_tokens`
- `broadcast_messages`
- `message_recipients`

---

## 📊 What Each Table Does

### 1. `fcm_tokens`
- Stores device tokens for push notifications
- Links tokens to users (students/admins)
- One token per user per device

### 2. `broadcast_messages`
- Stores the actual messages sent by admins
- Contains: title, message, admin_id, group_id, etc.
- One record per message

### 3. `message_recipients`
- Links messages to students (many-to-many)
- Tracks read/unread status per student
- One record per student per message

---

## ✅ After Adding Schema

1. **Restart your backend server:**
   ```bash
   cd Backend
   # Stop current server (Ctrl+C)
   go run .
   ```

2. **Test sending a message:**
   - Login as admin
   - Go to "Broadcast Message"
   - Send a test message
   - Check backend logs for: `DEBUG: Created X recipients`

3. **Test viewing messages:**
   - Login as student
   - Click messages icon
   - Should see the message you sent

---

## 🐛 Troubleshooting

### Error: "relation does not exist"
- Make sure you ran the SQL schema in Supabase
- Check that tables exist using the verification query above

### Error: "foreign key constraint"
- Make sure `admins` and `students` tables exist first
- These should already be there from your initial setup

### Messages not showing
- Check backend logs for errors
- Verify `message_recipients` table has data:
  ```sql
  SELECT COUNT(*) FROM message_recipients;
  ```

---

## 📝 Quick Copy-Paste SQL

If you want to copy directly, here's the full schema:

```sql
-- Broadcast Messages System Database Schema
-- Run this in Supabase SQL Editor

-- 1. Create fcm_tokens table to store device tokens
CREATE TABLE IF NOT EXISTS fcm_tokens (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL, -- References admins(id) or students(id)
  user_type VARCHAR(20) NOT NULL, -- 'admin' or 'student'
  fcm_token TEXT NOT NULL,
  device_type VARCHAR(50) DEFAULT 'mobile',
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(user_id, fcm_token) -- One token per user per device
);

-- 2. Create broadcast_messages table
CREATE TABLE IF NOT EXISTS broadcast_messages (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  admin_id UUID NOT NULL REFERENCES admins(id) ON DELETE CASCADE,
  group_id UUID REFERENCES groups(id) ON DELETE CASCADE, -- NULL = all students
  title VARCHAR(255) NOT NULL,
  message TEXT NOT NULL,
  sent_to_all BOOLEAN DEFAULT false, -- true = all students, false = group only
  created_at TIMESTAMP DEFAULT NOW()
);

-- 3. Create message_recipients table (many-to-many)
CREATE TABLE IF NOT EXISTS message_recipients (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  message_id UUID NOT NULL REFERENCES broadcast_messages(id) ON DELETE CASCADE,
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  is_read BOOLEAN DEFAULT false,
  read_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(message_id, student_id) -- Prevent duplicate entries
);

-- 4. Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_fcm_tokens_user_id ON fcm_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_fcm_tokens_user_type ON fcm_tokens(user_type);
CREATE INDEX IF NOT EXISTS idx_broadcast_messages_admin_id ON broadcast_messages(admin_id);
CREATE INDEX IF NOT EXISTS idx_broadcast_messages_group_id ON broadcast_messages(group_id);
CREATE INDEX IF NOT EXISTS idx_broadcast_messages_created_at ON broadcast_messages(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_message_recipients_message_id ON message_recipients(message_id);
CREATE INDEX IF NOT EXISTS idx_message_recipients_student_id ON message_recipients(student_id);
CREATE INDEX IF NOT EXISTS idx_message_recipients_is_read ON message_recipients(is_read);
```

---

## ✨ That's It!

Once you've added these tables, the broadcast messaging system will work! 🎉

