-- ============================================================================
-- PlayHub - hierarchy FOLLOW-UP migrations (000600/000700/000800).
--
-- Apply this on a DB that already has Phases 1-5 (the original bundle) but is
-- MISSING the three follow-ups. Brings the DB to the full 9-migration state
-- (matches supabase db reset). Safe to re-run: all statements are
-- CREATE OR REPLACE or drop+recreate of policies that already exist.
--
--   000600 - head_coach may manage NULL-sport batches in their center
--   000700 - head_coach + coach can create/edit students (own center)
--   000800 - head_coach can create/edit coach records (own center)
-- ============================================================================

begin;


-- ##########################################################################
-- ## 20260607000600_relax_head_coach_null_sport.sql
-- ##########################################################################

-- ============================================================================
-- Phase 2 follow-up — head_coach may also manage UNSCOPED (null-sport) batches
-- in their own center, not only batches tagged with one of their sports.
--
-- Phase 2 (20260607000200) made head_coach STRICTLY sport-scoped: a batch with
-- a NULL sport_id was unmanageable by a head_coach. In practice many batches
-- carry no sport_id (legacy data; the create form doesn't force one), which
-- locked head_coaches out of editing / enrolling / attendance on legitimate
-- batches in their own center (RLS 42501 on batches / batch_enrollments / etc).
--
-- New head_coach rule on a batch: in their center AND
--   (the batch has NO sport  OR  the batch's sport is one of theirs).
-- Sport-tagged batches stay limited to the owning head_coach; untagged batches
-- fall back to plain center scope. Tradeoff: a head_coach can now touch any
-- sport-less batch in their center — acceptable vs. locking them out.
--
-- This relaxes every head_coach batch gate at once, because attendance /
-- performance go through batch_in_my_sport() and enrollment / staffing / edit
-- go through can_manage_batch_fields().
-- ============================================================================

create or replace function public.batch_in_my_sport(p_batch_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.batches b
    where b.id = p_batch_id
      and (b.sport_id is null or public.head_coach_owns_sport(b.sport_id))
  );
$$;

create or replace function public.can_manage_batch_fields(
  p_center_id uuid,
  p_sport_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case (select role from public.users where id = auth.uid())
    when 'academy_owner' then true
    when 'academy_admin' then true
    when 'center_admin'  then
      p_center_id is null or p_center_id = public.current_user_center_id()
    when 'head_coach'    then
      (p_center_id is null or p_center_id = public.current_user_center_id())
      and (p_sport_id is null or public.head_coach_owns_sport(p_sport_id))
    else false
  end;
$$;



-- ##########################################################################
-- ## 20260607000700_head_coach_manage_students.sql
-- ##########################################################################

-- ============================================================================
-- head_coach AND coach can create + edit STUDENT records in their own center.
--
-- Originally students were a center_admin / admin record-management task; the
-- coaching roles were batch/sport scoped. This grants both head_coach and coach
-- center-scoped student create/edit so the people running training can onboard
-- athletes directly.
--
-- NOTE on scope: students carry a center_id but NO sport/batch, so this is
-- necessarily CENTER-wide for the user's own center (same reach as center_admin
-- for students) — it can't be narrowed to "their sport" or "their batch".
-- DELETE stays admin / center_admin (can_admin_center_scope) — coaching roles
-- onboard, they don't purge.
-- ============================================================================

create or replace function public.can_manage_student(p_center_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case (select role from public.users where id = auth.uid())
    when 'academy_owner' then true
    when 'academy_admin' then true
    when 'center_admin'  then
      p_center_id is null or p_center_id = public.current_user_center_id()
    when 'head_coach'    then
      p_center_id is null or p_center_id = public.current_user_center_id()
    when 'coach'         then
      p_center_id is null or p_center_id = public.current_user_center_id()
    else false
  end;
$$;

grant execute on function public.can_manage_student(uuid) to authenticated;

-- students insert + update → can_manage_student (adds head_coach, own center).
-- delete is left on can_admin_center_scope (admin tier + center_admin only).
drop policy students_insert on public.students;
drop policy students_update on public.students;

create policy students_insert on public.students
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_student(center_id))
  );

create policy students_update on public.students
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_student(center_id))
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_student(center_id))
  );



-- ##########################################################################
-- ## 20260607000800_head_coach_manage_coaches.sql
-- ##########################################################################

-- ============================================================================
-- head_coach can create + edit COACH records (and their coach_sports) in their
-- own center — completing the "create coach -> assign to a batch" loop.
--
-- The coaches row is what batches.coach_id points at, so inviting a coach LOGIN
-- wasn't enough; the head_coach also needs to create the coaches record. As
-- with students, coach records carry a center_id but no sport, so this is
-- CENTER-scoped for the head_coach's center (same reach as center_admin for
-- coaches). DELETE stays admin / center_admin.
--
-- can_manage_coach() (used by the coach_sports junction policies) is redefined
-- to ride the same gate, so the coach form's setCoachSports() write also
-- succeeds for a head_coach.
-- ============================================================================

create or replace function public.can_manage_coach_record(p_center_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case (select role from public.users where id = auth.uid())
    when 'academy_owner' then true
    when 'academy_admin' then true
    when 'center_admin'  then
      p_center_id is null or p_center_id = public.current_user_center_id()
    when 'head_coach'    then
      p_center_id is null or p_center_id = public.current_user_center_id()
    else false
  end;
$$;

grant execute on function public.can_manage_coach_record(uuid) to authenticated;

-- coaches insert + update → include head_coach (own center). delete unchanged.
drop policy coaches_insert on public.coaches;
drop policy coaches_update on public.coaches;

create policy coaches_insert on public.coaches
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_coach_record(center_id))
  );

create policy coaches_update on public.coaches
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_coach_record(center_id))
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_coach_record(center_id))
  );

-- coach_sports writes ride can_manage_coach(); widen it to head_coach too so a
-- head_coach's "new coach" save (which sets the coach's sports) succeeds.
create or replace function public.can_manage_coach(p_coach_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.can_manage_coach_record(
    (select center_id from public.coaches where id = p_coach_id)
  );
$$;


-- ============================================================================
commit;
