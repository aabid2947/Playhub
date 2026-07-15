-- ============================================================================
-- Trainers are modeled as coaches records tagged kind='trainer' (a trainer =
-- a coaches row + a linked login with role=trainer), so the ENTIRE coaches
-- infrastructure — the form, center/sport scoping, RLS (can_manage_coach_record),
-- documents, and the invite-from-record flow — is reused for trainers. `kind`
-- discriminates the Coaches vs Trainers sections in the app.
--
-- Existing rows are coaches (the default). RLS is deliberately UNCHANGED:
-- can_manage_coach_record already scopes create/edit to owner/admin (any center)
-- and center_admin/head_coach (own center), which is exactly the access we want
-- for trainers too. The distinction is purely the app section + the login role
-- (trainer vs coach) minted on invite.
--
-- Batch assignment stays split: a batch's PRIMARY coach (batches.coach_id) is
-- picked from kind='coach' only (the app filters this); trainers assist via
-- batch_staff. gen:types owed for web-admin (new column).
-- ============================================================================

alter table public.coaches
  add column if not exists kind text not null default 'coach'
  check (kind in ('coach', 'trainer'));

comment on column public.coaches.kind is
  'Which staff section this record belongs to: ''coach'' (default) or '
  '''trainer''. A trainer is a coaches row + a linked role=trainer login; '
  'reuses all coach infrastructure. batches.coach_id picks kind=''coach'' only.';
