# Database Setup Instructions

## Problem
The error "Could not find the table 'public.groups' in the schema cache" means the database tables haven't been created yet.

## Solution

### Step 1: Open Supabase SQL Editor
1. Go to your Supabase project dashboard
2. Click on "SQL Editor" in the left sidebar
3. Click "New query"

### Step 2: Run the Schema
1. Open the file `Backend/SCHEMA_GROUPS.sql` in this project
2. Copy ALL the SQL code from that file
3. Paste it into the Supabase SQL Editor
4. Click "Run" (or press Ctrl+Enter)

### Step 3: Verify Tables Created
Run this query to verify the tables exist:
```sql
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
AND table_name IN ('groups', 'group_students', 'group_attendance');
```

You should see all three tables listed.

### Step 4: Test the Application
After running the schema:
1. Restart your backend server (if needed)
2. Try creating a group again from the admin dashboard
3. The error should be gone!

## Notes
- The schema uses `CREATE TABLE IF NOT EXISTS` so it's safe to run multiple times
- RLS (Row Level Security) is disabled for development - enable it for production
- All tables have proper indexes for performance

