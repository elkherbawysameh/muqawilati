-- إضافة حقول طريقة الدفع للعملاء
-- شغّل هذا في Supabase → SQL Editor

ALTER TABLE clients
  ADD COLUMN IF NOT EXISTS payment_method TEXT DEFAULT 'installments'
  CHECK (payment_method IN ('upfront', 'installments', 'on_completion'));

ALTER TABLE clients
  ADD COLUMN IF NOT EXISTS advance_percentage DECIMAL(5,2) DEFAULT 0;
