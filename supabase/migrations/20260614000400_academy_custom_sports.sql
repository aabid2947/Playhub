-- ============================================================================
-- Academy-scoped custom sports — let a center_admin (or admin tier) CREATE a new
-- sport name, not just pick from the global catalog.
--
-- `sports` was a single global catalog, super_admin-write only, read by everyone
-- (`using (true)`). We add a nullable `academy_id`:
--   * academy_id IS NULL  → global catalog sport (super_admin curated, seen by all)
--   * academy_id = X      → X's private custom sport (created in-app, seen only by X)
--
-- Reads are tightened so one academy's custom sports never leak into another's
-- pickers. The global `code` UNIQUE is relaxed to "unique within scope" so two
-- academies can both coin e.g. `frisbee` without colliding with each other or
-- the global catalog.
-- ============================================================================

alter table public.sports
  add column academy_id uuid references public.academies(id) on delete cascade;

-- Relax the global UNIQUE(code): global codes stay unique among themselves;
-- per-academy codes are unique within that academy.
alter table public.sports drop constraint sports_code_key;
create unique index uq_sports_code_global
  on public.sports(code) where academy_id is null;
create unique index uq_sports_code_academy
  on public.sports(academy_id, code) where academy_id is not null;
create index idx_sports_academy
  on public.sports(academy_id) where academy_id is not null;

-- Tighten read: global catalog + the caller's own academy (super_admin sees all).
drop policy sports_authenticated_read on public.sports;
create policy sports_read on public.sports
  for select to authenticated using (
    public.is_super_admin()
    or academy_id is null
    or academy_id = public.current_user_academy_id()
  );

-- super_admin keeps full write via the existing sports_super_admin_write (global
-- catalog). Add academy-scoped create/edit for owner/admin/center_admin — they
-- may only touch THEIR academy's custom sports, never the global catalog.
create policy sports_academy_insert on public.sports
  for insert to authenticated with check (
    academy_id is not null
    and academy_id = public.current_user_academy_id()
    and public.current_user_role() in (
      'academy_owner', 'academy_admin', 'center_admin'
    )
  );

create policy sports_academy_update on public.sports
  for update to authenticated using (
    academy_id is not null
    and academy_id = public.current_user_academy_id()
    and public.current_user_role() in (
      'academy_owner', 'academy_admin', 'center_admin'
    )
  ) with check (
    academy_id is not null
    and academy_id = public.current_user_academy_id()
    and public.current_user_role() in (
      'academy_owner', 'academy_admin', 'center_admin'
    )
  );

-- Deletes stay super_admin-only (sports_super_admin_write) — academies deactivate
-- a custom sport via is_active rather than hard-deleting (it may be referenced by
-- batches/students). center_sports is the per-center enable/disable toggle.
