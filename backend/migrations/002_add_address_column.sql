-- Migration script to add address column to users table
ALTER TABLE users ADD COLUMN IF NOT EXISTS address TEXT;
