#!/bin/bash

echo "Testing Backend Endpoints..."
echo "================================"
echo ""

# Test Admin Login
echo "1. Testing Admin Login..."
curl -X POST http://localhost:8080/api/admin-login \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin" \
  -d "password=admin123" \
  -w "\nStatus: %{http_code}\n"
echo ""

# Test Student Login
echo "2. Testing Student Login..."
curl -X POST http://localhost:8080/api/student-login \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "student_id=ST001" \
  -d "student_name=Anil Kumar" \
  -w "\nStatus: %{http_code}\n"
echo ""

echo "================================"
echo "If you see 'Forbidden' errors, check:"
echo "1. Supabase RLS policies (disable for testing)"
echo "2. Supabase URL and API key in .env file"
echo "3. Tables exist in Supabase"
echo "4. Data is inserted in tables"

