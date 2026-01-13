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

-- 5. Enable Row Level Security (optional, for Supabase)
-- ALTER TABLE fcm_tokens ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE broadcast_messages ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE message_recipients ENABLE ROW LEVEL SECURITY;

