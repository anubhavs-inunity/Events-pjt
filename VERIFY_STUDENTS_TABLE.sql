-- Verify Students Table Setup
-- Run this in Supabase SQL Editor

-- 1. Check if students table exists
SELECT 
    table_name,
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns 
WHERE table_name = 'students'
ORDER BY ordinal_position;

-- 2. Check current students count
SELECT COUNT(*) as total_students FROM students;

-- 3. Check if RLS is enabled (should be disabled for development)
SELECT 
    tablename,
    rowsecurity as rls_enabled
FROM pg_tables 
WHERE schemaname = 'public' 
AND tablename = 'students';

-- 4. If RLS is enabled, disable it (for development)
-- Uncomment the line below if RLS is enabled:
-- ALTER TABLE students DISABLE ROW LEVEL SECURITY;

-- 5. Test insert (optional - to verify permissions)
-- Uncomment to test:
-- INSERT INTO students (student_id, student_name) 
-- VALUES ('TEST001', 'Test Student')
-- ON CONFLICT (student_id) DO NOTHING;

-- 6. Verify the test insert worked
-- SELECT * FROM students WHERE student_id = 'TEST001';

-- 7. Clean up test (optional)
-- DELETE FROM students WHERE student_id = 'TEST001';

