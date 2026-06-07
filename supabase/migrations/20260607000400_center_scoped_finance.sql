-- ============================================================================
-- Phase 4 — center-scoped finance (the "who manages fees" answer).
--
-- Until now ALL finance was academy-scoped + admin-only WRITE, but academy-wide
-- READ for every staff member — so a center_admin could SEE every center's
-- money but manage none, and a parent could read every invoice in the academy.
--
-- This makes center_admin the per-center fee manager and narrows reads:
--   • WRITE fees/discounts/invoices/payments/assignments → admin-tier (any
--     center) OR center_admin (their OWN center's students/batches).
--   • READ those rows → admin-tier (academy) / center_admin (own center) /
--     parent+student (their own student only). Coaches/head_coaches/trainers
--     no longer read finance (they have no viewRevenue capability).
--   • REFUNDS stay academy_admin+ for writes (money-out = separation of duties);
--     read narrows to admin-tier + the payer's parent/student.
--   • fee_structures / discount_structures (TEMPLATES) gain a nullable center_id:
--     NULL = academy-wide (admin-managed), set = a center_admin's own template.
--
-- Center is DERIVED from the row's student/batch (both invoices + payments carry
-- student_id NOT NULL), so no center_id column is added to per-student money
-- rows and the recur-invoice cron / razorpay-webhook (service-role, RLS-bypass)
-- are untouched — money paths stay idempotent + signature-verified (invariant 6).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Finance scope helpers
-- ----------------------------------------------------------------------------

-- WRITE gate for per-student money: admin tier (any center) OR center_admin
-- (the student's center). The policy still pins academy_id, so this only adds
-- the center narrowing.
create or replace function public.can_manage_finance(p_student_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.can_admin_center_scope(
    (select center_id from public.students where id = p_student_id)
  );
$$;

-- READ gate for per-student money: admin/center_admin (scoped) in the same
-- academy, plus the student's own parent/student login. Coaches/trainers get
-- nothing (finance isn't theirs).
create or replace function public.can_view_student_finance(p_student_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.is_super_admin()
    or (
      (select academy_id from public.students where id = p_student_id)
        = public.current_user_academy_id()
      and public.can_admin_center_scope(
        (select center_id from public.students where id = p_student_id))
    )
    or public.parent_can_see_student(p_student_id);
$$;

-- Invoice helpers resolve to the invoice's student.
create or replace function public.can_manage_invoice(p_invoice_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.can_manage_finance(
    (select student_id from public.invoices where id = p_invoice_id));
$$;

create or replace function public.can_view_invoice(p_invoice_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.can_view_student_finance(
    (select student_id from public.invoices where id = p_invoice_id));
$$;

-- Batch-level fee/discount config: admin tier (any) OR center_admin (the
-- batch's center). No parent/student read — these are pricing config.
create or replace function public.can_manage_batch_finance(p_batch_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.can_admin_center_scope(
    (select center_id from public.batches where id = p_batch_id));
$$;

-- Refund read gate: admin-tier (same academy) + the payer's parent/student.
-- SECURITY DEFINER so the payments lookup isn't re-filtered by payments RLS.
create or replace function public.can_view_refund(p_payment_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.is_super_admin()
    or (
      (select academy_id from public.payments where id = p_payment_id)
        = public.current_user_academy_id()
      and public.has_admin_or_higher()
    )
    or public.parent_can_see_student(
         (select student_id from public.payments where id = p_payment_id));
$$;

grant execute on function public.can_manage_finance(uuid)         to authenticated;
grant execute on function public.can_view_student_finance(uuid)   to authenticated;
grant execute on function public.can_manage_invoice(uuid)         to authenticated;
grant execute on function public.can_view_invoice(uuid)           to authenticated;
grant execute on function public.can_manage_batch_finance(uuid)   to authenticated;
grant execute on function public.can_view_refund(uuid)            to authenticated;

-- ----------------------------------------------------------------------------
-- Templates: add a nullable center_id (NULL = academy-wide). Reads stay
-- academy-wide (templates are reusable config, not per-student money).
-- ----------------------------------------------------------------------------
alter table public.fee_structures
  add column center_id uuid references public.centers(id) on delete set null;
create index idx_fee_structures_center
  on public.fee_structures(center_id) where center_id is not null;

alter table public.discount_structures
  add column center_id uuid references public.centers(id) on delete set null;
create index idx_discount_structures_center
  on public.discount_structures(center_id) where center_id is not null;

-- fee_structures writes → admin tier (any) + center_admin (own center).
drop policy fee_structures_admin_insert on public.fee_structures;
drop policy fee_structures_admin_update on public.fee_structures;
drop policy fee_structures_admin_delete on public.fee_structures;

create policy fee_structures_write_insert on public.fee_structures
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_admin_center_scope(center_id))
  );
create policy fee_structures_write_update on public.fee_structures
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_admin_center_scope(center_id))
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_admin_center_scope(center_id))
  );
create policy fee_structures_write_delete on public.fee_structures
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_admin_center_scope(center_id))
  );

drop policy ds_admin_insert on public.discount_structures;
drop policy ds_admin_update on public.discount_structures;
drop policy ds_admin_delete on public.discount_structures;

create policy ds_write_insert on public.discount_structures
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_admin_center_scope(center_id))
  );
create policy ds_write_update on public.discount_structures
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_admin_center_scope(center_id))
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_admin_center_scope(center_id))
  );
create policy ds_write_delete on public.discount_structures
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_admin_center_scope(center_id))
  );

-- ----------------------------------------------------------------------------
-- invoices — read narrowed; write center-scoped (via the invoice's student).
-- ----------------------------------------------------------------------------
drop policy invoices_academy_read on public.invoices;
drop policy invoices_admin_insert on public.invoices;
drop policy invoices_admin_update on public.invoices;
drop policy invoices_admin_delete on public.invoices;

create policy invoices_read on public.invoices
  for select using (public.can_view_student_finance(student_id));
create policy invoices_write_insert on public.invoices
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_finance(student_id))
  );
create policy invoices_write_update on public.invoices
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_finance(student_id))
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_finance(student_id))
  );
create policy invoices_write_delete on public.invoices
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_finance(student_id))
  );

-- invoice_line_items — inherit the parent invoice's gate.
drop policy invoice_lines_academy_read on public.invoice_line_items;
drop policy invoice_lines_admin_insert on public.invoice_line_items;
drop policy invoice_lines_admin_update on public.invoice_line_items;
drop policy invoice_lines_admin_delete on public.invoice_line_items;

create policy invoice_lines_read on public.invoice_line_items
  for select using (public.can_view_invoice(invoice_id));
create policy invoice_lines_write_insert on public.invoice_line_items
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_invoice(invoice_id))
  );
create policy invoice_lines_write_update on public.invoice_line_items
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_invoice(invoice_id))
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_invoice(invoice_id))
  );
create policy invoice_lines_write_delete on public.invoice_line_items
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_invoice(invoice_id))
  );

-- ----------------------------------------------------------------------------
-- payments — read narrowed; write center-scoped. (Razorpay inserts come via
-- the webhook as service-role and bypass RLS.)
-- ----------------------------------------------------------------------------
drop policy payments_academy_read on public.payments;
drop policy payments_admin_insert on public.payments;
drop policy payments_admin_update on public.payments;
drop policy payments_admin_delete on public.payments;

create policy payments_read on public.payments
  for select using (public.can_view_student_finance(student_id));
create policy payments_write_insert on public.payments
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_finance(student_id))
  );
create policy payments_write_update on public.payments
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_finance(student_id))
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_finance(student_id))
  );
create policy payments_write_delete on public.payments
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_finance(student_id))
  );

-- ----------------------------------------------------------------------------
-- refunds — WRITES stay academy_admin+ (unchanged). Read narrows from
-- academy-wide to admin-tier + the payer's parent/student.
-- ----------------------------------------------------------------------------
drop policy refunds_academy_read on public.refunds;

create policy refunds_read on public.refunds
  for select using (public.can_view_refund(payment_id));

-- ----------------------------------------------------------------------------
-- student_fee_assignments — read narrowed; write center-scoped.
-- ----------------------------------------------------------------------------
drop policy sfa_academy_read on public.student_fee_assignments;
drop policy sfa_admin_insert on public.student_fee_assignments;
drop policy sfa_admin_update on public.student_fee_assignments;
drop policy sfa_admin_delete on public.student_fee_assignments;

create policy sfa_read on public.student_fee_assignments
  for select using (public.can_view_student_finance(student_id));
create policy sfa_write_insert on public.student_fee_assignments
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_finance(student_id))
  );
create policy sfa_write_update on public.student_fee_assignments
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_finance(student_id))
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_finance(student_id))
  );
create policy sfa_write_delete on public.student_fee_assignments
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_finance(student_id))
  );

-- ----------------------------------------------------------------------------
-- student_discount_assignments — read narrowed; write center-scoped.
-- ----------------------------------------------------------------------------
drop policy sda_academy_read on public.student_discount_assignments;
drop policy sda_admin_insert on public.student_discount_assignments;
drop policy sda_admin_update on public.student_discount_assignments;
drop policy sda_admin_delete on public.student_discount_assignments;

create policy sda_read on public.student_discount_assignments
  for select using (public.can_view_student_finance(student_id));
create policy sda_write_insert on public.student_discount_assignments
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_finance(student_id))
  );
create policy sda_write_update on public.student_discount_assignments
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_finance(student_id))
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_finance(student_id))
  );
create policy sda_write_delete on public.student_discount_assignments
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_finance(student_id))
  );

-- ----------------------------------------------------------------------------
-- batch_fee_assignments / batch_discount_assignments — staff-only (admin tier
-- + center_admin own center), via the batch's center. No parent/student read.
-- ----------------------------------------------------------------------------
drop policy bfa_academy_read on public.batch_fee_assignments;
drop policy bfa_admin_insert on public.batch_fee_assignments;
drop policy bfa_admin_update on public.batch_fee_assignments;
drop policy bfa_admin_delete on public.batch_fee_assignments;

create policy bfa_read on public.batch_fee_assignments
  for select using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_batch_finance(batch_id))
  );
create policy bfa_write_insert on public.batch_fee_assignments
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_batch_finance(batch_id))
  );
create policy bfa_write_update on public.batch_fee_assignments
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_batch_finance(batch_id))
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_batch_finance(batch_id))
  );
create policy bfa_write_delete on public.batch_fee_assignments
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_batch_finance(batch_id))
  );

drop policy bda_academy_read on public.batch_discount_assignments;
drop policy bda_admin_insert on public.batch_discount_assignments;
drop policy bda_admin_update on public.batch_discount_assignments;
drop policy bda_admin_delete on public.batch_discount_assignments;

create policy bda_read on public.batch_discount_assignments
  for select using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_batch_finance(batch_id))
  );
create policy bda_write_insert on public.batch_discount_assignments
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_batch_finance(batch_id))
  );
create policy bda_write_update on public.batch_discount_assignments
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_batch_finance(batch_id))
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_batch_finance(batch_id))
  );
create policy bda_write_delete on public.batch_discount_assignments
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_batch_finance(batch_id))
  );
