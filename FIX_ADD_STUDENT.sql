-- Fix Add Student Feature
-- Run this in Supabase SQL Editor

-- 1. Disable RLS (Row Level Security) for students table
-- This allows the backend to insert students
ALTER TABLE students DISABLE ROW LEVEL SECURITY;

-- 2. Verify RLS is disabled
SELECT 
    tablename,
    rowsecurity as rls_enabled
FROM pg_tables 
WHERE schemaname = 'public' 
AND tablename = 'students';
-- Should show: rls_enabled = false

-- 3. Test insert to verify permissions work
INSERT INTO students (student_id, student_name) 
VALUES ('TEST001', 'Test Student')
ON CONFLICT (student_id) DO NOTHING;

-- 4. Verify test insert worked
SELECT * FROM students WHERE student_id = 'TEST001';

-- 5. Clean up test (optional)
-- DELETE FROM students WHERE student_id = 'TEST001';

-- That's it! Now try adding a student from the app again.

