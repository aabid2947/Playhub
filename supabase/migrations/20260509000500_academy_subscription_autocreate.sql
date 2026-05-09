-- ============================================================================
-- Sprint 5 — Auto-create an academy_subscriptions row whenever a new academy
-- is created (via bootstrap_owner_academy or super_admin insert). New
-- academies start on the `basic` plan with the same trial window as before.
-- ============================================================================

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
    coalesce(new.trial_ends_at, now() + interval '1 month'),
    new.trial_ends_at
  )
  on conflict (academy_id) do nothing;

  return new;
end;
$$;

create trigger trg_academies_ensure_subscription
  after insert on public.academies
  for each row execute function public.ensure_academy_subscription();
