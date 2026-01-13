-- Multi-Group System Database Schema
-- Run this in Supabase SQL Editor

-- 1. Create groups table (sessions/events)
CREATE TABLE IF NOT EXISTS groups (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  admin_id UUID NOT NULL REFERENCES admins(id) ON DELETE CASCADE,
  location_lat FLOAT,
  location_lon FLOAT,
  threshold_meters FLOAT DEFAULT 100.0,
  status VARCHAR(50) DEFAULT 'inactive', -- 'active', 'closed', 'inactive'
  window_start_time TIMESTAMP,
  window_end_time TIMESTAMP,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- 2. Create group_students junction table (many-to-many)
CREATE TABLE IF NOT EXISTS group_students (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  group_id UUID NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  joined_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(group_id, student_id) -- Prevent duplicate entries
);

-- 3. Create group_attendance table (persistent attendance records)
CREATE TABLE IF NOT EXISTS group_attendance (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  group_id UUID NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  status VARCHAR(50) NOT NULL, -- 'Present', 'Absent'
  distance FLOAT,
  latitude FLOAT,
  longitude FLOAT,
  submitted_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(group_id, student_id) -- One attendance record per student per group
);

-- 4. Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_groups_admin_id ON groups(admin_id);
CREATE INDEX IF NOT EXISTS idx_groups_status ON groups(status);
CREATE INDEX IF NOT EXISTS idx_group_students_group_id ON group_students(group_id);
CREATE INDEX IF NOT EXISTS idx_group_students_student_id ON group_students(student_id);
CREATE INDEX IF NOT EXISTS idx_group_attendance_group_id ON group_attendance(group_id);
CREATE INDEX IF NOT EXISTS idx_group_attendance_student_id ON group_attendance(student_id);

-- 5. Disable RLS for development (enable policies for production)
ALTER TABLE groups DISABLE ROW LEVEL SECURITY;
ALTER TABLE group_students DISABLE ROW LEVEL SECURITY;
ALTER TABLE group_attendance DISABLE ROW LEVEL SECURITY;

-- 6. Create function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- 7. Create trigger for groups table
CREATE TRIGGER update_groups_updated_at BEFORE UPDATE ON groups
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

