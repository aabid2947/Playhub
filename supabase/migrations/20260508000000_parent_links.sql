-- ============================================================================
-- parent_links — joins parent users to the students they're allowed to see.
--
-- Plus students.user_id (older students with their own login) and a reusable
-- helper `parent_can_see_student(student_id)` used to narrow read policies on
-- student-keyed tables (students, attendance, performance, invoices,
-- payments, batch_enrollments) for the 'parent' and 'student' roles.
--
-- For all other roles (super_admin, owner, admin, center_admin, head_coach,
-- coach, trainer) the existing academy-wide read behaviour is preserved.
-- ============================================================================

create table public.parent_links (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies(id) on delete cascade,
  parent_user_id uuid not null references public.users(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  relationship text not null default 'parent',
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  unique (parent_user_id, student_id)
);

create index idx_parent_links_academy on public.parent_links(academy_id);
create index idx_parent_links_parent on public.parent_links(parent_user_id);
create index idx_parent_links_student on public.parent_links(student_id);

-- A student row may carry an optional auth user (older students log in
-- directly). One-to-one when set.
alter table public.students
  add column user_id uuid references public.users(id) on delete set null;
create unique index idx_students_user
  on public.students(user_id) where user_id is not null;

-- ============================================================================
-- Helper: can the current user (parent or student) see this student?
-- SECURITY DEFINER so it can read parent_links / students past RLS.
-- ============================================================================

create or replace function public.parent_can_see_student(p_student_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    exists (
      select 1 from public.parent_links
      where parent_user_id = auth.uid()
        and student_id = p_student_id
    )
    or exists (
      select 1 from public.students
      where id = p_student_id and user_id = auth.uid()
    ),
    false
  );
$$;

grant execute on function public.parent_can_see_student(uuid) to authenticated;

-- Convenience used by Flutter parent dashboard: list of student IDs visible
-- to the calling user. Returns an empty array for non-parent/non-student.
create or replace function public.my_linked_student_ids()
returns uuid[]
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    array_agg(distinct sid),
    array[]::uuid[]
  )
  from (
    select student_id as sid
      from public.parent_links
      where parent_user_id = auth.uid()
    union
    select id as sid
      from public.students
      where user_id = auth.uid()
  ) s
$$;

grant execute on function public.my_linked_student_ids() to authenticated;

-- ============================================================================
-- RLS for parent_links itself.
--   Read: super_admin, same-academy admins, the parent themselves, and the
--         linked student (if they have a login).
--   Write: admin-or-higher only.
-- ============================================================================

alter table public.parent_links enable row level security;

create policy parent_links_read on public.parent_links
  for select using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and (
        public.has_admin_or_higher()
        or parent_user_id = auth.uid()
        or exists (
          select 1 from public.students s
          where s.id = parent_links.student_id and s.user_id = auth.uid()
        )
      )
    )
  );

create policy parent_links_admin_insert on public.parent_links
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create policy parent_links_admin_update on public.parent_links
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  )
  with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create policy parent_links_admin_delete on public.parent_links
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create trigger trg_audit_parent_links
  after insert or update or delete on public.parent_links
  for each row execute function public.write_audit_log();

-- ============================================================================
-- Narrow read policies on student-keyed tables for parent/student roles.
--
-- Pattern per table:
--   drop existing *_academy_read,
--   recreate with extra clause: if role is parent/student, only allow rows
--   where parent_can_see_student(student_id) is true.
--
-- Non-restricted roles keep their academy-wide visibility.
-- ============================================================================

-- students -----------------------------------------------------------------
drop policy students_academy_read on public.students;

create policy students_academy_read on public.students
  for select using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and (
        public.current_user_role() not in ('parent', 'student')
        or public.parent_can_see_student(id)
      )
    )
  );

-- batch_enrollments --------------------------------------------------------
drop policy enrollments_academy_read on public.batch_enrollments;

create policy enrollments_academy_read on public.batch_enrollments
  for select using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and (
        public.current_user_role() not in ('parent', 'student')
        or public.parent_can_see_student(student_id)
      )
    )
  );

-- attendance_records -------------------------------------------------------
drop policy attendance_academy_read on public.attendance_records;

create policy attendance_academy_read on public.attendance_records
  for select using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and (
        public.current_user_role() not in ('parent', 'student')
        or public.parent_can_see_student(student_id)
      )
    )
  );

-- performance_assessments --------------------------------------------------
drop policy perf_assess_academy_read on public.performance_assessments;

create policy perf_assess_academy_read on public.performance_assessments
  for select using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and (
        public.current_user_role() not in ('parent', 'student')
        or public.parent_can_see_student(student_id)
      )
    )
  );

-- performance_skills -------------------------------------------------------
drop policy perf_skills_academy_read on public.performance_skills;

create policy perf_skills_academy_read on public.performance_skills
  for select using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and (
        public.current_user_role() not in ('parent', 'student')
        or public.parent_can_see_student(student_id)
      )
    )
  );

-- performance_media --------------------------------------------------------
drop policy perf_media_academy_read on public.performance_media;

create policy perf_media_academy_read on public.performance_media
  for select using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and (
        public.current_user_role() not in ('parent', 'student')
        or public.parent_can_see_student(student_id)
      )
    )
  );

-- invoices -----------------------------------------------------------------
drop policy invoices_academy_read on public.invoices;

create policy invoices_academy_read on public.invoices
  for select using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and (
        public.current_user_role() not in ('parent', 'student')
        or public.parent_can_see_student(student_id)
      )
    )
  );

-- invoice_line_items (no student_id; check via parent_link of the invoice's
-- student, but the FK chain costs a join — gate via the parent invoice's
-- visibility via an exists subquery)
drop policy invoice_lines_academy_read on public.invoice_line_items;

create policy invoice_lines_academy_read on public.invoice_line_items
  for select using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and (
        public.current_user_role() not in ('parent', 'student')
        or exists (
          select 1 from public.invoices i
          where i.id = invoice_line_items.invoice_id
            and public.parent_can_see_student(i.student_id)
        )
      )
    )
  );

-- payments -----------------------------------------------------------------
drop policy payments_academy_read on public.payments;

create policy payments_academy_read on public.payments
  for select using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and (
        public.current_user_role() not in ('parent', 'student')
        or public.parent_can_see_student(student_id)
      )
    )
  );
