-- ============================================================================
-- DB-layer regression tests for the functions, triggers, generated columns and
-- CHECK constraints that the apps depend on (the logic that lives in Postgres,
-- not in RLS). Same harness as rls_tenancy.sql: a transaction that ROLLS BACK,
-- each `do` block raises 'PASS:' on success or 'FAIL'/exception to abort.
--
-- Covered:
--   • next_invoice_number — format, monotonic, per-academy isolation
--   • invoices.amount      — generated (base+tax+late_fee−discount) + ≥0 CHECK
--   • invoice_line_items.total_amount — generated (qty × unit)
--   • inventory movement   — sign validation + on_hand denormalization trigger
--   • apply_saas_payment   — saas_invoice flips to paid
--   • ensure_academy_subscription — auto-creates exactly one basic subscription
--   • leads contact CHECK  — a lead with neither email nor phone is rejected
-- ============================================================================

\set ON_ERROR_STOP on

begin;

-- 1. next_invoice_number ------------------------------------------------------
do $$
declare a1 uuid; a2 uuid; n1 text; n2 text; m1 text;
begin
  insert into public.academies (name) values ('NIN A') returning id into a1;
  insert into public.academies (name) values ('NIN B') returning id into a2;
  n1 := public.next_invoice_number(a1);
  n2 := public.next_invoice_number(a1);
  m1 := public.next_invoice_number(a2);
  if n1 not like 'INV-%' or right(n1, 6) <> '000001' then
    raise exception 'FAIL: first number was % (expected INV-…000001)', n1;
  end if;
  if right(n2, 6) <> '000002' then
    raise exception 'FAIL: number did not advance: %', n2;
  end if;
  if right(m1, 6) <> '000001' then
    raise exception 'FAIL: counter not isolated per academy: %', m1;
  end if;
  raise notice 'PASS: next_invoice_number — format, monotonic, per-academy isolation';
end $$;

-- 2. invoices.amount generated column + amount >= 0 CHECK ---------------------
do $$
declare a uuid; s uuid; v_amount numeric; v_caught boolean := false;
begin
  insert into public.academies (name) values ('GEN') returning id into a;
  insert into public.students (academy_id, first_name, last_name, parent_name)
    values (a, 'G', 'S', 'P') returning id into s;

  insert into public.invoices
    (academy_id, student_id, invoice_number, status, base_amount, tax_amount, late_fee_amount, discount_amount, due_date)
    values (a, s, 'INV-000001', 'issued', 1000, 180, 50, 30, current_date)
    returning amount into v_amount;
  if v_amount <> 1200 then
    raise exception 'FAIL: generated amount was % (expected 1200 = 1000+180+50-30)', v_amount;
  end if;

  begin
    insert into public.invoices
      (academy_id, student_id, invoice_number, status, base_amount, discount_amount, due_date)
      values (a, s, 'INV-000002', 'issued', 100, 500, current_date);
  exception when check_violation then v_caught := true;
  end;
  if not v_caught then
    raise exception 'FAIL: an over-discounted (negative) invoice amount was allowed';
  end if;
  raise notice 'PASS: invoices.amount generated + amount>=0 CHECK';
end $$;

-- 3. invoice_line_items.total_amount generated -------------------------------
do $$
declare a uuid; s uuid; inv uuid; v_total numeric;
begin
  insert into public.academies (name) values ('LI') returning id into a;
  insert into public.students (academy_id, first_name, last_name, parent_name)
    values (a, 'L', 'S', 'P') returning id into s;
  insert into public.invoices
    (academy_id, student_id, invoice_number, status, base_amount, due_date)
    values (a, s, 'INV-000001', 'issued', 0, current_date) returning id into inv;

  insert into public.invoice_line_items
    (invoice_id, academy_id, kind, description, unit_amount, quantity)
    values (inv, a, 'base', 'x3 sessions', 250, 3)
    returning total_amount into v_total;
  if v_total <> 750 then
    raise exception 'FAIL: line total was % (expected 750 = 250×3)', v_total;
  end if;
  raise notice 'PASS: invoice_line_items.total_amount generated (qty × unit)';
end $$;

-- 4. inventory movement: sign validation + on_hand sync -----------------------
do $$
declare a uuid; it uuid; v_onhand numeric; v_caught boolean := false;
begin
  insert into public.academies (name) values ('INV') returning id into a;
  insert into public.inventory_items (academy_id, name) values (a, 'Bat') returning id into it;

  insert into public.inventory_movements (academy_id, item_id, kind, qty) values (a, it, 'in', 10);
  insert into public.inventory_movements (academy_id, item_id, kind, qty) values (a, it, 'out', -4);
  select on_hand into v_onhand from public.inventory_items where id = it;
  if v_onhand <> 6 then
    raise exception 'FAIL: on_hand was % (expected 6 = +10-4)', v_onhand;
  end if;

  begin
    insert into public.inventory_movements (academy_id, item_id, kind, qty) values (a, it, 'out', 5);
  exception when others then v_caught := true;
  end;
  if not v_caught then
    raise exception 'FAIL: a wrong-signed "out" movement (positive qty) was allowed';
  end if;
  raise notice 'PASS: inventory movement sign validation + on_hand sync';
end $$;

-- 5. apply_saas_payment: covering payment flips invoice to paid --------------
do $$
declare a uuid; sub uuid; inv uuid; v_total numeric; v_status text;
begin
  insert into public.academies (name) values ('SAAS') returning id into a;
  -- ensure_academy_subscription auto-created the row; grab it.
  select id into sub from public.academy_subscriptions where academy_id = a;
  insert into public.saas_invoices
    (academy_id, subscription_id, invoice_number, amount, tax_amount, period_start, period_end, due_date, issued_at, status)
    values (a, sub, 'SAAS-1', 1000, 0, now(), now() + interval '30 days', now() + interval '7 days', now(), 'issued')
    returning id, total_amount into inv, v_total;

  insert into public.saas_payments (academy_id, saas_invoice_id, amount, method)
    values (a, inv, v_total, 'razorpay');

  select status into v_status from public.saas_invoices where id = inv;
  if v_status <> 'paid' then
    raise exception 'FAIL: saas_invoice status was % (expected paid)', v_status;
  end if;
  raise notice 'PASS: apply_saas_payment flips a fully-paid SaaS invoice to paid';
end $$;

-- 6. ensure_academy_subscription: one basic subscription per academy ---------
do $$
declare a uuid; v_count int; v_code text;
begin
  insert into public.academies (name) values ('SUB') returning id into a;
  select count(*) into v_count from public.academy_subscriptions where academy_id = a;
  if v_count <> 1 then
    raise exception 'FAIL: academy got % subscription rows (expected exactly 1)', v_count;
  end if;
  select p.code into v_code
    from public.academy_subscriptions s join public.subscription_plans p on p.id = s.plan_id
    where s.academy_id = a;
  if v_code <> 'basic' then
    raise exception 'FAIL: auto subscription was on plan % (expected basic)', v_code;
  end if;
  raise notice 'PASS: ensure_academy_subscription auto-creates one basic subscription';
end $$;

-- 7. leads contact CHECK: neither email nor phone is rejected ----------------
do $$
declare a uuid; v_caught boolean := false;
begin
  insert into public.academies (name) values ('LEAD') returning id into a;
  begin
    insert into public.leads (academy_id, first_name) values (a, 'NoContact');
  exception when check_violation then v_caught := true;
  end;
  if not v_caught then
    raise exception 'FAIL: a lead with no email and no phone was allowed';
  end if;
  raise notice 'PASS: leads contact CHECK requires email or phone';
end $$;

do $$ begin raise notice 'All function/trigger/constraint tests passed.'; end $$;

rollback;
