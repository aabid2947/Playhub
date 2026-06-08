-- ============================================================================
-- Constrain the announcement_media bucket: cap per-file size at 100 MiB and
-- restrict to image/video mime types. (The original bucket was created with no
-- explicit limit, so it inherited the project-wide storage limit and rejected
-- larger videos with a 413 "object exceeded the maximum allowed size".)
--
-- NOTE: the per-bucket limit can never exceed the PROJECT-WIDE storage limit.
-- Local dev: supabase/config.toml [storage] file_size_limit (now 100MiB) — run
-- `supabase stop && supabase start` to apply. Hosted: Dashboard → Project
-- Settings → Storage → "Upload file size limit".
-- ============================================================================

update storage.buckets
   set file_size_limit = 104857600,  -- 100 MiB
       allowed_mime_types = array[
         'image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif',
         'video/mp4', 'video/quicktime', 'video/webm', 'video/x-m4v'
       ]
 where id = 'announcement_media';
