# Quick Start Guide

## ✅ What You've Done:
1. ✅ Created Supabase tables (`admins` and `students`)
2. ✅ Inserted data (admin and students)
3. ✅ Created `.env` file with credentials

## 🔍 Next Steps to Verify:

### 1. Check Supabase RLS (Row Level Security)

The "Forbidden" error is usually because RLS is enabled. Run this in Supabase SQL Editor:

```sql
-- Disable RLS for testing (development only)
ALTER TABLE admins DISABLE ROW LEVEL SECURITY;
ALTER TABLE students DISABLE ROW LEVEL SECURITY;
```

### 2. Verify Your .env File Format

Your `.env` file should look like this (no quotes, no spaces):

```
SUPABASE_URL=https://your-project-id.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

**Common mistakes:**
- ❌ `SUPABASE_URL = "https://..."` (spaces and quotes)
- ✅ `SUPABASE_URL=https://...` (no spaces, no quotes)

### 3. Test the Backend

```bash
cd Backend

# Make sure server is running
go run .

# In another terminal, test endpoints:
./test_endpoints.sh
```

### 4. Manual Test with curl

```bash
# Test admin login
curl -X POST http://localhost:8080/api/admin-login \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin" \
  -d "password=admin123"

# Test student login
curl -X POST http://localhost:8080/api/student-login \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "student_id=ST001" \
  -d "student_name=Anil Kumar"
```

### 5. Expected Responses

**Success (200):**
```json
{
  "success": true,
  "message": "Login successful",
  "admin": { "id": "...", "username": "admin" }
}
```

**Error (401/404):**
```json
{
  "error": "Invalid credentials"
}
```

## 🐛 If Still Not Working:

1. Check `TROUBLESHOOTING.md` for detailed solutions
2. Verify Supabase connection:
   ```bash
   # Replace with your actual values
   curl "https://YOUR_PROJECT_ID.supabase.co/rest/v1/admins" \
     -H "apikey: YOUR_ANON_KEY" \
     -H "Authorization: Bearer YOUR_ANON_KEY"
   ```

3. Check server logs when making requests

## 📝 Summary Checklist:

- [ ] RLS disabled on `admins` and `students` tables
- [ ] `.env` file has correct format (no quotes/spaces)
- [ ] Supabase URL is correct (no trailing slash)
- [ ] Anon key is correct (starts with `eyJ`)
- [ ] Tables have data inserted
- [ ] Server is running on port 8080
- [ ] Test endpoints return success responses

