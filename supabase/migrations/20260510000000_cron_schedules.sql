-- ============================================================================
-- Sprint 5 follow-up — schedule the new cron Edge Functions via pg_cron.
--
-- Times are scheduled in UTC (pg_cron's clock). Conversions:
--   - recur-saas-billing                  → 02:30 IST  ≡ 21:00 UTC prev day
--   - subscription-grace-period-check     → 03:30 IST  ≡ 22:00 UTC prev day
--   - analytics-aggregations              → hourly
--
-- Auth model: each Edge Function accepts a service-role Bearer token (per
-- _shared/cors.ts → authoriseCron). The Bearer token is read out of
-- vault.decrypted_secrets under the conventional key 'service_role_key',
-- which Supabase projects typically pre-populate. If your vault does not
-- have it yet, run once (replace with your project's service-role key):
--
--   select vault.create_secret('<service-role-key>', 'service_role_key');
--
-- Idempotent: existing schedules with the same job name are unscheduled
-- first so reruns are safe.
-- ============================================================================

create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;

-- Wrapper that posts to a function URL with the service-role bearer token.
create or replace function public.cron_invoke_function(p_path text)
returns void
language plpgsql
security definer
set search_path = public, extensions, vault
as $$
declare
  v_token text;
  v_base text := 'https://hrawgduftgslwsdgzliy.supabase.co/functions/v1/';
begin
  select decrypted_secret into v_token
    from vault.decrypted_secrets
    where name = 'service_role_key'
    limit 1;

  perform net.http_post(
    url := v_base || p_path,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || coalesce(v_token, '')
    ),
    body := '{}'::jsonb
  );
end;
$$;

-- Idempotent reschedule helper.
create or replace function public.reschedule_cron(
  p_jobname text, p_schedule text, p_command text
)
returns void
language plpgsql
as $$
declare
  v_existing bigint;
begin
  select jobid into v_existing
    from cron.job where jobname = p_jobname;
  if v_existing is not null then
    perform cron.unschedule(v_existing);
  end if;
  perform cron.schedule(p_jobname, p_schedule, p_command);
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. recur-saas-billing — once daily ~02:30 IST (21:00 UTC prev day)
-- ---------------------------------------------------------------------------
select public.reschedule_cron(
  'recur-saas-billing-daily',
  '0 21 * * *',
  $cmd$ select public.cron_invoke_function('recur-saas-billing'); $cmd$
);

-- ---------------------------------------------------------------------------
-- 2. subscription-grace-period-check — once daily ~03:30 IST (22:00 UTC prev day)
-- ---------------------------------------------------------------------------
select public.reschedule_cron(
  'subscription-grace-period-check-daily',
  '0 22 * * *',
  $cmd$ select public.cron_invoke_function('subscription-grace-period-check'); $cmd$
);

-- ---------------------------------------------------------------------------
-- 3. analytics-aggregations — hourly at minute 0
-- ---------------------------------------------------------------------------
select public.reschedule_cron(
  'analytics-aggregations-hourly',
  '0 * * * *',
  $cmd$ select public.cron_invoke_function('analytics-aggregations'); $cmd$
);
