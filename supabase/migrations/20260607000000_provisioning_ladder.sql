-- ============================================================================
-- Provisioning ladder — who may create whom.
--
-- Encodes the org hierarchy ("each role provisions the rung below it; a higher
-- role can do anything a lower role can"):
--
--   academy_owner  -> academy_admin + everything below
--   academy_admin  -> center_admin + everything below (NOT another admin/owner)
--   center_admin   -> head_coach / coach / trainer / parent / student (own center)
--   head_coach     -> coach / trainer                                 (own center)
--   coach          -> trainer                                         (own center)
--   trainer        -> nobody
--
-- role_rank() centralises the "higher >= lower" invariant in one place.
-- can_provision_role() is the single gate, consumed by:
--   (a) the users write policies below  — defence-in-depth for DIRECT client
--       writes to public.users (e.g. a center_admin trying to self-promote);
--   (b) the invite-user Edge Function    — the REAL gate, because the auth
--       trigger that inserts public.users is SECURITY DEFINER and bypasses RLS.
--
-- Also persists center_id on convert_lead-created students so the new student
-- inherits the lead's center (was NULL, which means "manageable by every
-- center_admin" under can_admin_center_scope — a silent widening).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- role_rank — the seniority ladder. Pure mapping, so IMMUTABLE.
-- ----------------------------------------------------------------------------
create or replace function public.role_rank(p_role public.user_role)
returns int
language sql
immutable
as $$
  select case p_role
    when 'super_admin'   then 100
    when 'academy_owner' then 90
    when 'academy_admin' then 80
    when 'center_admin'  then 70
    when 'head_coach'    then 60
    when 'coach'         then 50
    when 'trainer'       then 40
    when 'parent'        then 20
    when 'student'       then 10
  end;
$$;

grant execute on function public.role_rank(public.user_role) to authenticated;

-- ----------------------------------------------------------------------------
-- can_provision_role(target_role, center_id) — may the caller create a user of
-- target_role scoped to center_id?
--
-- SECURITY DEFINER + pinned search_path so it can read the caller's own
-- users row past RLS (same pattern as can_admin_center_scope). super_admin and
-- the academy_id tenant filter are applied by the *policy*, not here.
-- ----------------------------------------------------------------------------
create or replace function public.can_provision_role(
  p_target_role public.user_role,
  p_center_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case
    when (select role from public.users where id = auth.uid()) = 'super_admin'
      then true
    -- Ceiling: never create a peer or a more-senior role.
    when public.role_rank((select role from public.users where id = auth.uid()))
         <= public.role_rank(p_target_role)
      then false
    -- End-user logins (parent/student) are record management, not staff
    -- provisioning: only admin-tier + center_admin (own center) may mint them.
    when p_target_role in ('parent', 'student')
      then public.can_admin_center_scope(p_center_id)
    -- Staff roles strictly below the caller's rank.
    else case (select role from public.users where id = auth.uid())
      when 'academy_owner' then true
      when 'academy_admin' then true
      when 'center_admin'  then
        p_center_id is null or p_center_id = public.current_user_center_id()
      when 'head_coach'    then
        p_center_id is null or p_center_id = public.current_user_center_id()
      when 'coach'         then
        p_center_id is null or p_center_id = public.current_user_center_id()
      else false
    end
  end;
$$;

grant execute on function public.can_provision_role(public.user_role, uuid)
  to authenticated;

-- ============================================================================
-- users — replace the coarse has_admin_or_higher() write gate with the
-- provisioning ladder. Per-action split (no `for all`) so the read policies
-- are untouched.
--
-- UPDATE checks the ladder on BOTH the old row (using → current role/center)
-- and the new row (with check → target role/center): a center_admin cannot
-- promote a coach upward, nor move a user to another center. users_self_update
-- (self edits, role frozen) and users_self_read / users_same_academy_read are
-- left in place.
--
-- NOTE: 20260502000000_tighten_users_rls already split the old `users_admin_write`
-- into users_admin_insert/update/delete (gated on has_admin_or_higher()); we
-- replace all three with the provisioning-ladder versions.
-- ============================================================================
drop policy users_admin_insert on public.users;
drop policy users_admin_update on public.users;
drop policy users_admin_delete on public.users;

create policy users_admin_insert on public.users
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_provision_role(role, center_id))
  );

create policy users_admin_update on public.users
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_provision_role(role, center_id))
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_provision_role(role, center_id))
  );

create policy users_admin_delete on public.users
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_provision_role(role, center_id))
  );

-- ============================================================================
-- convert_lead — persist center_id (= lead.preferred_center_id) on the new
-- student. Otherwise unchanged from 20260508000600_convert_lead_rpc.sql.
-- ============================================================================
create or replace function public.convert_lead(
  p_lead_id uuid,
  p_batch_id uuid default null,
  p_parent_user_id uuid default null,
  p_start_date date default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_lead public.leads%rowtype;
  v_student_id uuid;
  v_start date := coalesce(p_start_date, current_date);
begin
  -- Lock the row to keep the conversion race-free.
  select * into v_lead from public.leads
   where id = p_lead_id for update;
  if not found then raise exception 'lead not found'; end if;
  if v_lead.status = 'converted' then
    raise exception 'lead already converted';
  end if;

  insert into public.students (
    academy_id, center_id, first_name, last_name, parent_name, email, phone
  ) values (
    v_lead.academy_id,
    v_lead.preferred_center_id,   -- inherit the lead's center for scoping
    v_lead.first_name,
    coalesce(v_lead.last_name, ''),
    coalesce(v_lead.parent_name, ''),
    v_lead.email,
    v_lead.phone
  )
  returning id into v_student_id;

  if p_batch_id is not null then
    -- Validate the batch belongs to the same academy.
    if not exists (
      select 1 from public.batches
      where id = p_batch_id and academy_id = v_lead.academy_id
    ) then
      raise exception 'batch not in lead''s academy';
    end if;

    insert into public.batch_enrollments
      (academy_id, batch_id, student_id, enrollment_status, enrolled_at)
    values (v_lead.academy_id, p_batch_id, v_student_id, 'active',
            v_start::timestamptz);
  end if;

  if p_parent_user_id is not null then
    insert into public.parent_links
      (academy_id, parent_user_id, student_id, is_primary)
    values (v_lead.academy_id, p_parent_user_id, v_student_id, true)
    on conflict do nothing;
  end if;

  update public.leads
     set status = 'converted',
         converted_student_id = v_student_id,
         converted_at = now()
   where id = p_lead_id;

  insert into public.lead_activities
    (academy_id, lead_id, user_id, kind, content, metadata)
  values (
    v_lead.academy_id, p_lead_id, auth.uid(),
    'note',
    'Lead converted to student',
    jsonb_build_object('student_id', v_student_id, 'batch_id', p_batch_id)
  );

  return v_student_id;
end;
$$;

grant execute on function public.convert_lead(uuid, uuid, uuid, date)
  to authenticated;
