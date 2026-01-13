# 🧪 Test Broadcast Messages - Step by Step

## ✅ Prerequisites
- ✅ Database tables added to Supabase
- ✅ Backend server running
- ✅ Frontend app running

---

## 📝 Test Steps

### **Test 1: Send a Broadcast Message (Admin)**

1. **Login as Admin**
   - Open your Flutter app
   - Login with admin credentials

2. **Navigate to Broadcast Message**
   - Click sidebar menu
   - Click "Broadcast Message"

3. **Send a Test Message**
   - **Title:** "Test Message"
   - **Message:** "This is a test broadcast message"
   - **Recipients:** Select "Send to All Students" ✅
   - Click **"Send Broadcast Message"**

4. **Check Backend Logs**
   You should see in backend console:
   ```
   DEBUG: Creating recipients for message <uuid>, X students
   DEBUG: Created X recipients for message <uuid>
   ```

5. **Expected Result:**
   - ✅ Green success message: "Message sent to X students"
   - ✅ Form clears
   - ✅ Returns to admin dashboard

---

### **Test 2: View Messages (Student)**

1. **Login as Student**
   - Logout from admin (if logged in)
   - Login with student credentials (e.g., ST001)

2. **Open Messages**
   - Click the **📬 Messages icon** in the app bar (top right)

3. **Check Messages Page**
   - Should see your test message
   - Message should have:
     - ✅ Title: "Test Message"
     - ✅ Blue background (unread)
     - ✅ Blue dot indicator (unread)
     - ✅ "From: Admin" or admin name
     - ✅ Timestamp

4. **Check Frontend Console**
   You should see:
   ```
   🔍 Fetching messages for student: ST001
   📥 Response status: 200
   ✅ Messages count: 1
   ```

5. **Click on Message**
   - Click the message card
   - Should open full message dialog
   - Message should be marked as read (white background)

---

### **Test 3: Send to Specific Group**

1. **Create a Group (if not exists)**
   - Login as admin
   - Create a group with some students

2. **Send Group Message**
   - Go to "Broadcast Message"
   - **Title:** "Group Test"
   - **Message:** "This is for group members only"
   - **Recipients:** Uncheck "Send to All"
   - **Select Group:** Choose your group from dropdown
   - Click **"Send Broadcast Message"**

3. **Test as Group Member**
   - Login as student who is in the group
   - Open messages
   - Should see the group message

4. **Test as Non-Group Member**
   - Login as student NOT in the group
   - Open messages
   - Should NOT see the group message

---

## 🐛 Troubleshooting

### ❌ "Message sent but students don't see it"

**Check 1: Backend Logs**
```bash
# Look for these lines:
DEBUG: getMessagesHandler - studentID: ST001, studentUUID: <uuid>
DEBUG: Found X recipients for student <uuid>
DEBUG: Found X message IDs: [...]
DEBUG: Retrieved X broadcast messages
```

**Check 2: Database Query**
Run in Supabase SQL Editor:
```sql
-- Check if message was created
SELECT * FROM broadcast_messages ORDER BY created_at DESC LIMIT 1;

-- Check if recipients were created
SELECT COUNT(*) FROM message_recipients 
WHERE message_id = '<message_id_from_above>';

-- Check if student can see it
SELECT mr.*, bm.title 
FROM message_recipients mr
JOIN broadcast_messages bm ON mr.message_id = bm.id
WHERE mr.student_id = (
  SELECT id FROM students WHERE student_id = 'ST001'
);
```

**Check 3: Student UUID Mapping**
```sql
-- Verify student ID to UUID mapping
SELECT id, student_id FROM students WHERE student_id = 'ST001';
```

---

### ❌ "Error: Student not found"

**Problem:** Student ID doesn't exist in database

**Solution:**
```sql
-- Check if student exists
SELECT * FROM students WHERE student_id = 'ST001';

-- If not, add student:
INSERT INTO students (student_id, student_name) 
VALUES ('ST001', 'Test Student');
```

---

### ❌ "Empty response" or "No messages"

**Check 1: Recipients Created?**
```sql
SELECT COUNT(*) FROM message_recipients;
-- Should be > 0
```

**Check 2: Message Exists?**
```sql
SELECT * FROM broadcast_messages ORDER BY created_at DESC;
-- Should show your messages
```

**Check 3: Student UUID Correct?**
- Verify the student_id used in frontend matches database
- Check backend logs for UUID conversion

---

### ❌ "Dropdown error" (already fixed)

If you see dropdown assertion error:
- ✅ Already fixed in `broadcast_message_page.dart`
- Hot restart the app (not just hot reload)

---

## ✅ Success Checklist

After testing, you should have:

- [ ] ✅ Sent message to all students
- [ ] ✅ Sent message to specific group
- [ ] ✅ Students can see messages
- [ ] ✅ Messages show correct read/unread status
- [ ] ✅ Clicking message marks it as read
- [ ] ✅ Backend logs show debug info
- [ ] ✅ No errors in console

---

## 🚀 Next Steps

Once everything works:

1. **Test FCM Push Notifications** (optional)
   - Currently placeholder
   - Need Firebase Admin SDK integration

2. **Add More Features** (optional)
   - Message search
   - Filter by read/unread
   - Message templates

---

## 📞 Need Help?

If something doesn't work:
1. Check backend logs
2. Check frontend console
3. Check database tables
4. Share the error messages/logs

