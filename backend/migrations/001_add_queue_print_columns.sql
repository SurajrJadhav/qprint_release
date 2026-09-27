-- Migration script to add Queue Print feature columns
-- Run this in your PostgreSQL database

-- Add new columns to files table
ALTER TABLE files ADD COLUMN IF NOT EXISTS print_type TEXT DEFAULT 'private';
ALTER TABLE files ADD COLUMN IF NOT EXISTS copies INT DEFAULT 1;
ALTER TABLE files ADD COLUMN IF NOT EXISTS print_mode TEXT DEFAULT 'single';
ALTER TABLE files ADD COLUMN IF NOT EXISTS color_mode TEXT DEFAULT 'bw';
ALTER TABLE files ADD COLUMN IF NOT EXISTS paper_size TEXT DEFAULT 'A4';
ALTER TABLE files ADD COLUMN IF NOT EXISTS num_pages INT DEFAULT 0;
ALTER TABLE files ADD COLUMN IF NOT EXISTS total_cost DECIMAL(10,2) DEFAULT 0;
ALTER TABLE files ADD COLUMN IF NOT EXISTS shop_id INT REFERENCES users(id);
ALTER TABLE files ADD COLUMN IF NOT EXISTS queue_position INT;

-- Verify the changes
SELECT column_name, data_type, column_default 
FROM information_schema.columns 
WHERE table_name = 'files' 
ORDER BY ordinal_position;
