-- ============================================================================
-- Sprint 1 — batches + batch_enrollments per SRD §3.4 / §7.1
-- ============================================================================

create table public.batches (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies(id) on delete cascade,
  center_id uuid references public.centers(id) on delete set null,
  coach_id uuid references public.coaches(id) on delete set null,

  name text not null,
  description text,
  sport text,

  -- Schedule stored as JSONB for flexibility:
  -- { "days": ["mon","wed","fri"], "start_time": "16:00", "end_time": "17:30" }
  schedule jsonb not null default '{}'::jsonb,

  capacity int,
  age_group text,                                -- "6-10", "U-15", "Adult"
  skill_level text check (skill_level
    in ('beginner', 'intermediate', 'advanced', 'mixed')),
  fees numeric(10, 2),

  start_date date,
  end_date date,

  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index idx_batches_academy on public.batches(academy_id);
create index idx_batches_center on public.batches(center_id);
create index idx_batches_coach on public.batches(coach_id);

create trigger trg_batches_updated before update on public.batches
  for each row execute function public.set_updated_at();

-- Junction: which students are enrolled in which batch -----------------------
create table public.batch_enrollments (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies(id) on delete cascade,
  batch_id uuid not null references public.batches(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  enrollment_status text not null default 'active'
    check (enrollment_status in ('active', 'waitlisted', 'withdrawn')),
  enrolled_at timestamptz not null default now(),
  unique (batch_id, student_id)
);

create index idx_enrollments_batch on public.batch_enrollments(batch_id);
create index idx_enrollments_student on public.batch_enrollments(student_id);

-- ============================================================================
-- RLS — same Sprint-1 pattern: academy-scoped read + admin-or-higher writes
-- ============================================================================

alter table public.batches            enable row level security;
alter table public.batch_enrollments  enable row level security;

create policy batches_academy_read on public.batches
  for select using (
    public.is_super_admin()
    or academy_id = public.current_user_academy_id()
  );

create policy batches_admin_write on public.batches
  for all using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  )
  with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create policy enrollments_academy_read on public.batch_enrollments
  for select using (
    public.is_super_admin()
    or academy_id = public.current_user_academy_id()
  );

create policy enrollments_admin_write on public.batch_enrollments
  for all using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  )
  with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

-- ============================================================================
-- View: batches with enrollment counts (saves a separate query in the UI)
-- ============================================================================
create or replace view public.batches_with_counts as
select
  b.*,
  coalesce(e.cnt, 0)::int as enrolled_count
from public.batches b
left join (
  select batch_id, count(*)::int as cnt
  from public.batch_enrollments
  where enrollment_status = 'active'
  group by batch_id
) e on e.batch_id = b.id;

grant select on public.batches_with_counts to authenticated;
