-- ============================================================================
-- Trial usage quotas — cap what a FREE-TRIAL academy may create.
--
-- During the 14-day free trial (academies.subscription_status = 'trial') an
-- academy is limited to:
--     • 1 sport            (distinct sport across the academy)
--     • 1 head_coach login · 1 coach login · 1 trainer login
--     • 2 coach RECORDS    (the `coaches` roster = 1 head coach + 1 coach)
--     • 5 students
-- The caps LIFT the moment the academy goes paid (status 'active'/'past_due').
--
-- This is the v1.1 "real enforcement" the soft caps deferred
-- (20260509000200_saas_billing.sql:42). It is INDEPENDENT of the plan's
-- max_students/max_coaches columns (those stay soft UI hints) AND independent of
-- the subscription read-only-freeze layer (20260627*): the caps are added as
-- standalone RESTRICTIVE policies, so they compose with whatever permissive
-- INSERT policies already exist WITHOUT this migration having to know, reproduce,
-- or depend on them (no academy_writes_allowed() reference).
--
-- ---- design notes (read before editing) -----------------------------------
-- 1. RESTRICTIVE policies. Postgres AND-s every restrictive policy with the OR
--    of the permissive ones, so these only ever ADD a constraint — existing
--    create permissions are untouched. service_role (BYPASSRLS) and the table
--    owner skip RLS entirely; super_admin passes because academy_on_trial() is
--    false for them (no academy → the trial lookup finds nothing).
-- 2. INSERT-ONLY. The caps gate INSERT only — editing/soft-deleting existing
--    trial rows must always stay possible.
-- 3. SELF-REFERENCE. An INSERT WITH CHECK subquery can already see the row being
--    inserted, so every helper EXCLUDES the new row by id (`id <> p_row_id`) and
--    compares the count of *existing* rows with `< N` — unambiguous boundary.
-- 4. STAFF LOGINS bypass this RLS — invite-user creates them via the service
--    role (auth trigger = SECURITY DEFINER). The real cap for invited staff is
--    enforced in the invite-user edge function via trial_role_quota_ok();
--    trial_allows_user_role() below is the backstop for any direct users insert.
--
-- Mirror: apps/mobile/lib/features/subscription/data/trial_limits.dart holds the
-- same numbers for client-side button-greying. Keep both in sync (RLS is the
-- real gate; the client mirror only hides entry points early).
-- ============================================================================

-- True when the caller's academy is on a free trial.
create or replace function public.academy_on_trial()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.academies a
    where a.id = public.current_user_academy_id()
      and a.subscription_status = 'trial'
  );
$$;

grant execute on function public.academy_on_trial() to authenticated;

-- ---- students: max 5 -------------------------------------------------------
create or replace function public.trial_allows_student(
  p_academy_id uuid,
  p_row_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select not public.academy_on_trial()
    or (
      select count(*) from public.students s
      where s.academy_id = p_academy_id
        and s.id <> p_row_id
    ) < 5;
$$;

grant execute on function public.trial_allows_student(uuid, uuid) to authenticated;

-- ---- coach RECORDS: max 2 (1 head coach + 1 coach) -------------------------
create or replace function public.trial_allows_coach(
  p_academy_id uuid,
  p_row_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select not public.academy_on_trial()
    or (
      select count(*) from public.coaches c
      where c.academy_id = p_academy_id
        and c.id <> p_row_id
    ) < 2;
$$;

grant execute on function public.trial_allows_coach(uuid, uuid) to authenticated;

-- ---- sports: 1 DISTINCT sport across the academy (via center_sports) -------
-- A new row is allowed when the academy already offers this sport (re-enabling
-- it at another center) OR currently offers zero sports.
create or replace function public.trial_allows_center_sport(
  p_academy_id uuid,
  p_sport_id uuid,
  p_row_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select not public.academy_on_trial()
    or exists (
      select 1 from public.center_sports cs
      where cs.academy_id = p_academy_id
        and cs.sport_id = p_sport_id
        and cs.id <> p_row_id
    )
    or (
      select count(distinct cs.sport_id) from public.center_sports cs
      where cs.academy_id = p_academy_id
        and cs.id <> p_row_id
    ) < 1;
$$;

grant execute on function public.trial_allows_center_sport(uuid, uuid, uuid) to authenticated;

-- ---- staff logins: head_coach / coach / trainer = 1 each -------------------
-- Backstop for direct users inserts (the primary path is invite-user, which is
-- service-role and bypasses RLS — see trial_role_quota_ok below).
create or replace function public.trial_allows_user_role(
  p_academy_id uuid,
  p_role public.user_role,
  p_row_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select not public.academy_on_trial()
    or p_role not in ('head_coach', 'coach', 'trainer')
    or (
      select count(*) from public.users u
      where u.academy_id = p_academy_id
        and u.role = p_role
        and u.id <> p_row_id
    ) < 1;
$$;

grant execute on function public.trial_allows_user_role(uuid, public.user_role, uuid) to authenticated;

-- Invite-path quota: counts EXISTING users of the role in the caller's own
-- academy (the invitee does not exist yet, so no row to exclude). Academy is
-- taken from current_user_academy_id() so it can't be spoofed by the caller.
create or replace function public.trial_role_quota_ok(p_role public.user_role)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select not public.academy_on_trial()
    or p_role not in ('head_coach', 'coach', 'trainer')
    or (
      select count(*) from public.users u
      where u.academy_id = public.current_user_academy_id()
        and u.role = p_role
    ) < 1;
$$;

grant execute on function public.trial_role_quota_ok(public.user_role) to authenticated;

-- ============================================================================
-- RESTRICTIVE policies — AND-ed on top of the existing permissive INSERT
-- policies. Drop-if-exists first so the migration is re-runnable.
-- ============================================================================

drop policy if exists trial_quota_students_insert on public.students;
create policy trial_quota_students_insert on public.students
  as restrictive
  for insert
  with check (public.trial_allows_student(academy_id, id));

drop policy if exists trial_quota_coaches_insert on public.coaches;
create policy trial_quota_coaches_insert on public.coaches
  as restrictive
  for insert
  with check (public.trial_allows_coach(academy_id, id));

drop policy if exists trial_quota_center_sports_insert on public.center_sports;
create policy trial_quota_center_sports_insert on public.center_sports
  as restrictive
  for insert
  with check (public.trial_allows_center_sport(academy_id, sport_id, id));

drop policy if exists trial_quota_users_insert on public.users;
create policy trial_quota_users_insert on public.users
  as restrictive
  for insert
  with check (public.trial_allows_user_role(academy_id, role, id));

-- academy_sports: canonical (20260510000100) but missing on some drifted DBs,
-- so its helper + restrictive policy are created only where the table exists.
-- (The center_sports cap above is what enforces "1 sport" for the app, which
-- never writes academy_sports.)
do $guard$
begin
  if to_regclass('public.academy_sports') is not null then
    execute $fn$
      create or replace function public.trial_allows_academy_sport(
        p_academy_id uuid,
        p_row_id uuid
      )
      returns boolean
      language sql
      stable
      security definer
      set search_path = public
      as $body$
        select not public.academy_on_trial()
          or (
            select count(*) from public.academy_sports a
            where a.academy_id = p_academy_id
              and a.id <> p_row_id
          ) < 1;
      $body$;
    $fn$;
    execute 'grant execute on function '
      || 'public.trial_allows_academy_sport(uuid, uuid) to authenticated';

    execute 'drop policy if exists trial_quota_academy_sports_insert '
      || 'on public.academy_sports';
    execute $pol$
      create policy trial_quota_academy_sports_insert on public.academy_sports
        as restrictive
        for insert
        with check (public.trial_allows_academy_sport(academy_id, id));
    $pol$;
  end if;
end
$guard$;
