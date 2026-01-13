-- Add 10 More Mock Students to the Database
-- Run this in Supabase SQL Editor

INSERT INTO public.students (student_id, student_name) VALUES
('ST004', 'Sneha Patel'),
('ST005', 'Vikram Singh'),
('ST006', 'Meera Desai'),
('ST007', 'Arjun Reddy'),
('ST008', 'Kavya Nair'),
('ST009', 'Rohan Mehta'),
('ST010', 'Ananya Sharma'),
('ST011', 'Aditya Kumar'),
('ST012', 'Isha Gupta'),
('ST013', 'Rahul Verma')
ON CONFLICT (student_id) DO NOTHING;

-- Verify the students were added
SELECT student_id, student_name, created_at 
FROM public.students 
ORDER BY student_id;

