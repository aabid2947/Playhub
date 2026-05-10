-- ============================================================================
-- Polish — sports become per-center, not per-academy.
--
-- An academy with multiple centers may offer different sports at each
-- (one center has the pool; another the cricket nets). The previous
-- `academy_sports` table flattened that. This migration:
--
--   * creates center_sports (center_id × sport_id),
--   * fans out each existing academy_sports row to a row per center in
--     that academy as a best-guess backfill (admin prunes after),
--   * drops academy_sports.
--
-- academy_id is denormalised onto center_sports so the existing tenant-
-- isolated read/write policies (and KPI queries) keep their cheap
-- equality filter.
-- ============================================================================

create table public.center_sports (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies(id) on delete cascade,
  center_id uuid not null references public.centers(id) on delete cascade,
  sport_id uuid not null references public.sports(id) on delete restrict,
  custom_name text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (center_id, sport_id)
);

create index idx_center_sports_academy on public.center_sports(academy_id);
create index idx_center_sports_center on public.center_sports(center_id);

alter table public.center_sports enable row level security;

create policy center_sports_member_read on public.center_sports
  for select using (
    public.is_super_admin()
    or academy_id = public.current_user_academy_id()
  );

create policy center_sports_admin_insert on public.center_sports
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create policy center_sports_admin_update on public.center_sports
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  )
  with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create policy center_sports_admin_delete on public.center_sports
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create trigger trg_audit_center_sports
  after insert or update or delete on public.center_sports
  for each row execute function public.write_audit_log();

-- ---------------------------------------------------------------------------
-- Backfill: every academy_sports row → one row per center in that academy.
-- ---------------------------------------------------------------------------
insert into public.center_sports (academy_id, center_id, sport_id, custom_name, is_active)
select c.academy_id, c.id, ash.sport_id, ash.custom_name, ash.is_active
from public.centers c
join public.academy_sports ash on ash.academy_id = c.academy_id
on conflict (center_id, sport_id) do nothing;

-- ---------------------------------------------------------------------------
-- Drop academy_sports.
-- ---------------------------------------------------------------------------
drop table public.academy_sports;
