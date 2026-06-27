-- ============================================================================
-- Subscription enforcement — Phase 1a: the write gate helper.
--
-- `academy_writes_allowed()` is the single source of truth for "may the calling
-- user's academy perform management writes right now?". It is wired into the
-- WRITE policies/helpers in a LATER migration (enforcement step) — adding it
-- here is behaviour-neutral on its own.
--
-- Allowed to write when: super_admin (always), OR the academy's subscription is
-- active / past_due (grace window still works), OR it is on trial and the trial
-- has not expired. Blocked when: trial expired, suspended, or cancelled.
--
-- Immediate trial-expiry enforcement (no cron lag) comes from the live
-- `trial_ends_at > now()` check here; the cron only flips the persisted status
-- for UI/reporting hygiene.
--
-- Read paths are NOT gated. We deliberately do NOT touch is_super_admin() or
-- current_user_academy_id() (used by SELECT policies) — reads stay open so a
-- suspended academy can still see its data and pay to unlock.
-- See SUBSCRIPTION_ENFORCEMENT.md.
-- ============================================================================

create or replace function public.academy_writes_allowed()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_super_admin() or exists (
    select 1
    from public.academies a
    where a.id = public.current_user_academy_id()
      and a.subscription_status <> 'cancelled'
      and (
        a.subscription_status in ('active', 'past_due')
        or (
          a.subscription_status = 'trial'
          and (a.trial_ends_at is null or a.trial_ends_at > now())
        )
      )
  );
$$;

comment on function public.academy_writes_allowed() is
  'True when the calling user''s academy may perform management writes: super_admin always; otherwise subscription active/past_due, or trial not yet expired. The write gate for subscription enforcement (see SUBSCRIPTION_ENFORCEMENT.md). Reads are never gated.';

-- ----------------------------------------------------------------------------
-- Consistency fix: a new academy's trial period should fall back to 14 days,
-- not 1 month, to match academies.trial_ends_at's default. In practice
-- new.trial_ends_at is always set (column default), so this only changes the
-- dead fallback branch — behaviour-neutral, kept for correctness.
-- ----------------------------------------------------------------------------
create or replace function public.ensure_academy_subscription()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_plan_id uuid;
begin
  select id into v_plan_id from public.subscription_plans where code = 'basic' limit 1;

  if v_plan_id is null then
    return new;
  end if;

  insert into public.academy_subscriptions (
    academy_id, plan_id, status,
    current_period_start, current_period_end, trial_ends_at
  )
  values (
    new.id,
    v_plan_id,
    coalesce(new.subscription_status, 'trial'),
    now(),
    coalesce(new.trial_ends_at, now() + interval '14 days'),
    new.trial_ends_at
  )
  on conflict (academy_id) do nothing;

  return new;
end;
$$;
