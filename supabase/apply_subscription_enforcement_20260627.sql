-- ============================================================================
-- COMBINED MIGRATIONS — subscription enforcement (2026-06-27)
-- Run once in the Supabase SQL editor. Wrapped in a single transaction:
-- if anything fails, NOTHING is applied (all-or-nothing).
--
-- PREREQUISITE: all migrations up to and including 20260624000000 must already
-- be applied (especially the 20260614 / 20260615 batch) — sections 2-4 below
-- create-or-replace the capability helpers + policies those migrations defined.
--
-- Order (do NOT reorder — recovery is created BEFORE enforcement so a paying
-- academy is never stranded; the gate helper must exist before it is referenced):
--   1. 20260627000000_subscription_writes_gate      (gate helper + 14d fallback)
--   2. 20260627000100_saas_auto_reactivate          (reactivate-on-payment trigger)
--   3. 20260627000200_subscription_enforce_writes   (gate the capability helpers)
--   4. 20260627000300_subscription_enforce_policies (gate the inline/direct policies)
--
-- NOTE: if your DB already has SOME of these applied, a `create trigger ...` or a
-- `drop policy ...` will error and the whole transaction rolls back. In that case
-- use `supabase db push` instead (applies only what's missing).
--
-- AFTER APPLYING:
--   • run supabase/tests/rls_subscription_enforcement.sql to verify the gate;
--   • make sure existing real academies are 'active' / fresh-trial first, or any
--     on an EXPIRED trial (trial_ends_at in the past) freeze immediately.
--   See SUBSCRIPTION_ENFORCEMENT.md for the full plan + carve-outs.
-- ============================================================================

begin;

-- ############################################################################
-- ## SECTION 1/4 : 20260627000000_subscription_writes_gate.sql
-- ############################################################################

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

-- ############################################################################
-- ## SECTION 2/4 : 20260627000100_saas_auto_reactivate.sql
-- ############################################################################

-- ============================================================================
-- Subscription enforcement — Phase 3a: auto-reactivate on full payment.
--
-- When a SaaS payment clears the last outstanding invoice for a subscription,
-- flip the subscription (and its academy) back to 'active' + is_active=true so
-- a suspended/past_due academy is unblocked automatically. This is the recovery
-- half of the enforcement loop — it MUST exist before writes are gated so a
-- paying academy is never stranded.
--
-- Pairs with apply_saas_payment() (trg_saas_payment_apply), which marks the
-- invoice 'paid'. Trigger fire order on saas_payments is by name:
--   trg_saas_payment_apply  <  trg_saas_payment_reactivate
-- so the just-paid invoice is already 'paid' when we count outstanding ones.
--
-- Super-admin can also reactivate manually via web-admin (reactivateSubscription
-- action) — e.g. a trial-expired academy that has no invoice to pay against.
-- See SUBSCRIPTION_ENFORCEMENT.md.
-- ============================================================================

create or replace function public.reactivate_paid_subscription()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_subscription_id uuid;
  v_academy_id uuid;
  v_outstanding int;
begin
  -- Resolve the subscription + academy from the invoice this payment hit.
  select si.subscription_id, si.academy_id
    into v_subscription_id, v_academy_id
  from public.saas_invoices si
  where si.id = new.saas_invoice_id;

  if v_subscription_id is null then
    return new;
  end if;

  -- Any invoice for this subscription still outstanding?
  select count(*)
    into v_outstanding
  from public.saas_invoices
  where subscription_id = v_subscription_id
    and status not in ('paid', 'cancelled');

  if v_outstanding = 0 then
    -- Only touch rows that were actually blocked (idempotent; never demotes).
    update public.academy_subscriptions
      set status = 'active'
      where id = v_subscription_id
        and status in ('past_due', 'suspended');

    update public.academies
      set subscription_status = 'active',
          is_active = true
      where id = v_academy_id
        and subscription_status in ('past_due', 'suspended');
  end if;

  return new;
end;
$$;

create trigger trg_saas_payment_reactivate
  after insert on public.saas_payments
  for each row execute function public.reactivate_paid_subscription();

-- ############################################################################
-- ## SECTION 3/4 : 20260627000200_subscription_enforce_writes.sql
-- ############################################################################

-- ============================================================================
-- Subscription enforcement — Phase 1b: gate the capability WRITE helpers.
--
-- Wraps each WRITE-ONLY capability helper with academy_writes_allowed() so that
-- a suspended / trial-expired academy can no longer create/edit/delete content.
-- The helper pattern is `is_super_admin() OR (academy match AND can_X(...))` in
-- the policies, so:
--   • super_admin still passes (the policy's is_super_admin() branch, and
--     academy_writes_allowed() also returns true for super_admin).
--   • a normal user in a suspended academy → can_X() now returns false → blocked.
--   • READS are untouched (these can_* helpers appear only in write policies).
--
-- IMPORTANT — can_admin_center_scope() is NOT gated here: it is reused inside the
-- READ gate can_view_student_finance() (20260607000400), so gating it would block
-- finance READS. Finance WRITES are instead gated via the write-only delegators
-- can_manage_finance / can_manage_invoice / can_manage_batch_finance below. The
-- handful of WRITE policies that call can_admin_center_scope() directly
-- (students_update coach branch, leads, inventory_items, fee_structures,
-- discount_structures) + the inline-role tables (sports catalog, vendors,
-- inventory categories/movements/stock, parent_links, announcements) are gated at
-- the POLICY level in the next migration.
--
-- Bodies are reproduced verbatim from their latest definitions (20260614000000,
-- 20260607000300/400/800, 20260606000000, 20260527000000/100) with only the
-- academy_writes_allowed() guard added. create-or-replace preserves grants.
-- See SUBSCRIPTION_ENFORCEMENT.md.
-- ============================================================================

-- ---- students / coaches ----------------------------------------------------

create or replace function public.can_manage_student(p_center_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select public.academy_writes_allowed() and (
    case (select role from public.users where id = auth.uid())
      when 'academy_owner' then true
      when 'academy_admin' then true
      when 'center_admin'  then
        p_center_id is null or public.current_user_in_center(p_center_id)
      when 'head_coach'    then
        p_center_id is null or public.current_user_in_center(p_center_id)
      else false
    end
  );
$$;

create or replace function public.can_manage_coach_record(p_center_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select public.academy_writes_allowed() and (
    case (select role from public.users where id = auth.uid())
      when 'academy_owner' then true
      when 'academy_admin' then true
      when 'center_admin'  then
        p_center_id is null or public.current_user_in_center(p_center_id)
      when 'head_coach'    then
        p_center_id is null or public.current_user_in_center(p_center_id)
      else false
    end
  );
$$;

-- coach_sports junction → resolves to the coach's center via can_manage_coach_record.
create or replace function public.can_manage_coach(p_coach_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select public.academy_writes_allowed() and public.can_manage_coach_record(
    (select center_id from public.coaches where id = p_coach_id)
  );
$$;

-- ---- batches / enrollment / staff ------------------------------------------

create or replace function public.can_manage_batches(p_center_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select public.academy_writes_allowed() and (
    case (select role from public.users where id = auth.uid())
      when 'academy_owner' then true
      when 'academy_admin' then true
      when 'center_admin'  then
        p_center_id is null or public.current_user_in_center(p_center_id)
      when 'head_coach'    then
        p_center_id is null or public.current_user_in_center(p_center_id)
      else false
    end
  );
$$;

create or replace function public.can_manage_batch_fields(
  p_center_id uuid,
  p_sport_id uuid
)
returns boolean language sql stable security definer set search_path = public
as $$
  select public.academy_writes_allowed() and (
    case (select role from public.users where id = auth.uid())
      when 'academy_owner' then true
      when 'academy_admin' then true
      when 'center_admin'  then
        p_center_id is null or public.current_user_in_center(p_center_id)
      when 'head_coach'    then
        (p_center_id is null or public.current_user_in_center(p_center_id))
        and (p_sport_id is null or public.head_coach_owns_sport(p_sport_id))
      else false
    end
  );
$$;

create or replace function public.can_manage_enrollment(p_batch_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select public.academy_writes_allowed() and (
    public.can_manage_batch_fields(
           (select center_id from public.batches where id = p_batch_id),
           (select sport_id  from public.batches where id = p_batch_id)
         )
      or public.coach_owns_batch(p_batch_id)
  );
$$;

create or replace function public.can_staff_batch(p_batch_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select public.academy_writes_allowed() and (
    public.coach_owns_batch(p_batch_id)
      or public.can_manage_batch_fields(
           (select center_id from public.batches where id = p_batch_id),
           (select sport_id  from public.batches where id = p_batch_id)
         )
  );
$$;

-- ---- attendance / performance / media --------------------------------------

create or replace function public.can_mark_attendance(p_batch_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select public.academy_writes_allowed() and (
    case (select role from public.users where id = auth.uid())
      when 'academy_owner' then true
      when 'academy_admin' then true
      when 'center_admin'  then public.batch_in_my_center(p_batch_id)
      when 'head_coach'    then
        public.batch_in_my_center(p_batch_id)
        and public.batch_in_my_sport(p_batch_id)
      when 'coach'         then public.staff_on_batch(p_batch_id)
      when 'trainer'       then public.staff_on_batch(p_batch_id)
      else false
    end
  );
$$;

create or replace function public.can_record_performance(p_batch_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select public.academy_writes_allowed() and (
    case (select role from public.users where id = auth.uid())
      when 'academy_owner' then true
      when 'academy_admin' then true
      when 'center_admin'  then p_batch_id is null or public.batch_in_my_center(p_batch_id)
      when 'head_coach'    then
        p_batch_id is null
        or (public.batch_in_my_center(p_batch_id)
            and public.batch_in_my_sport(p_batch_id))
      when 'coach'         then p_batch_id is null or public.staff_on_batch(p_batch_id)
      when 'trainer'       then p_batch_id is not null and public.staff_on_batch(p_batch_id)
      else false
    end
  );
$$;

create or replace function public.can_record_perf_for_assessment(p_assessment_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select public.academy_writes_allowed() and public.can_record_performance(
    (select batch_id from public.performance_assessments where id = p_assessment_id)
  );
$$;

create or replace function public.can_upload_student_media(p_student_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select public.academy_writes_allowed() and (
    case (select role from public.users where id = auth.uid())
      when 'academy_owner' then true
      when 'academy_admin' then true
      when 'center_admin'  then public.student_in_my_center(p_student_id)
      when 'head_coach'    then public.student_in_my_center(p_student_id)
      when 'coach'         then public.student_in_my_batch(p_student_id)
      when 'trainer'       then public.student_in_my_batch(p_student_id)
      else false
    end
  );
$$;

-- ---- per-student finance (write-only delegators; reads via can_view_*) ------

create or replace function public.can_manage_finance(p_student_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select public.academy_writes_allowed() and public.can_admin_center_scope(
    (select center_id from public.students where id = p_student_id)
  );
$$;

create or replace function public.can_manage_invoice(p_invoice_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select public.academy_writes_allowed() and public.can_manage_finance(
    (select student_id from public.invoices where id = p_invoice_id)
  );
$$;

create or replace function public.can_manage_batch_finance(p_batch_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select public.academy_writes_allowed() and public.can_admin_center_scope(
    (select center_id from public.batches where id = p_batch_id)
  );
$$;

-- ---- leads (activity log) --------------------------------------------------

create or replace function public.can_admin_lead(p_lead_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select public.academy_writes_allowed() and public.can_admin_center_scope(
    (select preferred_center_id from public.leads where id = p_lead_id)
  );
$$;

-- ---- user provisioning / invites -------------------------------------------

create or replace function public.can_provision_role(
  p_target_role public.user_role,
  p_center_id uuid
)
returns boolean language sql stable security definer set search_path = public
as $$
  select public.academy_writes_allowed() and (
    case
      when (select role from public.users where id = auth.uid()) = 'super_admin'
        then true
      when public.role_rank((select role from public.users where id = auth.uid()))
           <= public.role_rank(p_target_role)
        then false
      when p_target_role in ('parent', 'student')
        then public.can_admin_center_scope(p_center_id)
      else case (select role from public.users where id = auth.uid())
        when 'academy_owner' then true
        when 'academy_admin' then true
        when 'center_admin'  then
          p_center_id is null or public.current_user_in_center(p_center_id)
        when 'head_coach'    then
          p_center_id is null or public.current_user_in_center(p_center_id)
        when 'coach'         then
          p_center_id is null or public.current_user_in_center(p_center_id)
        else false
      end
    end
  );
$$;

-- ############################################################################
-- ## SECTION 4/4 : 20260627000300_subscription_enforce_policies.sql
-- ############################################################################

-- ============================================================================
-- Subscription enforcement — Phase 1c: gate the WRITE policies that bypass the
-- (now-gated) capability helpers.
--
-- Two groups can't be covered by gating a helper:
--   1. Policies that call can_admin_center_scope() DIRECTLY — that helper is
--      reused in the finance READ gate, so it must stay un-gated; we add the
--      guard at the policy instead. (leads, inventory_items, fee_structures,
--      discount_structures, center_sports, students_update coach branch.)
--   2. Policies with inline has_admin_or_higher() / role-list checks.
--      (academy_sports, vendors, inventory_categories, inventory_movements,
--      parent_links, announcements, event_registrations, event_results.)
--
-- Mechanism: add `and public.academy_writes_allowed()` to the tenant branch.
-- super_admin keeps writing via the policy's separate is_super_admin() branch.
-- Reads are untouched. Policy bodies are reproduced verbatim from their latest
-- definitions with only the guard added. See SUBSCRIPTION_ENFORCEMENT.md.
--
-- NOT gated (deliberate carve-outs): saas_* (the pay-to-unlock path), support
-- tickets, messaging + notifications, and the parent/student event self-register
-- branch (a frozen academy must not block its customers' self-service).
-- inventory_stock has no client write policy (trigger-maintained) — nothing to do.
-- ============================================================================

-- ---- students_update: gate the inline coach branch too ---------------------
drop policy students_update on public.students;
create policy students_update on public.students
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.academy_writes_allowed()
        and (public.can_manage_student(center_id)
             or (public.current_user_role() = 'coach'
                 and public.student_assigned_to_me(id))))
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.academy_writes_allowed()
        and (public.can_manage_student(center_id)
             or (public.current_user_role() = 'coach'
                 and public.student_assigned_to_me(id))))
  );

-- ---- leads (direct can_admin_center_scope) ---------------------------------
drop policy leads_write_insert on public.leads;
drop policy leads_write_update on public.leads;
drop policy leads_write_delete on public.leads;

create policy leads_write_insert on public.leads
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.academy_writes_allowed()
        and public.can_admin_center_scope(preferred_center_id))
  );
create policy leads_write_update on public.leads
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.academy_writes_allowed()
        and public.can_admin_center_scope(preferred_center_id))
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.academy_writes_allowed()
        and public.can_admin_center_scope(preferred_center_id))
  );
create policy leads_write_delete on public.leads
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.academy_writes_allowed()
        and public.can_admin_center_scope(preferred_center_id))
  );

-- ---- inventory_items (direct can_admin_center_scope) -----------------------
drop policy inv_items_write_insert on public.inventory_items;
drop policy inv_items_write_update on public.inventory_items;
drop policy inv_items_write_delete on public.inventory_items;

create policy inv_items_write_insert on public.inventory_items
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.academy_writes_allowed()
        and public.can_admin_center_scope(center_id))
  );
create policy inv_items_write_update on public.inventory_items
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.academy_writes_allowed()
        and public.can_admin_center_scope(center_id))
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.academy_writes_allowed()
        and public.can_admin_center_scope(center_id))
  );
create policy inv_items_write_delete on public.inventory_items
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.academy_writes_allowed()
        and public.can_admin_center_scope(center_id))
  );

-- ---- fee_structures (templates; direct can_admin_center_scope) -------------
drop policy fee_structures_write_insert on public.fee_structures;
drop policy fee_structures_write_update on public.fee_structures;
drop policy fee_structures_write_delete on public.fee_structures;

create policy fee_structures_write_insert on public.fee_structures
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.academy_writes_allowed()
        and public.can_admin_center_scope(center_id))
  );
create policy fee_structures_write_update on public.fee_structures
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.academy_writes_allowed()
        and public.can_admin_center_scope(center_id))
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.academy_writes_allowed()
        and public.can_admin_center_scope(center_id))
  );
create policy fee_structures_write_delete on public.fee_structures
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.academy_writes_allowed()
        and public.can_admin_center_scope(center_id))
  );

-- ---- discount_structures (templates; direct can_admin_center_scope) --------
drop policy ds_write_insert on public.discount_structures;
drop policy ds_write_update on public.discount_structures;
drop policy ds_write_delete on public.discount_structures;

create policy ds_write_insert on public.discount_structures
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.academy_writes_allowed()
        and public.can_admin_center_scope(center_id))
  );
create policy ds_write_update on public.discount_structures
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.academy_writes_allowed()
        and public.can_admin_center_scope(center_id))
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.academy_writes_allowed()
        and public.can_admin_center_scope(center_id))
  );
create policy ds_write_delete on public.discount_structures
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.academy_writes_allowed()
        and public.can_admin_center_scope(center_id))
  );

-- ---- center_sports (direct can_admin_center_scope) -------------------------
drop policy center_sports_write_insert on public.center_sports;
drop policy center_sports_write_update on public.center_sports;
drop policy center_sports_write_delete on public.center_sports;

create policy center_sports_write_insert on public.center_sports
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.academy_writes_allowed()
        and public.can_admin_center_scope(center_id))
  );
create policy center_sports_write_update on public.center_sports
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.academy_writes_allowed()
        and public.can_admin_center_scope(center_id))
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.academy_writes_allowed()
        and public.can_admin_center_scope(center_id))
  );
create policy center_sports_write_delete on public.center_sports
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.academy_writes_allowed()
        and public.can_admin_center_scope(center_id))
  );

-- ---- academy_sports (catalog; inline has_admin_or_higher) ------------------
drop policy academy_sports_admin_insert on public.academy_sports;
drop policy academy_sports_admin_update on public.academy_sports;
drop policy academy_sports_admin_delete on public.academy_sports;

create policy academy_sports_admin_insert on public.academy_sports
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.has_admin_or_higher() and public.academy_writes_allowed())
  );
create policy academy_sports_admin_update on public.academy_sports
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.has_admin_or_higher() and public.academy_writes_allowed())
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.has_admin_or_higher() and public.academy_writes_allowed())
  );
create policy academy_sports_admin_delete on public.academy_sports
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.has_admin_or_higher() and public.academy_writes_allowed())
  );

-- ---- vendors (inline has_admin_or_higher) ----------------------------------
drop policy vendors_admin_insert on public.vendors;
drop policy vendors_admin_update on public.vendors;
drop policy vendors_admin_delete on public.vendors;

create policy vendors_admin_insert on public.vendors
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.has_admin_or_higher() and public.academy_writes_allowed())
  );
create policy vendors_admin_update on public.vendors
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.has_admin_or_higher() and public.academy_writes_allowed())
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.has_admin_or_higher() and public.academy_writes_allowed())
  );
create policy vendors_admin_delete on public.vendors
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.has_admin_or_higher() and public.academy_writes_allowed())
  );

-- ---- inventory_categories (inline has_admin_or_higher) ---------------------
drop policy inv_cats_admin_insert on public.inventory_categories;
drop policy inv_cats_admin_update on public.inventory_categories;
drop policy inv_cats_admin_delete on public.inventory_categories;

create policy inv_cats_admin_insert on public.inventory_categories
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.has_admin_or_higher() and public.academy_writes_allowed())
  );
create policy inv_cats_admin_update on public.inventory_categories
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.has_admin_or_higher() and public.academy_writes_allowed())
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.has_admin_or_higher() and public.academy_writes_allowed())
  );
create policy inv_cats_admin_delete on public.inventory_categories
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.has_admin_or_higher() and public.academy_writes_allowed())
  );

-- ---- inventory_movements (inline staff role list) --------------------------
drop policy inv_moves_staff_insert on public.inventory_movements;
create policy inv_moves_staff_insert on public.inventory_movements
  for insert with check (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.academy_writes_allowed()
      and public.current_user_role() in (
        'academy_owner', 'academy_admin', 'center_admin', 'head_coach', 'coach', 'trainer'
      )
    )
  );

-- ---- parent_links (inline has_admin_or_higher) -----------------------------
drop policy parent_links_admin_insert on public.parent_links;
drop policy parent_links_admin_update on public.parent_links;
drop policy parent_links_admin_delete on public.parent_links;

create policy parent_links_admin_insert on public.parent_links
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.has_admin_or_higher() and public.academy_writes_allowed())
  );
create policy parent_links_admin_update on public.parent_links
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.has_admin_or_higher() and public.academy_writes_allowed())
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.has_admin_or_higher() and public.academy_writes_allowed())
  );
create policy parent_links_admin_delete on public.parent_links
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.has_admin_or_higher() and public.academy_writes_allowed())
  );

-- ---- announcements (compose; can_target_announcement is plpgsql) -----------
drop policy announcements_compose_insert on public.announcements;
drop policy announcements_compose_update on public.announcements;
drop policy announcements_compose_delete on public.announcements;

create policy announcements_compose_insert on public.announcements
  for insert with check (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.academy_writes_allowed()
      and public.can_target_announcement(
        target_roles, target_batches, target_centers, target_sports
      )
    )
  );
create policy announcements_compose_update on public.announcements
  for update using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.academy_writes_allowed()
      and (public.has_admin_or_higher() or created_by = auth.uid())
    )
  )
  with check (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.academy_writes_allowed()
      and (public.has_admin_or_higher() or created_by = auth.uid())
      and public.can_target_announcement(
        target_roles, target_batches, target_centers, target_sports
      )
    )
  );
create policy announcements_compose_delete on public.announcements
  for delete using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.academy_writes_allowed()
      and (public.has_admin_or_higher() or created_by = auth.uid())
    )
  );

-- ---- event_registrations: gate STAFF writes; keep parent/student self-register
drop policy event_regs_admin_insert on public.event_registrations;
drop policy event_regs_admin_update on public.event_registrations;
drop policy event_regs_admin_delete on public.event_registrations;

create policy event_regs_admin_insert on public.event_registrations
  for insert with check (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and (
        (
          (public.has_admin_or_higher()
           or public.current_user_role() in ('center_admin', 'head_coach', 'coach'))
          and public.academy_writes_allowed()
        )
        or (
          public.current_user_role() in ('parent', 'student')
          and public.parent_can_see_student(student_id)
          and exists (
            select 1 from public.events e
            where e.id = event_id
              and e.academy_id = academy_id
              and e.status = 'published'
              and (e.registration_opens_at is null or e.registration_opens_at <= now())
              and (e.registration_closes_at is null or e.registration_closes_at >= now())
          )
        )
      )
    )
  );
create policy event_regs_admin_update on public.event_registrations
  for update using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.academy_writes_allowed()
      and public.current_user_role() not in ('parent', 'student')
    )
  )
  with check (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.academy_writes_allowed()
      and public.current_user_role() not in ('parent', 'student')
    )
  );
create policy event_regs_admin_delete on public.event_registrations
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.has_admin_or_higher() and public.academy_writes_allowed())
  );

-- ---- event_results (inline staff role list) --------------------------------
drop policy event_results_staff_insert on public.event_results;
create policy event_results_staff_insert on public.event_results
  for insert with check (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.academy_writes_allowed()
      and public.current_user_role() in (
        'academy_owner', 'academy_admin', 'center_admin', 'head_coach', 'coach'
      )
    )
  );

commit;
