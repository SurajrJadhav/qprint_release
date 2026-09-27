-- Script to convert S3 file paths to local paths
-- Run this in your PostgreSQL database

-- Step 1: Check what S3 paths exist
SELECT id, file_path, created_at 
FROM files 
WHERE file_path LIKE 's3://%' 
ORDER BY created_at DESC 
LIMIT 10;

-- Step 2: Update S3 paths to local paths
-- This extracts the filename from s3://bucket/filename and converts to uploads/filename
UPDATE files 
SET file_path = 'uploads/' || SUBSTRING(file_path FROM 's3://[^/]+/(.+)$')
WHERE file_path LIKE 's3://%';

-- Step 3: Verify the update
SELECT id, file_path, created_at 
FROM files 
WHERE file_path LIKE 'uploads/%' 
ORDER BY created_at DESC 
LIMIT 10;

-- Alternative: If you want to set all S3 paths to a specific local path pattern
-- UPDATE files 
-- SET file_path = 'uploads/' || id::text || '.pdf'
-- WHERE file_path LIKE 's3://%';
