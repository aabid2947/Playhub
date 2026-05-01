-- ============================================================================
-- Sprint 2 — attendance_records per SRD §3.5 / §7.1
--
-- Coaches mark attendance for their batches. One row per (batch, student,
-- date). Status enum present/absent/late/excused. method tracks how the
-- record was created (manual marking, bulk all-present, auto-mark-absent
-- cron, future QR / biometric).
-- ============================================================================

-- Helper: coach role and above. Used by attendance + performance writes
-- so plain "coach" users (Sprint 2 coach-login lands as a sub-task) can
-- mark attendance and performance, but not edit students/batches.
create or replace function public.has_coach_or_higher()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select role from public.users where id = auth.uid())
      in ('super_admin','academy_owner','academy_admin',
          'center_admin','head_coach','coach'),
    false
  )
$$;

create table public.attendance_records (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies(id) on delete cascade,
  batch_id uuid not null references public.batches(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  coach_id uuid references public.coaches(id) on delete set null,

  date date not null,
  status text not null
    check (status in ('present', 'absent', 'late', 'excused')),

  check_in_time timestamptz,
  check_out_time timestamptz,
  notes text,

  marked_by uuid references public.users(id) on delete set null,
  method text not null default 'manual'
    check (method in ('manual', 'bulk', 'auto', 'qr', 'biometric')),

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  -- exactly one record per student per batch per day
  unique (batch_id, student_id, date)
);

create index idx_attendance_academy_date
  on public.attendance_records(academy_id, date desc);
create index idx_attendance_batch_date
  on public.attendance_records(batch_id, date desc);
create index idx_attendance_student_date
  on public.attendance_records(student_id, date desc);
create index idx_attendance_coach_date
  on public.attendance_records(coach_id, date desc);

create trigger trg_attendance_updated before update on public.attendance_records
  for each row execute function public.set_updated_at();

-- ============================================================================
-- RLS — academy-scoped read; coach-or-higher writes within their own academy.
--
-- Policy is split per-action to avoid the `for all using (admin_check)` leak
-- pattern (see RLS gotcha note); the using-clause always pins academy_id.
-- ============================================================================

alter table public.attendance_records enable row level security;

create policy attendance_academy_read on public.attendance_records
  for select using (
    public.is_super_admin()
    or academy_id = public.current_user_academy_id()
  );

create policy attendance_coach_insert on public.attendance_records
  for insert with check (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.has_coach_or_higher()
    )
  );

create policy attendance_coach_update on public.attendance_records
  for update using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.has_coach_or_higher()
    )
  )
  with check (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.has_coach_or_higher()
    )
  );

create policy attendance_admin_delete on public.attendance_records
  for delete using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.has_admin_or_higher()
    )
  );

-- Audit log
create trigger trg_audit_attendance_records
  after insert or update or delete on public.attendance_records
  for each row execute function public.write_audit_log();
