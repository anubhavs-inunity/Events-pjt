# Troubleshooting Guide

## Issue: "Forbidden" Error from Supabase

If you're getting "Forbidden" errors when testing the login endpoints, it's likely due to **Row Level Security (RLS)** policies in Supabase.

### Solution 1: Disable RLS (For Development/Testing)

Go to Supabase Dashboard → SQL Editor and run:

```sql
-- Disable RLS for admins table
ALTER TABLE admins DISABLE ROW LEVEL SECURITY;

-- Disable RLS for students table
ALTER TABLE students DISABLE ROW LEVEL SECURITY;
```

### Solution 2: Create RLS Policies (For Production)

If you want to keep RLS enabled, create policies:

```sql
-- Allow public read access to admins (for login)
CREATE POLICY "Allow public read on admins"
ON admins FOR SELECT
USING (true);

-- Allow public read access to students (for login)
CREATE POLICY "Allow public read on students"
ON students FOR SELECT
USING (true);
```

## Issue: "Database connection error"

### Check:
1. **Supabase URL** in `.env` file:
   - Should be: `https://your-project-id.supabase.co`
   - No trailing slash

2. **Anon Key** in `.env` file:
   - Get from: Supabase Dashboard → Settings → API → Project API keys → `anon` `public`
   - Should start with `eyJ...`

3. **Network connectivity**:
   ```bash
   curl https://your-project-id.supabase.co/rest/v1/
   ```

## Issue: "Student ID not found" or "Invalid credentials"

### Check:
1. **Tables exist**:
   ```sql
   SELECT * FROM admins;
   SELECT * FROM students;
   ```

2. **Data is inserted**:
   ```sql
   -- Verify admin exists
   SELECT * FROM admins WHERE username = 'admin';
   
   -- Verify students exist
   SELECT * FROM students;
   ```

3. **Column names match**:
   - `admins` table should have: `username`, `password`
   - `students` table should have: `student_id`, `student_name`

## Issue: Server won't start

### Check:
1. **Port 8080 is available**:
   ```bash
   lsof -i :8080
   # If something is using it, kill it or change port
   ```

2. **Go modules are installed**:
   ```bash
   cd Backend
   go mod tidy
   go build .
   ```

## Testing Steps

1. **Verify .env file**:
   ```bash
   cd Backend
   cat .env
   # Should show SUPABASE_URL and SUPABASE_ANON_KEY
   ```

2. **Test Supabase connection directly**:
   ```bash
   # Replace with your actual values
   curl "https://YOUR_PROJECT_ID.supabase.co/rest/v1/admins?username=eq.admin" \
     -H "apikey: YOUR_ANON_KEY" \
     -H "Authorization: Bearer YOUR_ANON_KEY"
   ```

3. **Run test script**:
   ```bash
   cd Backend
   ./test_endpoints.sh
   ```

## Common .env File Format

Make sure your `.env` file looks like this (no quotes, no spaces around `=`):

```
SUPABASE_URL=https://abcdefghijklmnop.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFiY2RlZmdoaWprbG1ub3AiLCJyb2xlIjoiYW5vbiIsImlhdCI6MTYzMjU2NzI5MCwiZXhwIjoxOTQ4MTQzMjkwfQ.xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

**Important**: 
- No spaces around `=`
- No quotes around values
- No trailing slashes in URL

