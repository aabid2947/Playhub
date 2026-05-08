-- ============================================================================
-- Lead funnel — public website form lands here, kanban moves status, and
-- `convert-lead-to-student` Edge Function flips a lead into a student row.
--
-- Two tables:
--   leads             — the prospect contact + funnel state
--   lead_activities   — append-only timeline (status changes, notes, calls)
--
-- The status enum is opinionated (matches PLAN.md §3.8 kanban columns).
-- Once a lead is `converted`, leads.converted_student_id points at the
-- student row created by the convert function.
-- ============================================================================

create type public.lead_status as enum (
  'new',
  'contacted',
  'interested',
  'trial_scheduled',
  'converted',
  'lost'
);

create type public.lead_source as enum (
  'website',
  'referral',
  'walk_in',
  'instagram',
  'facebook',
  'google',
  'event',
  'other'
);

create table public.leads (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies(id) on delete cascade,

  first_name text not null,
  last_name text,
  email text,
  phone text,
  parent_name text,                  -- when prospect is a child
  age int check (age is null or age > 0),
  sport text,
  preferred_center_id uuid references public.centers(id) on delete set null,
  notes text,

  status public.lead_status not null default 'new',
  source public.lead_source not null default 'website',

  assigned_to uuid references public.users(id) on delete set null,
  next_followup_at timestamptz,
  trial_scheduled_at timestamptz,

  -- When converted, this is the resulting student. Cleared if the student
  -- is hard-deleted later.
  converted_student_id uuid references public.students(id) on delete set null,
  converted_at timestamptz,
  lost_reason text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  -- Either email or phone is required (otherwise we can't contact them).
  constraint leads_contact_present check (
    (email is not null and length(trim(email)) > 0)
    or (phone is not null and length(trim(phone)) > 0)
  )
);

create index idx_leads_academy_status on public.leads(academy_id, status);
create index idx_leads_followup
  on public.leads(academy_id, next_followup_at)
  where next_followup_at is not null and status not in ('converted', 'lost');
create index idx_leads_assigned on public.leads(assigned_to);

create trigger trg_leads_updated before update on public.leads
  for each row execute function public.set_updated_at();

-- Activities — append-only audit of what happened with a lead.
create table public.lead_activities (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies(id) on delete cascade,
  lead_id uuid not null references public.leads(id) on delete cascade,
  user_id uuid references public.users(id) on delete set null,

  kind text not null check (kind in (
    'note', 'status_change', 'call_logged', 'email_sent',
    'sms_sent', 'trial_scheduled', 'reminder_sent'
  )),
  content text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index idx_lead_activities_lead
  on public.lead_activities(lead_id, created_at desc);
create index idx_lead_activities_academy
  on public.lead_activities(academy_id, created_at desc);

-- ============================================================================
-- Auto-log status changes on leads → lead_activities
-- ============================================================================

create or replace function public.log_lead_status_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if TG_OP = 'UPDATE' and old.status is distinct from new.status then
    insert into public.lead_activities (
      academy_id, lead_id, user_id, kind, content, metadata
    ) values (
      new.academy_id,
      new.id,
      auth.uid(),
      'status_change',
      old.status::text || ' → ' || new.status::text,
      jsonb_build_object('from', old.status, 'to', new.status)
    );
  end if;
  return new;
end;
$$;

create trigger trg_leads_status_change
  after update on public.leads
  for each row execute function public.log_lead_status_change();

-- ============================================================================
-- RLS
--   Reads: any same-academy authenticated user (admin / coach use the kanban;
--          parents/students don't read this table).
--   Writes: admin-or-higher inserts/updates/deletes leads.
--   lead_activities: same shape; inserts also allowed by `public.log_*` and
--   by the convert-lead Edge Function (service-role bypass) directly.
-- ============================================================================

alter table public.leads             enable row level security;
alter table public.lead_activities   enable row level security;

create policy leads_academy_read on public.leads
  for select using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.current_user_role() not in ('parent', 'student')
    )
  );

create policy leads_admin_insert on public.leads
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create policy leads_admin_update on public.leads
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  )
  with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create policy leads_admin_delete on public.leads
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create policy lead_activities_academy_read on public.lead_activities
  for select using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.current_user_role() not in ('parent', 'student')
    )
  );

-- App-layer inserts: admin/owner can attach notes / call logs.
create policy lead_activities_admin_insert on public.lead_activities
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

-- No update / delete from app layer — activity log is append-only.

-- Audit hooks
create trigger trg_audit_leads
  after insert or update or delete on public.leads
  for each row execute function public.write_audit_log();

create trigger trg_audit_lead_activities
  after insert or update or delete on public.lead_activities
  for each row execute function public.write_audit_log();
