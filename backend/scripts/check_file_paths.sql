-- Quick script to check file paths in your database

-- Check all file paths
SELECT id, file_path, status, created_at 
FROM files 
ORDER BY created_at DESC 
LIMIT 20;

-- Count files by path type
SELECT 
    CASE 
        WHEN file_path LIKE 's3://%' THEN 'S3'
        WHEN file_path LIKE 'uploads/%' THEN 'Local'
        ELSE 'Other'
    END as path_type,
    COUNT(*) as count
FROM files
GROUP BY path_type;

-- Show S3 paths that need to be fixed
SELECT id, file_path, created_at 
FROM files 
WHERE file_path LIKE 's3://%';
