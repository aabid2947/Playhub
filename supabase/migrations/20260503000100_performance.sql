-- ============================================================================
-- Sprint 2 — performance assessments per SRD §3.6 / §7.1
--
-- Header table (`performance_assessments`) + child line items
-- (`performance_skills`) + media attachments (`performance_media`).
-- Each assessment is a coach's evaluation of one student on a given date.
-- ============================================================================

create table public.performance_assessments (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  batch_id uuid references public.batches(id) on delete set null,
  coach_id uuid references public.coaches(id) on delete set null,

  assessment_date date not null default current_date,
  sport text,                                   -- copied from student.sport for trend grouping
  overall_score numeric(4, 2),                  -- 0–10 composite, optional
  qualitative_feedback text,

  recorded_by uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index idx_perf_assess_academy_date
  on public.performance_assessments(academy_id, assessment_date desc);
create index idx_perf_assess_student_date
  on public.performance_assessments(student_id, assessment_date desc);
create index idx_perf_assess_batch_date
  on public.performance_assessments(batch_id, assessment_date desc);

create trigger trg_perf_assess_updated before update
  on public.performance_assessments
  for each row execute function public.set_updated_at();

-- Line items: one row per skill scored on the rubric -------------------------
create table public.performance_skills (
  id uuid primary key default gen_random_uuid(),
  assessment_id uuid not null references public.performance_assessments(id)
    on delete cascade,
  academy_id uuid not null references public.academies(id) on delete cascade,
  -- denormalised for cheap RLS + per-student trend joins
  student_id uuid not null references public.students(id) on delete cascade,

  skill_name text not null,                     -- e.g. "Footwork", "Backhand"
  score int not null check (score between 1 and 10),
  notes text,

  created_at timestamptz not null default now()
);

create index idx_perf_skills_assessment on public.performance_skills(assessment_id);
create index idx_perf_skills_student on public.performance_skills(student_id, created_at desc);
create index idx_perf_skills_academy on public.performance_skills(academy_id);

-- Media: photos / videos backing the assessment ------------------------------
create table public.performance_media (
  id uuid primary key default gen_random_uuid(),
  assessment_id uuid not null references public.performance_assessments(id)
    on delete cascade,
  academy_id uuid not null references public.academies(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,

  media_type text not null check (media_type in ('photo', 'video')),
  file_path text not null,                      -- key inside performance_media bucket
  original_filename text,
  mime_type text,
  size_bytes int,

  uploaded_by uuid references public.users(id) on delete set null,
  uploaded_at timestamptz not null default now()
);

create index idx_perf_media_assessment on public.performance_media(assessment_id);
create index idx_perf_media_student on public.performance_media(student_id);
create index idx_perf_media_academy on public.performance_media(academy_id);

-- ============================================================================
-- RLS
-- ============================================================================

alter table public.performance_assessments enable row level security;
alter table public.performance_skills      enable row level security;
alter table public.performance_media       enable row level security;

-- Reads: any authenticated user in the academy. Per-role narrowing
-- (parent sees own children, student sees self) lands when parent_links /
-- student-self-mapping ships in Sprint 4. For now, all roles in the
-- academy read everything.
create policy perf_assess_academy_read on public.performance_assessments
  for select using (
    public.is_super_admin()
    or academy_id = public.current_user_academy_id()
  );

create policy perf_skills_academy_read on public.performance_skills
  for select using (
    public.is_super_admin()
    or academy_id = public.current_user_academy_id()
  );

create policy perf_media_academy_read on public.performance_media
  for select using (
    public.is_super_admin()
    or academy_id = public.current_user_academy_id()
  );

-- Writes: coach-or-higher within their academy. Split per-action to avoid
-- the `for all using` cross-tenant read leak pattern.
create policy perf_assess_coach_insert on public.performance_assessments
  for insert with check (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.has_coach_or_higher()
    )
  );

create policy perf_assess_coach_update on public.performance_assessments
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

create policy perf_assess_admin_delete on public.performance_assessments
  for delete using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.has_admin_or_higher()
    )
  );

create policy perf_skills_coach_insert on public.performance_skills
  for insert with check (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.has_coach_or_higher()
    )
  );

create policy perf_skills_coach_update on public.performance_skills
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

create policy perf_skills_coach_delete on public.performance_skills
  for delete using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.has_coach_or_higher()
    )
  );

create policy perf_media_coach_insert on public.performance_media
  for insert with check (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.has_coach_or_higher()
    )
  );

create policy perf_media_coach_update on public.performance_media
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

create policy perf_media_coach_delete on public.performance_media
  for delete using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.has_coach_or_higher()
    )
  );

-- Audit hooks
create trigger trg_audit_performance_assessments
  after insert or update or delete on public.performance_assessments
  for each row execute function public.write_audit_log();

create trigger trg_audit_performance_skills
  after insert or update or delete on public.performance_skills
  for each row execute function public.write_audit_log();

create trigger trg_audit_performance_media
  after insert or update or delete on public.performance_media
  for each row execute function public.write_audit_log();
