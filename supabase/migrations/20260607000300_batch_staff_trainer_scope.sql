-- ============================================================================
-- Phase 3 — trainer→student scope, coach→student enrollment, trainer perf.
--
-- The org model wants:
--   • coach   → assigns students (enrol into THEIR OWN batch) + creates trainers
--   • trainer → limited to THEIR students, manages attendance + performance
--
-- "A trainer's students" needs a structure: a batch carries a coach
-- (batches.coach_id) plus zero-or-more assigned trainers (the new batch_staff).
-- A trainer's scope = students enrolled in the batches they staff.
--
--   staff_on_batch(b)        = caller is the batch's coach OR an assigned staffer
--   student_assigned_to_me(s)= s is actively enrolled in a batch I staff
--   can_staff_batch(b)       = who may add/remove staff on a batch (the coach +
--                              management tiers)
--
-- Changes vs Phase 2:
--   • coach can now ENROL into their own batch (can_manage_enrollment).
--   • trainer GAINS performance (was else-false) — scoped to their batches.
--   • attendance/perf "coach"+"trainer" branches use staff_on_batch, so an
--     assigned co-coach/trainer (not just batches.coach_id) is covered.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- batch_staff — additional staff (trainers / assistant coaches) on a batch.
-- The primary coach stays on batches.coach_id; this is for everyone else.
-- ----------------------------------------------------------------------------
create table public.batch_staff (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies(id) on delete cascade,
  batch_id uuid not null references public.batches(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  role text not null default 'trainer'
    check (role in ('trainer', 'assistant_coach')),
  created_at timestamptz not null default now(),
  unique (batch_id, user_id)
);

create index idx_batch_staff_batch on public.batch_staff(batch_id);
create index idx_batch_staff_user on public.batch_staff(user_id);

alter table public.batch_staff enable row level security;

-- ----------------------------------------------------------------------------
-- Scope helpers
-- ----------------------------------------------------------------------------

-- Is the caller staff on this batch — its coach (batches.coach_id) or an
-- assigned trainer/assistant (batch_staff)?
create or replace function public.staff_on_batch(p_batch_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.coach_owns_batch(p_batch_id)
    or exists (
      select 1 from public.batch_staff bs
      where bs.batch_id = p_batch_id and bs.user_id = auth.uid()
    );
$$;

-- Is this student actively enrolled in a batch the caller staffs?
-- (This is "a trainer's / coach's students".)
create or replace function public.student_assigned_to_me(p_student_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.batch_enrollments e
    where e.student_id = p_student_id
      and e.enrollment_status = 'active'
      and public.staff_on_batch(e.batch_id)
  );
$$;

-- Who may add/remove staff on a batch: the batch's coach, plus the management
-- tiers that can manage the batch itself (admin / center_admin / head_coach-sport).
create or replace function public.can_staff_batch(p_batch_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.coach_owns_batch(p_batch_id)
    or public.can_manage_batch_fields(
         (select center_id from public.batches where id = p_batch_id),
         (select sport_id  from public.batches where id = p_batch_id)
       );
$$;

grant execute on function public.staff_on_batch(uuid)          to authenticated;
grant execute on function public.student_assigned_to_me(uuid)  to authenticated;
grant execute on function public.can_staff_batch(uuid)         to authenticated;

-- ----------------------------------------------------------------------------
-- batch_staff RLS — academy-scoped read; writes gated by can_staff_batch.
-- ----------------------------------------------------------------------------
create policy batch_staff_academy_read on public.batch_staff
  for select using (
    public.is_super_admin()
    or academy_id = public.current_user_academy_id()
  );

create policy batch_staff_write_insert on public.batch_staff
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_staff_batch(batch_id))
  );

create policy batch_staff_write_update on public.batch_staff
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_staff_batch(batch_id))
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_staff_batch(batch_id))
  );

create policy batch_staff_write_delete on public.batch_staff
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_staff_batch(batch_id))
  );

create trigger trg_audit_batch_staff
  after insert or update or delete on public.batch_staff
  for each row execute function public.write_audit_log();

-- ----------------------------------------------------------------------------
-- Fold the new scope into the ladder helpers.
-- ----------------------------------------------------------------------------

-- Enrollment: management tiers (sport-aware) OR the batch's own coach.
create or replace function public.can_manage_enrollment(p_batch_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.can_manage_batch_fields(
           (select center_id from public.batches where id = p_batch_id),
           (select sport_id  from public.batches where id = p_batch_id)
         )
      or public.coach_owns_batch(p_batch_id);
$$;

-- Attendance: coach + trainer branches become "staff on the batch" (covers
-- batches.coach_id AND assigned trainers/assistants).
create or replace function public.can_mark_attendance(p_batch_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case (select role from public.users where id = auth.uid())
    when 'academy_owner' then true
    when 'academy_admin' then true
    when 'center_admin'  then public.batch_in_my_center(p_batch_id)
    when 'head_coach'    then
      public.batch_in_my_center(p_batch_id)
      and public.batch_in_my_sport(p_batch_id)
    when 'coach'         then public.staff_on_batch(p_batch_id)
    when 'trainer'       then public.staff_on_batch(p_batch_id)
    else false
  end;
$$;

-- Performance: trainer is now GRANTED (scoped to their batches via
-- staff_on_batch); coach likewise via staff_on_batch.
create or replace function public.can_record_performance(p_batch_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case (select role from public.users where id = auth.uid())
    when 'academy_owner' then true
    when 'academy_admin' then true
    when 'center_admin'  then p_batch_id is null or public.batch_in_my_center(p_batch_id)
    when 'head_coach'    then
      p_batch_id is null
      or (public.batch_in_my_center(p_batch_id)
          and public.batch_in_my_sport(p_batch_id))
    when 'coach'         then p_batch_id is null or public.staff_on_batch(p_batch_id)
    when 'trainer'       then p_batch_id is not null and public.staff_on_batch(p_batch_id)
    else false
  end;
$$;
