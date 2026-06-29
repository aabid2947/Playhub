-- ============================================================================
-- REPAIR: restore the public.academy_sports table.
--
-- This table is part of the canonical schema (created in
-- 20260510000100_sports_catalog.sql alongside coach_sports + sport_skills), but
-- it was manually dropped on at least one deployment. Its absence blocks
-- apply_subscription_enforcement_20260627.sql (which drops/recreates the
-- academy_sports policies) and the trial-quota migration.
--
-- Idempotent: safe to run whether or not the table already exists. DDL is
-- reproduced verbatim from 20260510000100 (table + index + RLS + the four
-- original policies + audit trigger), with `if not exists` / `drop ... if
-- exists` guards added so it can also run on a DB that already has it.
-- ============================================================================

create table if not exists public.academy_sports (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies(id) on delete cascade,
  sport_id uuid not null references public.sports(id) on delete restrict,
  custom_name text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (academy_id, sport_id)
);

create index if not exists idx_academy_sports_academy
  on public.academy_sports(academy_id);

alter table public.academy_sports enable row level security;

drop policy if exists academy_sports_member_read   on public.academy_sports;
drop policy if exists academy_sports_admin_insert   on public.academy_sports;
drop policy if exists academy_sports_admin_update   on public.academy_sports;
drop policy if exists academy_sports_admin_delete   on public.academy_sports;

create policy academy_sports_member_read on public.academy_sports
  for select using (
    public.is_super_admin()
    or academy_id = public.current_user_academy_id()
  );

create policy academy_sports_admin_insert on public.academy_sports
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create policy academy_sports_admin_update on public.academy_sports
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  )
  with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create policy academy_sports_admin_delete on public.academy_sports
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

-- Audit hook (drop-if-exists so the rerun is clean).
drop trigger if exists trg_audit_academy_sports on public.academy_sports;
create trigger trg_audit_academy_sports
  after insert or update or delete on public.academy_sports
  for each row execute function public.write_audit_log();

-- Backfill the "academy offers this sport" list from sports already in use, so
-- the restored table matches the state the rest of the schema expects.
insert into public.academy_sports (academy_id, sport_id)
select distinct s.academy_id, s.sport_id
from (
  select academy_id, sport_id from public.students                where sport_id is not null
  union
  select academy_id, sport_id from public.batches                 where sport_id is not null
  union
  select academy_id, sport_id from public.leads                   where sport_id is not null
  union
  select academy_id, sport_id from public.events                  where sport_id is not null
  union
  select academy_id, sport_id from public.performance_assessments where sport_id is not null
) s
on conflict (academy_id, sport_id) do nothing;
