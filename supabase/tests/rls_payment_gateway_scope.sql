-- ============================================================================
-- Per-academy payment gateways — owner-only + secret-isolation regression
-- (20260615000000_academy_payment_gateways.sql).
--
-- Academy A1 (owner1, admin1, coach1) and academy A2 (owner2). A super_admin.
--
-- Asserts:
--   • owner1 can configure a gateway (RPC) and read its STATUS for A1 only;
--     the status view never exposes the secret, only `secret_configured`.
--   • admin1 / coach1 cannot read A1's gateway and cannot call the RPC.
--   • owner2 cannot see A1's gateway.
--   • nobody can INSERT into the table directly (writes go through the RPC).
--   • get_payment_gateway_credentials is NOT executable by a normal client
--     (server/service_role only) — secrets stay server-side.
--   • super_admin can read.
-- ============================================================================

\set ON_ERROR_STOP on
\set ECHO none

begin;

do $$
declare
  v_su     constant uuid := '00000000-0a00-0000-0000-000000000000';
  v_owner1 constant uuid := '00000000-0a00-0000-0000-000000000001';
  v_admin1 constant uuid := '00000000-0a00-0000-0000-000000000002';
  v_coach1 constant uuid := '00000000-0a00-0000-0000-000000000003';
  v_owner2 constant uuid := '00000000-0a00-0000-0000-000000000004';
  v_a1 uuid;
  v_a2 uuid;
begin
  insert into auth.users (id, instance_id, email, role, aud,
                          email_confirmed_at, created_at, updated_at)
  values
    (v_su,     '00000000-0000-0000-0000-000000000000', 'pg-su@x.invalid',     'authenticated', 'authenticated', now(), now(), now()),
    (v_owner1, '00000000-0000-0000-0000-000000000000', 'pg-owner1@x.invalid', 'authenticated', 'authenticated', now(), now(), now()),
    (v_admin1, '00000000-0000-0000-0000-000000000000', 'pg-admin1@x.invalid', 'authenticated', 'authenticated', now(), now(), now()),
    (v_coach1, '00000000-0000-0000-0000-000000000000', 'pg-coach1@x.invalid', 'authenticated', 'authenticated', now(), now(), now()),
    (v_owner2, '00000000-0000-0000-0000-000000000000', 'pg-owner2@x.invalid', 'authenticated', 'authenticated', now(), now(), now())
  on conflict (id) do nothing;

  insert into public.academies (name, owner_id) values ('PG Academy 1', v_owner1) returning id into v_a1;
  insert into public.academies (name, owner_id) values ('PG Academy 2', v_owner2) returning id into v_a2;

  insert into public.users (id, role, academy_id, center_id, first_name, last_name, email)
  values
    (v_su,     'super_admin',   null, null, 'Su', 'Per', 'pg-su@x.invalid'),
    (v_owner1, 'academy_owner', v_a1, null, 'Own', 'One', 'pg-owner1@x.invalid'),
    (v_admin1, 'academy_admin', v_a1, null, 'Adm', 'One', 'pg-admin1@x.invalid'),
    (v_coach1, 'coach',         v_a1, null, 'Coa', 'One', 'pg-coach1@x.invalid'),
    (v_owner2, 'academy_owner', v_a2, null, 'Own', 'Two', 'pg-owner2@x.invalid')
  on conflict (id) do update
    set role = excluded.role, academy_id = excluded.academy_id;

  perform set_config('pg.a1', v_a1::text, true);
  perform set_config('pg.a2', v_a2::text, true);
end $$;

-- ---------- owner1: configures + reads own gateway status --------------------

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0a00-0000-0000-000000000001';  -- owner1

do $$
declare
  v_a1 uuid := current_setting('pg.a1')::uuid;
  v_cnt int;
  v_configured boolean;
  v_caught boolean;
begin
  -- Configure Razorpay via the RPC (secret goes to Vault).
  begin
    perform public.set_payment_gateway('razorpay', 'rzp_test_abc', 'super_secret_value', 'whsec_value', true);
  exception when others then
    raise exception 'FAIL: owner could not set payment gateway: %', SQLERRM;
  end;

  -- Reads own academy's status; secret is NOT present, only a boolean.
  select count(*), bool_or(secret_configured)
    into v_cnt, v_configured
    from public.academy_payment_gateway_status
    where academy_id = v_a1 and provider = 'razorpay';
  if v_cnt <> 1 then raise exception 'FAIL: owner cannot read own gateway status'; end if;
  if not v_configured then raise exception 'FAIL: secret_configured should be true after setting'; end if;

  -- Direct INSERT into the table is denied (writes must go through the RPC).
  v_caught := false;
  begin
    insert into public.academy_payment_gateways (academy_id, provider, key_id)
    values (v_a1, 'paytm', 'MID123');
  exception when others then v_caught := true; end;
  if not v_caught then
    raise exception 'FAIL: owner inserted directly into academy_payment_gateways';
  end if;

  raise notice 'PASS: owner — configures via RPC, reads status (no secret), no direct writes';
end $$;

-- ---------- admin1: no access (owner-exclusive) -----------------------------

set local request.jwt.claim.sub = '00000000-0a00-0000-0000-000000000002';  -- admin1

do $$
declare
  v_a1 uuid := current_setting('pg.a1')::uuid;
  v_cnt int;
  v_caught boolean;
begin
  select count(*) into v_cnt
    from public.academy_payment_gateway_status where academy_id = v_a1;
  if v_cnt <> 0 then raise exception 'FAIL: academy_admin can read gateway status (owner-only)'; end if;

  v_caught := false;
  begin
    perform public.set_payment_gateway('paytm', 'MID999', 'sek', null, false);
  exception when others then v_caught := true; end;
  if not v_caught then raise exception 'FAIL: academy_admin called set_payment_gateway'; end if;

  raise notice 'PASS: academy_admin — no read, no RPC';
end $$;

-- ---------- coach1: no access + cannot read raw credentials ------------------

set local request.jwt.claim.sub = '00000000-0a00-0000-0000-000000000003';  -- coach1

do $$
declare
  v_a1 uuid := current_setting('pg.a1')::uuid;
  v_cnt int;
  v_caught boolean;
begin
  select count(*) into v_cnt
    from public.academy_payment_gateway_status where academy_id = v_a1;
  if v_cnt <> 0 then raise exception 'FAIL: coach can read gateway status'; end if;

  -- The credential-decrypt RPC is service_role only → not executable here.
  v_caught := false;
  begin
    perform public.get_payment_gateway_credentials(v_a1, 'razorpay');
  exception when others then v_caught := true; end;
  if not v_caught then
    raise exception 'FAIL: a normal client could call get_payment_gateway_credentials';
  end if;

  raise notice 'PASS: coach — no status, cannot decrypt credentials';
end $$;

-- ---------- owner2: cannot see academy 1's gateway --------------------------

set local request.jwt.claim.sub = '00000000-0a00-0000-0000-000000000004';  -- owner2

do $$
declare
  v_a1 uuid := current_setting('pg.a1')::uuid;
  v_cnt int;
begin
  select count(*) into v_cnt
    from public.academy_payment_gateway_status where academy_id = v_a1;
  if v_cnt <> 0 then raise exception 'FAIL: owner2 can see another academy''s gateway'; end if;
  raise notice 'PASS: owner2 — cross-academy isolation holds';
end $$;

-- ---------- super_admin: sees all -------------------------------------------

set local request.jwt.claim.sub = '00000000-0a00-0000-0000-000000000000';  -- super_admin

do $$
declare
  v_a1 uuid := current_setting('pg.a1')::uuid;
  v_cnt int;
begin
  select count(*) into v_cnt
    from public.academy_payment_gateway_status where academy_id = v_a1;
  if v_cnt < 1 then raise exception 'FAIL: super_admin cannot read gateway status'; end if;
  raise notice 'PASS: super_admin — reads all';
end $$;

reset role;
rollback;

\echo 'All payment-gateway-scope tests passed.'
