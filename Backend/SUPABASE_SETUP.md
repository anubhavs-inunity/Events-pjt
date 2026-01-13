# Supabase Setup Guide

## Step 1: Create Tables in Supabase

Go to your Supabase Dashboard → SQL Editor and run these commands:

### Create `admins` table:
```sql
CREATE TABLE admins (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  username VARCHAR(255) UNIQUE NOT NULL,
  password VARCHAR(255) NOT NULL,
  created_at TIMESTAMP DEFAULT NOW()
);
```

### Create `students` table:
```sql
CREATE TABLE students (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  student_id VARCHAR(50) UNIQUE NOT NULL,
  student_name VARCHAR(255) NOT NULL,
  created_at TIMESTAMP DEFAULT NOW()
);
```

## Step 2: Insert Initial Data

### Insert Admin Credentials:
```sql
INSERT INTO admins (username, password) 
VALUES ('admin', 'admin123');
```

### Insert Mock Students:
```sql
INSERT INTO students (student_id, student_name) VALUES
('ST001', 'Anil Kumar'),
('ST002', 'Priya Singh'),
('ST003', 'Rahul Sharma');
```

## Step 3: Configure Environment Variables

1. Copy `.env.example` to `.env`:
   ```bash
   cp .env.example .env
   ```

2. Edit `.env` and add your Supabase credentials:
   ```
   SUPABASE_URL=https://your-project-id.supabase.co
   SUPABASE_ANON_KEY=your-anon-key-here
   ```

3. Find these values in your Supabase Dashboard:
   - **SUPABASE_URL**: Settings → API → Project URL
   - **SUPABASE_ANON_KEY**: Settings → API → Project API keys → `anon` `public`

## Step 4: Enable Row Level Security (Optional but Recommended)

For production, you should enable RLS policies. For development/testing, you can disable RLS:

```sql
-- Disable RLS for admins table (development only)
ALTER TABLE admins DISABLE ROW LEVEL SECURITY;

-- Disable RLS for students table (development only)
ALTER TABLE students DISABLE ROW LEVEL SECURITY;
```

## Step 5: Test the Backend

1. Start the server:
   ```bash
   go run .
   ```

2. Test admin login:
   ```bash
   curl -X POST http://localhost:8080/api/admin-login \
     -d "username=admin" \
     -d "password=admin123"
   ```

3. Test student login:
   ```bash
   curl -X POST http://localhost:8080/api/student-login \
     -d "student_id=ST001" \
     -d "student_name=Anil Kumar"
   ```

## Notes

- For production, hash passwords using bcrypt instead of storing plain text
- Consider using Supabase Auth for better security
- The anon key has limited permissions - use service role key only on server-side if needed

