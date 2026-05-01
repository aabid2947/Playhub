-- ============================================================================
-- Sprint 1 — students table per SRD §7.1
-- ============================================================================

create table public.students (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies(id) on delete cascade,
  center_id uuid references public.centers(id) on delete set null,

  -- Personal
  first_name text not null,
  last_name text not null,
  date_of_birth date,
  gender text check (gender in ('male','female','other','prefer_not_to_say')),
  photo text,

  -- Student-direct contact (often empty for minors)
  email text,
  phone text,

  -- Parent / guardian
  parent_name text not null,
  parent_email text,
  parent_phone text,
  parent_alternate_phone text,

  -- Address
  address text,
  city text,
  state text,
  pincode text,

  -- Emergency
  emergency_contact_name text,
  emergency_contact_phone text,

  -- Medical
  medical_notes text,
  injury_info text,

  -- Training
  sport text,
  skill_level text check (skill_level in ('beginner','intermediate','advanced')),

  -- Lifecycle
  enrollment_date date not null default current_date,
  status text not null default 'active'
    check (status in ('active','inactive','paused','graduated')),

  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index idx_students_academy on public.students(academy_id);
create index idx_students_center on public.students(center_id);
create index idx_students_status on public.students(academy_id, status);
create index idx_students_name_search on public.students
  using gin (to_tsvector('simple', first_name || ' ' || last_name));

create trigger trg_students_updated before update on public.students
  for each row execute function public.set_updated_at();

-- ============================================================================
-- RLS
--   Sprint-1 scope: academy-scoped read + admin-or-higher writes.
--   Coach/parent/student-restricted reads land in Sprint 2 (attendance) once
--   we have the joining tables (batch_enrollments, parent_links, etc).
-- ============================================================================

alter table public.students enable row level security;

create policy students_academy_read on public.students
  for select using (
    public.is_super_admin()
    or academy_id = public.current_user_academy_id()
  );

create policy students_admin_write on public.students
  for all using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  )
  with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );
