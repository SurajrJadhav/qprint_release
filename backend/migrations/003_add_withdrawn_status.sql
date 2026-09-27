-- Migration script to add 'withdrawn' status to files table

-- Add new status 'withdrawn' to existing status column
ALTER TYPE file_status ADD VALUE 'withdrawn' BEFORE 'uploaded';

-- Update existing 'files' table status column to use the new type
ALTER TABLE files
ALTER COLUMN status TYPE file_status USING status::file_status;

-- You might need to drop and re-create the type if it's already in use
-- by other tables or constraints, but this simple ALTER TYPE should work for adding a value.

-- If ALTER TYPE ADD VALUE is not supported or causes issues, consider:
-- 1. Create a new enum type with all values (including 'withdrawn')
-- 2. Update the 'files' table to use the new type
-- 3. Drop the old type

-- Example for more complex type migration:
-- CREATE TYPE file_status_new AS ENUM ('withdrawn', 'uploaded', 'downloaded');
-- ALTER TABLE files ALTER COLUMN status TYPE file_status_new USING status::text::file_status_new;
-- DROP TYPE file_status;
-- ALTER TYPE file_status_new RENAME TO file_status;
