-- ============================================================================
-- Enforce the creation-chain dependencies at the DB LEVEL (previously UI-only).
--
-- Until now these product rules were enforced ONLY by the Flutter forms
-- (validators + save-time guards):
--   * a coach needs a center
--   * a batch needs a sport AND a coach
--   * a student needs a center
--   * a center_admin / head_coach LOGIN needs a center
-- The columns were nullable, no CHECK asserted them, and the RLS insert policies
-- explicitly ALLOW a null center (`p_center_id is null or ...`). So any path that
-- skipped the UI — CSV bulk import, a raw API call with a valid JWT, or an invite
-- that omitted the center — created powerless / isolation-leaking rows (e.g. a
-- head_coach with no center can manage nothing via current_user_in_center(); a
-- null-center student/coach is visible+editable by every center_admin because
-- center_admin_sees_*(null) = true).
--
-- This migration makes 4 of those rules real NOT NULL columns + 1 role-
-- conditional CHECK on users, and flips the 4 affected FKs from ON DELETE SET
-- NULL to ON DELETE RESTRICT (a NOT NULL column cannot be nulled on parent
-- delete). CONSEQUENCE: deleting a center / sport / coach that is still
-- referenced is now BLOCKED — reassign the dependents first.
--
-- NOT enforced here: "a coach must have >=1 sport". Sports live in the
-- coach_sports join table and the app inserts them in a SEPARATE request after
-- the coach row, so no column / CHECK / deferred-trigger can assert it without
-- rewriting coach-create to an atomic RPC. That one stays a UI-layer guard
-- (owner decision, 2026-07-10).
--
-- Pre-req data cleanup (below): existing violating rows are either backfilled
-- (null center in a single-center academy -> that center) or deleted
-- (un-backfillable junk in abandoned test academies: the 0-center academy "am",
-- and a coachless batch in "Elite" that has no coach records to assign). Every
-- child FK of the deleted rows is CASCADE or SET NULL (verified), so the deletes
-- are self-contained. 0 violations remain afterwards, so the constraints add as
-- VALID.
-- ============================================================================

begin;

-- 1. BACKFILL — assign a center to null-center staff / students / coaches, but
--    ONLY when the academy has exactly one center (unambiguous). Zero-center and
--    multi-center rows are handled below or left as-is (none of the latter exist).
update public.users u
   set center_id = (select ce.id from public.centers ce where ce.academy_id = u.academy_id)
 where u.role in ('center_admin', 'head_coach')
   and u.center_id is null
   and (select count(*) from public.centers ce where ce.academy_id = u.academy_id) = 1;

update public.students s
   set center_id = (select ce.id from public.centers ce where ce.academy_id = s.academy_id)
 where s.center_id is null
   and (select count(*) from public.centers ce where ce.academy_id = s.academy_id) = 1;

update public.coaches c
   set center_id = (select ce.id from public.centers ce where ce.academy_id = c.academy_id)
 where c.center_id is null
   and (select count(*) from public.centers ce where ce.academy_id = c.academy_id) = 1;

-- 2. DELETE un-backfillable junk (abandoned test academies).
--    a) Batches missing a sport or coach — child rows (enrollments, attendance,
--       batch_staff, fee/discount assignments, threads) are all FK CASCADE/SET NULL.
delete from public.batches where sport_id is null or coach_id is null;

--    b) Coaches / students with no center in a ZERO-center academy (no center
--       exists to assign). coach_sports + coach_documents cascade; student
--       invoices/payments/enrollments/etc. cascade (test data only).
delete from public.coaches c
 where c.center_id is null
   and (select count(*) from public.centers ce where ce.academy_id = c.academy_id) = 0;

delete from public.students s
 where s.center_id is null
   and (select count(*) from public.centers ce where ce.academy_id = s.academy_id) = 0;

-- 3. FKs SET NULL -> RESTRICT (a NOT NULL column can't be nulled on parent delete).
alter table public.coaches
  drop constraint coaches_center_id_fkey,
  add  constraint coaches_center_id_fkey
       foreign key (center_id) references public.centers(id) on delete restrict;

alter table public.students
  drop constraint students_center_id_fkey,
  add  constraint students_center_id_fkey
       foreign key (center_id) references public.centers(id) on delete restrict;

alter table public.batches
  drop constraint batches_sport_id_fkey,
  add  constraint batches_sport_id_fkey
       foreign key (sport_id) references public.sports(id) on delete restrict;

alter table public.batches
  drop constraint batches_coach_id_fkey,
  add  constraint batches_coach_id_fkey
       foreign key (coach_id) references public.coaches(id) on delete restrict;

-- 4. Make the columns required (0 violations remain -> validates immediately).
alter table public.coaches  alter column center_id set not null;
alter table public.students alter column center_id set not null;
alter table public.batches  alter column sport_id  set not null;
alter table public.batches  alter column coach_id  set not null;

-- 5. users — a center_admin / head_coach login MUST carry a center. All other
--    roles (owner, admin, coach, trainer, parent, student) may be center-less.
alter table public.users
  add constraint users_center_scoped_role_needs_center
  check (role not in ('center_admin', 'head_coach') or center_id is not null);

commit;
