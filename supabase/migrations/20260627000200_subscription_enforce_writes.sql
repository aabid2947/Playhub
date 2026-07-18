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
