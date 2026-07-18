-- ============================================================================
-- PlayHub — Cap the announcement_media bucket at 100 MiB + image/video types.
-- Paste-and-run in the Supabase SQL editor. Idempotent.
-- Mirrors migration 20260608000400_announcement_media_limits.sql.
--
-- IMPORTANT: a bucket limit can't exceed the PROJECT-WIDE storage limit. If
-- uploads still 413, raise it in Dashboard → Project Settings → Storage →
-- "Upload file size limit" (set it to at least 100 MiB).
-- ============================================================================

update storage.buckets
   set file_size_limit = 104857600,  -- 100 MiB
       allowed_mime_types = array[
         'image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif',
         'video/mp4', 'video/quicktime', 'video/webm', 'video/x-m4v'
       ]
 where id = 'announcement_media';
