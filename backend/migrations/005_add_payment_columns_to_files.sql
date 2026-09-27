-- Migration: Add payment_order_id and payment_status columns to files table
-- This migration ensures the payment columns exist on the files table
-- Run this manually on Render if InitSchema didn't create them

-- Check if columns exist before adding them
DO $$
BEGIN
    -- Add payment_order_id column if it doesn't exist
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_name = 'files' 
        AND column_name = 'payment_order_id'
    ) THEN
        ALTER TABLE files ADD COLUMN payment_order_id INT REFERENCES payment_orders(id);
        RAISE NOTICE 'Added payment_order_id column to files table';
    ELSE
        RAISE NOTICE 'payment_order_id column already exists';
    END IF;

    -- Add payment_status column if it doesn't exist
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_name = 'files' 
        AND column_name = 'payment_status'
    ) THEN
        ALTER TABLE files ADD COLUMN payment_status TEXT DEFAULT 'unpaid';
        RAISE NOTICE 'Added payment_status column to files table';
    ELSE
        RAISE NOTICE 'payment_status column already exists';
    END IF;
END $$;

-- Create indexes if they don't exist
CREATE INDEX IF NOT EXISTS idx_files_payment_order_id ON files(payment_order_id);
CREATE INDEX IF NOT EXISTS idx_files_payment_status ON files(payment_status);

-- Verify the columns were added
SELECT 
    column_name, 
    data_type, 
    is_nullable,
    column_default
FROM information_schema.columns 
WHERE table_name = 'files' 
AND column_name IN ('payment_order_id', 'payment_status')
ORDER BY column_name;
