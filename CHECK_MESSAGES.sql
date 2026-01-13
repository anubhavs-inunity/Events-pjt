-- Quick diagnostic queries for broadcast messages

-- 1. Check if any messages exist
SELECT 
    id, 
    title, 
    admin_id, 
    sent_to_all,
    created_at 
FROM broadcast_messages 
ORDER BY created_at DESC 
LIMIT 5;

-- 2. Check if any recipients exist
SELECT 
    COUNT(*) as total_recipients,
    COUNT(DISTINCT message_id) as unique_messages,
    COUNT(DISTINCT student_id) as unique_students
FROM message_recipients;

-- 3. Check specific message and its recipients
SELECT 
    bm.id as message_id,
    bm.title,
    bm.created_at as message_created,
    COUNT(mr.id) as recipient_count
FROM broadcast_messages bm
LEFT JOIN message_recipients mr ON bm.id = mr.message_id
GROUP BY bm.id, bm.title, bm.created_at
ORDER BY bm.created_at DESC
LIMIT 5;

-- 4. Check if student ST001 has any messages
SELECT 
    mr.*,
    bm.title,
    bm.message,
    bm.created_at
FROM message_recipients mr
JOIN broadcast_messages bm ON mr.message_id = bm.id
WHERE mr.student_id = (
    SELECT id FROM students WHERE student_id = 'ST001'
)
ORDER BY bm.created_at DESC;

-- 5. Verify student UUID for ST001
SELECT id, student_id, student_name 
FROM students 
WHERE student_id = 'ST001';

