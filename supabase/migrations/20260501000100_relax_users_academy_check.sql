-- ============================================================================
-- Relax users.users_academy_required CHECK so signup can create a stub row
-- before the user has been linked to an academy.
--
-- The proper flow (Sprint 1) is:
--   1. user signs up via Supabase Auth
--   2. trigger creates public.users row with role inferred from metadata
--   3. signup-bootstrap Edge Function creates academy (for owners) or links
--      to invited academy (for staff/students), populating academy_id
--
-- Until that bootstrap function exists, allow academy_id to be null for any
-- role. We'll re-introduce a stricter invariant once the flow is wired up.
-- ============================================================================

alter table public.users
  drop constraint if exists users_academy_required;

-- Soft hint: super_admin must NEVER have an academy_id; everyone else may.
alter table public.users
  add constraint users_super_admin_no_academy
  check (role <> 'super_admin' or academy_id is null);
