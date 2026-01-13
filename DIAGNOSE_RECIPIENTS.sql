-- Complete Diagnostic for Message Recipients Issue

-- 1. Check if ANY messages exist
SELECT 
    COUNT(*) as message_count,
    MAX(created_at) as latest_message_time
FROM broadcast_messages;

-- 2. Show all messages
SELECT 
    id, 
    title, 
    admin_id, 
    sent_to_all,
    created_at 
FROM broadcast_messages 
ORDER BY created_at DESC 
LIMIT 5;

-- 3. Check recipients count
SELECT COUNT(*) as recipient_count FROM message_recipients;

-- 4. Check if there's a message without recipients
SELECT 
    bm.id as message_id,
    bm.title,
    bm.created_at,
    COUNT(mr.id) as recipient_count
FROM broadcast_messages bm
LEFT JOIN message_recipients mr ON bm.id = mr.message_id
GROUP BY bm.id, bm.title, bm.created_at
ORDER BY bm.created_at DESC;

-- 5. Verify admin exists (for foreign key)
SELECT id, username FROM admins LIMIT 1;

-- 6. Verify students exist
SELECT COUNT(*) as student_count FROM students;

-- 7. Check table structure
SELECT 
    column_name, 
    data_type, 
    is_nullable
FROM information_schema.columns 
WHERE table_name = 'message_recipients'
ORDER BY ordinal_position;

-- 8. Try manual insert test (replace with actual IDs from query 2)
-- First get a message ID and student UUID:
SELECT 
    bm.id as message_id,
    s.id as student_uuid,
    s.student_id
FROM broadcast_messages bm
CROSS JOIN students s
WHERE s.student_id = 'ST001'
ORDER BY bm.created_at DESC
LIMIT 1;

-- Then try manual insert (uncomment and use IDs from above):
-- INSERT INTO message_recipients (message_id, student_id)
-- VALUES ('<message_id_from_above>', '<student_uuid_from_above>');

