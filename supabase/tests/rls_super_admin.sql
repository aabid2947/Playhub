-- ============================================================================
-- Super-admin RLS regression test
--
-- The web-admin console (apps/web-admin) is an RLS-RESPECTING client: a
-- super-admin signs in and every query rides on is_super_admin(). This test
-- pins the exact platform-operator behaviour the console relies on:
--   * a super-admin sees EVERY academy / ticket / invoice / user (cross-tenant)
--   * a super-admin can write academies + subscription_plans platform-wide
--   * a NON-super-admin (academy_owner) is confined to their own academy and
--     cannot write subscription_plans
--
-- The whole script runs in a transaction and rolls back, so re-running is
-- idempotent and it never pollutes local data.
--
-- Run locally:
--   psql "$(supabase status -o env | grep DB_URL | cut -d= -f2 | tr -d \")" \
--        -f supabase/tests/rls_super_admin.sql
-- ============================================================================

\set ON_ERROR_STOP on
\set ECHO none

begin;

-- ---------- Setup (as service role / superuser) -----------------------------

do $$
declare
  v_super    constant uuid := '00000000-5555-0000-0000-000000000099';
  v_owner_a  constant uuid := '00000000-aaaa-0000-0000-0000000000a1';
  v_owner_b  constant uuid := '00000000-bbbb-0000-0000-0000000000b1';
  v_academy_a uuid;
  v_academy_b uuid;
  v_sub_a uuid;
  v_sub_b uuid;
begin
  insert into auth.users (id, instance_id, email, role, aud,
                          email_confirmed_at, created_at, updated_at)
  values
    (v_super,   '00000000-0000-0000-0000-000000000000',
     'sa-test-super@example.invalid', 'authenticated', 'authenticated',
     now(), now(), now()),
    (v_owner_a, '00000000-0000-0000-0000-000000000000',
     'sa-test-a@example.invalid', 'authenticated', 'authenticated',
     now(), now(), now()),
    (v_owner_b, '00000000-0000-0000-0000-000000000000',
     'sa-test-b@example.invalid', 'authenticated', 'authenticated',
     now(), now(), now())
  on conflict (id) do nothing;

  -- The auth trigger creates stub public.users rows; upsert to set roles.
  insert into public.users (id, role, first_name, last_name, email)
  values
    (v_super,   'super_admin',   'Plat', 'Admin', 'sa-test-super@example.invalid'),
    (v_owner_a, 'academy_owner', 'Owner', 'A',    'sa-test-a@example.invalid'),
    (v_owner_b, 'academy_owner', 'Owner', 'B',    'sa-test-b@example.invalid')
  on conflict (id) do update
    set role = excluded.role, first_name = excluded.first_name;

  insert into public.academies (name, owner_id)
  values ('SA Test Academy A', v_owner_a) returning id into v_academy_a;
  insert into public.academies (name, owner_id)
  values ('SA Test Academy B', v_owner_b) returning id into v_academy_b;

  update public.users set academy_id = v_academy_a where id = v_owner_a;
  update public.users set academy_id = v_academy_b where id = v_owner_b;

  -- ensure_academy_subscription trigger auto-creates a Basic-plan subscription.
  select id into v_sub_a from public.academy_subscriptions where academy_id = v_academy_a;
  select id into v_sub_b from public.academy_subscriptions where academy_id = v_academy_b;

  insert into public.saas_invoices (
    academy_id, subscription_id, invoice_number, amount, tax_amount,
    period_start, period_end, due_date, issued_at, status)
  values
    (v_academy_a, v_sub_a, 'SA-A-0001', 1000, 180,
     now(), now() + interval '30 days', now() + interval '7 days', now(), 'issued'),
    (v_academy_b, v_sub_b, 'SA-B-0001', 2000, 360,
     now(), now() + interval '30 days', now() + interval '7 days', now(), 'issued');

  insert into public.support_tickets (academy_id, subject, body, priority, status, opened_by)
  values
    (v_academy_a, 'A needs help', 'body A', 'normal', 'open', v_owner_a),
    (v_academy_b, 'B needs help', 'body B', 'high',   'open', v_owner_b);

  perform set_config('test.super',     v_super::text,     true);
  perform set_config('test.owner_a',   v_owner_a::text,   true);
  perform set_config('test.academy_a', v_academy_a::text, true);
  perform set_config('test.academy_b', v_academy_b::text, true);

  raise notice '[setup] super=% academyA=% academyB=%', v_super, v_academy_a, v_academy_b;
end $$;

-- ===========================================================================
-- AS SUPER-ADMIN
-- ===========================================================================
set local role authenticated;
select set_config('request.jwt.claim.sub', current_setting('test.super'), true);

do $$
declare
  v_academy_b uuid := current_setting('test.academy_b')::uuid;
  v_flag boolean;
  v_n int;
begin
  select public.is_super_admin() into v_flag;
  if not v_flag then raise exception 'FAIL: is_super_admin() false for the super-admin'; end if;
  raise notice 'PASS: is_super_admin() true for super-admin';

  -- Sees BOTH test academies (cross-tenant read).
  select count(*) into v_n from public.academies
   where id = ANY (array[current_setting('test.academy_a')::uuid, v_academy_b]);
  if v_n <> 2 then raise exception 'FAIL: super-admin saw % of 2 academies', v_n; end if;
  raise notice 'PASS: super-admin reads all academies (cross-tenant)';

  -- Sees academy B's support ticket.
  select count(*) into v_n from public.support_tickets where academy_id = v_academy_b;
  if v_n <> 1 then raise exception 'FAIL: super-admin saw % tickets for academy B', v_n; end if;
  raise notice 'PASS: super-admin reads cross-tenant support tickets';

  -- Sees academy B's saas invoice.
  select count(*) into v_n from public.saas_invoices where academy_id = v_academy_b;
  if v_n <> 1 then raise exception 'FAIL: super-admin saw % invoices for academy B', v_n; end if;
  raise notice 'PASS: super-admin reads cross-tenant saas_invoices';

  -- Sees academy B's owner user row.
  select count(*) into v_n from public.users where academy_id = v_academy_b;
  if v_n < 1 then raise exception 'FAIL: super-admin could not read academy B users'; end if;
  raise notice 'PASS: super-admin reads cross-tenant users';

  -- Can toggle academy B active flag (cross-tenant write).
  update public.academies set is_active = false where id = v_academy_b;
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception 'FAIL: super-admin could not toggle academy B (% rows)', v_n; end if;
  raise notice 'PASS: super-admin writes academies platform-wide';

  -- Can write subscription_plans.
  update public.subscription_plans set is_active = is_active;
  get diagnostics v_n = row_count;
  if v_n < 1 then raise exception 'FAIL: super-admin could not write subscription_plans'; end if;
  raise notice 'PASS: super-admin writes subscription_plans (% rows)', v_n;
end $$;

-- ===========================================================================
-- AS NON-SUPER-ADMIN academy_owner (Academy A)
-- ===========================================================================
select set_config('request.jwt.claim.sub', current_setting('test.owner_a'), true);

do $$
declare
  v_academy_b uuid := current_setting('test.academy_b')::uuid;
  v_flag boolean;
  v_n int;
begin
  select public.is_super_admin() into v_flag;
  if v_flag then raise exception 'FAIL: is_super_admin() true for an academy_owner'; end if;
  raise notice 'PASS: is_super_admin() false for academy_owner';

  -- Cannot see academy B.
  select count(*) into v_n from public.academies where id = v_academy_b;
  if v_n <> 0 then raise exception 'FAIL: owner A saw academy B (% rows)', v_n; end if;
  raise notice 'PASS: academy_owner cannot read other academies';

  -- Cannot see academy B's tickets.
  select count(*) into v_n from public.support_tickets where academy_id = v_academy_b;
  if v_n <> 0 then raise exception 'FAIL: owner A saw academy B tickets (% rows)', v_n; end if;
  raise notice 'PASS: academy_owner cannot read other academies'' tickets';

  -- Cannot see academy B's invoices.
  select count(*) into v_n from public.saas_invoices where academy_id = v_academy_b;
  if v_n <> 0 then raise exception 'FAIL: owner A saw academy B invoices (% rows)', v_n; end if;
  raise notice 'PASS: academy_owner cannot read other academies'' invoices';

  -- Cannot write subscription_plans — RLS filters the UPDATE to 0 rows.
  update public.subscription_plans set is_active = false;
  get diagnostics v_n = row_count;
  if v_n <> 0 then raise exception 'FAIL: academy_owner wrote % subscription_plans rows', v_n; end if;
  raise notice 'PASS: academy_owner cannot write subscription_plans';
end $$;

reset role;

do $$ begin raise notice 'ALL SUPER-ADMIN RLS ASSERTIONS PASSED'; end $$;

rollback;
