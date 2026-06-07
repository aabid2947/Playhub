-- ============================================================================
-- PlayHub - org hierarchy re-architecture (Phases 1-5), combined.
--
-- Paste-and-run in the Supabase SQL editor. Applies the 6 hierarchy migrations
-- IN ORDER, wrapped in a single transaction (all-or-nothing).
--
-- ASSUMES the existing base schema (all migrations through 20260606000300) is
-- already applied. Run ONCE on a DB that does not yet have these changes.
-- Equivalent to applying, in order:
--   * 20260607000000_provisioning_ladder.sql
--   * 20260607000100_harden_auth_trigger.sql
--   * 20260607000200_head_coach_sport_scope.sql
--   * 20260607000300_batch_staff_trainer_scope.sql
--   * 20260607000400_center_scoped_finance.sql
--   * 20260607000500_center_read_isolation.sql
-- ============================================================================

begin;


-- ##########################################################################
-- ## 20260607000000_provisioning_ladder.sql
-- ##########################################################################

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



-- ##########################################################################
-- ## 20260607000100_harden_auth_trigger.sql
-- ##########################################################################

-- ============================================================================
-- Security: stop a self-signup from minting a privileged role.
--
-- THE HOLE: handle_new_auth_user (20260508000800) read role / academy_id /
-- center_id straight from raw_user_meta_data. A client fully controls that blob
-- via supabase.auth.signUp({ options: { data } }), so anyone could self-register
-- with { role:'academy_admin', academy_id:'<any-academy-uuid>' } and the trigger
-- would mint them an admin of someone else's academy (or 'super_admin', which
-- needs no academy at all). A cross-tenant privilege escalation.
--
-- THE FIX: privileged fields (role / academy_id / center_id / links) are now
-- honoured ONLY from a TRUSTED source:
--   • raw_app_meta_data — GoTrue ignores client-supplied app_metadata on
--     signUp(); only the service role (admin.createUser / updateUserById) can
--     set it. Used by create_demo_users.mjs.
--   • raw_user_meta_data, but ONLY when invited_at is set — i.e. the row came
--     through GoTrue's admin invite endpoint (inviteUserByEmail), which the
--     invite-user Edge Function calls after can_provision_role() has authorised
--     the caller.
--
-- A plain self-signup has neither app_metadata nor invited_at, so it always
-- lands as a 'student' with no academy; the owner-onboarding flow then promotes
-- via bootstrap_owner_academy() (which only ever touches auth.uid()'s own row).
--
-- Non-privileged first_name / last_name stay readable from user_metadata — they
-- carry no authority, and the self-signup form legitimately supplies them.
-- ============================================================================

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  v_app  jsonb := coalesce(new.raw_app_meta_data, '{}'::jsonb);
  -- The only trusted source of privileged fields: app_metadata (service-role
  -- only), or user_metadata for admin-driven invites (invited_at set).
  v_trusted jsonb := case
    when v_app ? 'role'             then v_app
    when new.invited_at is not null then v_user
    else '{}'::jsonb
  end;
  v_role public.user_role :=
    coalesce((v_trusted->>'role')::public.user_role, 'student');
  v_academy_id uuid := nullif(v_trusted->>'academy_id', '')::uuid;
  v_center_id uuid := nullif(v_trusted->>'center_id', '')::uuid;
  v_link_student_id uuid := nullif(v_trusted->>'link_to_student_id', '')::uuid;
  v_link_relationship text := coalesce(v_trusted->>'link_relationship', 'parent');
  v_link_coach_id uuid := nullif(v_trusted->>'link_coach_id', '')::uuid;
  v_link_student_login_id uuid := nullif(v_trusted->>'link_student_login_id', '')::uuid;
  v_must_change boolean := (v_trusted ? 'role' and v_academy_id is not null);
begin
  insert into public.users (
    id, email, phone, role, first_name, last_name,
    academy_id, center_id, must_change_password
  ) values (
    new.id,
    new.email,
    new.phone,
    v_role,
    v_user->>'first_name',   -- non-privileged: fine to trust from the client
    v_user->>'last_name',
    v_academy_id,
    v_center_id,
    v_must_change
  )
  on conflict (id) do nothing;

  -- Parent linking — only when role is 'parent' and the invite carried a link.
  if v_role = 'parent' and v_link_student_id is not null
     and v_academy_id is not null then
    insert into public.parent_links
      (academy_id, parent_user_id, student_id, relationship, is_primary)
    values
      (v_academy_id, new.id, v_link_student_id, v_link_relationship, true)
    on conflict do nothing;
  end if;

  -- Coach login — connect the new user to an existing coaches row.
  if v_link_coach_id is not null then
    update public.coaches set user_id = new.id where id = v_link_coach_id;
  end if;

  -- Student login — connect the new user to an existing students row.
  if v_link_student_login_id is not null then
    update public.students set user_id = new.id where id = v_link_student_login_id;
  end if;

  return new;
end;
$$;



-- ##########################################################################
-- ## 20260607000200_head_coach_sport_scope.sql
-- ##########################################################################

-- ============================================================================
-- Phase 2 — head_coach is limited to THEIR OWN SPORT(S), and center_admin can
-- enable sports for their center.
--
-- Until now head_coach was scoped only to its CENTER (byte-identical to
-- center_admin in can_manage_batches). The org model wants a head_coach to own
-- a sport, not the whole center. A head_coach's sports = the coach_sports rows
-- of the coaches row they're linked to (coaches.user_id = auth.uid()).
--
-- New authority for a head_coach on a batch = in their center AND in one of
-- their sports. center_admin / admin-tier are unchanged (center / academy-wide).
--
-- NOTE on NULL sport_id: a batch with no sport_id is NOT manageable by a
-- head_coach (they own specific sports, not "no sport") — admin/center_admin
-- still manage it. Keep batches.sport_id populated. The legacy free-text
-- batches.sport column was already dropped (20260510000200).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Scope helpers
-- ----------------------------------------------------------------------------

-- Is p_sport_id one of the caller's (head-)coach sports?
create or replace function public.head_coach_owns_sport(p_sport_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.coach_sports cs
    join public.coaches c on c.id = cs.coach_id
    where c.user_id = auth.uid()
      and cs.sport_id = p_sport_id
  );
$$;

-- Does this batch's sport belong to the caller? (NULL sport → false.)
create or replace function public.batch_in_my_sport(p_batch_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.batches b
    where b.id = p_batch_id
      and public.head_coach_owns_sport(b.sport_id)
  );
$$;

-- Batch writer check WITH sport context (batches carry both center_id +
-- sport_id). head_coach is narrowed to own center AND own sport; everyone else
-- as before. Used by the batches + enrollment policies. (can_manage_batches —
-- center-only — is kept for events, which are not sport-bound.)
create or replace function public.can_manage_batch_fields(
  p_center_id uuid,
  p_sport_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case (select role from public.users where id = auth.uid())
    when 'academy_owner' then true
    when 'academy_admin' then true
    when 'center_admin'  then
      p_center_id is null or p_center_id = public.current_user_center_id()
    when 'head_coach'    then
      (p_center_id is null or p_center_id = public.current_user_center_id())
      and public.head_coach_owns_sport(p_sport_id)
    else false
  end;
$$;

grant execute on function public.head_coach_owns_sport(uuid)        to authenticated;
grant execute on function public.batch_in_my_sport(uuid)            to authenticated;
grant execute on function public.can_manage_batch_fields(uuid, uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- Fold the sport gate into the existing ladder helpers (head_coach branch).
-- Full bodies restated (create or replace); only the head_coach branch / the
-- enrollment resolver change.
-- ----------------------------------------------------------------------------

create or replace function public.can_manage_enrollment(p_batch_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.can_manage_batch_fields(
    (select center_id from public.batches where id = p_batch_id),
    (select sport_id  from public.batches where id = p_batch_id)
  );
$$;

create or replace function public.can_mark_attendance(p_batch_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case (select role from public.users where id = auth.uid())
    when 'academy_owner' then true
    when 'academy_admin' then true
    when 'center_admin'  then public.batch_in_my_center(p_batch_id)
    when 'head_coach'    then
      public.batch_in_my_center(p_batch_id)
      and public.batch_in_my_sport(p_batch_id)
    when 'coach'         then public.coach_owns_batch(p_batch_id)
    when 'trainer'       then public.coach_owns_batch(p_batch_id)
    else false
  end;
$$;

create or replace function public.can_record_performance(p_batch_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case (select role from public.users where id = auth.uid())
    when 'academy_owner' then true
    when 'academy_admin' then true
    when 'center_admin'  then p_batch_id is null or public.batch_in_my_center(p_batch_id)
    when 'head_coach'    then
      p_batch_id is null
      or (public.batch_in_my_center(p_batch_id)
          and public.batch_in_my_sport(p_batch_id))
    when 'coach'         then p_batch_id is null or public.coach_owns_batch(p_batch_id)
    else false  -- trainer + end-user roles (Phase 3 adds trainer)
  end;
$$;

-- ============================================================================
-- batches — swap the center-only gate for the sport-aware one.
-- (Read policy unchanged. Events keep can_manage_batches — not sport-bound.)
-- ============================================================================
drop policy batches_insert on public.batches;
drop policy batches_update on public.batches;
drop policy batches_delete on public.batches;

create policy batches_insert on public.batches
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_batch_fields(center_id, sport_id))
  );

create policy batches_update on public.batches
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_batch_fields(center_id, sport_id))
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_batch_fields(center_id, sport_id))
  );

create policy batches_delete on public.batches
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_batch_fields(center_id, sport_id))
  );

-- ============================================================================
-- center_sports — let center_admin enable/rename/remove sports for THEIR
-- center (was has_admin_or_higher → admin-only). can_admin_center_scope already
-- encodes "admin tier any center, center_admin own center".
-- ============================================================================
drop policy center_sports_admin_insert on public.center_sports;
drop policy center_sports_admin_update on public.center_sports;
drop policy center_sports_admin_delete on public.center_sports;

create policy center_sports_write_insert on public.center_sports
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_admin_center_scope(center_id))
  );

create policy center_sports_write_update on public.center_sports
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_admin_center_scope(center_id))
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_admin_center_scope(center_id))
  );

create policy center_sports_write_delete on public.center_sports
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_admin_center_scope(center_id))
  );



-- ##########################################################################
-- ## 20260607000300_batch_staff_trainer_scope.sql
-- ##########################################################################

-- ============================================================================
-- Phase 3 — trainer→student scope, coach→student enrollment, trainer perf.
--
-- The org model wants:
--   • coach   → assigns students (enrol into THEIR OWN batch) + creates trainers
--   • trainer → limited to THEIR students, manages attendance + performance
--
-- "A trainer's students" needs a structure: a batch carries a coach
-- (batches.coach_id) plus zero-or-more assigned trainers (the new batch_staff).
-- A trainer's scope = students enrolled in the batches they staff.
--
--   staff_on_batch(b)        = caller is the batch's coach OR an assigned staffer
--   student_assigned_to_me(s)= s is actively enrolled in a batch I staff
--   can_staff_batch(b)       = who may add/remove staff on a batch (the coach +
--                              management tiers)
--
-- Changes vs Phase 2:
--   • coach can now ENROL into their own batch (can_manage_enrollment).
--   • trainer GAINS performance (was else-false) — scoped to their batches.
--   • attendance/perf "coach"+"trainer" branches use staff_on_batch, so an
--     assigned co-coach/trainer (not just batches.coach_id) is covered.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- batch_staff — additional staff (trainers / assistant coaches) on a batch.
-- The primary coach stays on batches.coach_id; this is for everyone else.
-- ----------------------------------------------------------------------------
create table public.batch_staff (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies(id) on delete cascade,
  batch_id uuid not null references public.batches(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  role text not null default 'trainer'
    check (role in ('trainer', 'assistant_coach')),
  created_at timestamptz not null default now(),
  unique (batch_id, user_id)
);

create index idx_batch_staff_batch on public.batch_staff(batch_id);
create index idx_batch_staff_user on public.batch_staff(user_id);

alter table public.batch_staff enable row level security;

-- ----------------------------------------------------------------------------
-- Scope helpers
-- ----------------------------------------------------------------------------

-- Is the caller staff on this batch — its coach (batches.coach_id) or an
-- assigned trainer/assistant (batch_staff)?
create or replace function public.staff_on_batch(p_batch_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.coach_owns_batch(p_batch_id)
    or exists (
      select 1 from public.batch_staff bs
      where bs.batch_id = p_batch_id and bs.user_id = auth.uid()
    );
$$;

-- Is this student actively enrolled in a batch the caller staffs?
-- (This is "a trainer's / coach's students".)
create or replace function public.student_assigned_to_me(p_student_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.batch_enrollments e
    where e.student_id = p_student_id
      and e.enrollment_status = 'active'
      and public.staff_on_batch(e.batch_id)
  );
$$;

-- Who may add/remove staff on a batch: the batch's coach, plus the management
-- tiers that can manage the batch itself (admin / center_admin / head_coach-sport).
create or replace function public.can_staff_batch(p_batch_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.coach_owns_batch(p_batch_id)
    or public.can_manage_batch_fields(
         (select center_id from public.batches where id = p_batch_id),
         (select sport_id  from public.batches where id = p_batch_id)
       );
$$;

grant execute on function public.staff_on_batch(uuid)          to authenticated;
grant execute on function public.student_assigned_to_me(uuid)  to authenticated;
grant execute on function public.can_staff_batch(uuid)         to authenticated;

-- ----------------------------------------------------------------------------
-- batch_staff RLS — academy-scoped read; writes gated by can_staff_batch.
-- ----------------------------------------------------------------------------
create policy batch_staff_academy_read on public.batch_staff
  for select using (
    public.is_super_admin()
    or academy_id = public.current_user_academy_id()
  );

create policy batch_staff_write_insert on public.batch_staff
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_staff_batch(batch_id))
  );

create policy batch_staff_write_update on public.batch_staff
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_staff_batch(batch_id))
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_staff_batch(batch_id))
  );

create policy batch_staff_write_delete on public.batch_staff
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_staff_batch(batch_id))
  );

create trigger trg_audit_batch_staff
  after insert or update or delete on public.batch_staff
  for each row execute function public.write_audit_log();

-- ----------------------------------------------------------------------------
-- Fold the new scope into the ladder helpers.
-- ----------------------------------------------------------------------------

-- Enrollment: management tiers (sport-aware) OR the batch's own coach.
create or replace function public.can_manage_enrollment(p_batch_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.can_manage_batch_fields(
           (select center_id from public.batches where id = p_batch_id),
           (select sport_id  from public.batches where id = p_batch_id)
         )
      or public.coach_owns_batch(p_batch_id);
$$;

-- Attendance: coach + trainer branches become "staff on the batch" (covers
-- batches.coach_id AND assigned trainers/assistants).
create or replace function public.can_mark_attendance(p_batch_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case (select role from public.users where id = auth.uid())
    when 'academy_owner' then true
    when 'academy_admin' then true
    when 'center_admin'  then public.batch_in_my_center(p_batch_id)
    when 'head_coach'    then
      public.batch_in_my_center(p_batch_id)
      and public.batch_in_my_sport(p_batch_id)
    when 'coach'         then public.staff_on_batch(p_batch_id)
    when 'trainer'       then public.staff_on_batch(p_batch_id)
    else false
  end;
$$;

-- Performance: trainer is now GRANTED (scoped to their batches via
-- staff_on_batch); coach likewise via staff_on_batch.
create or replace function public.can_record_performance(p_batch_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case (select role from public.users where id = auth.uid())
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
  end;
$$;



-- ##########################################################################
-- ## 20260607000400_center_scoped_finance.sql
-- ##########################################################################

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



-- ##########################################################################
-- ## 20260607000500_center_read_isolation.sql
-- ##########################################################################

-- ============================================================================
-- Phase 5 — finish center_admin READ isolation on the secondary lists, and
-- align announcement reads to actual delivery.
--
-- center_narrowed_rls (20260509000400) already narrowed center_admin reads on
-- students / batches / enrollments / attendance / performance_* / invoices, and
-- Phase 4 narrowed payments + fee/discount assignments. This closes the
-- remaining academy-wide reads a center_admin shouldn't have:
--   coaches, leads, inventory_items, events, batch_staff → their own center.
--
-- Each rides the existing center_admin_sees_center / center_admin_sees_batch
-- helpers, which SHORT-CIRCUIT to true for every non-center_admin role — so
-- admins stay academy-wide and coaches/parents/students are unaffected.
--
-- Announcements: the per-user feed is the announcement_recipients rows; the
-- base table was readable academy-wide. Narrow it so non-admins see only
-- announcements delivered to them (or that they created), matching the feed.
-- (Admins keep the full compose/history view.)
--
-- NOT in scope (flagged): NULL-center semantics still mean "visible to every
-- center_admin" (a soft widening), and materialized KPI/analytics views bypass
-- RLS so dashboards may show academy-wide aggregates to a center_admin. Both
-- need a dedicated, signed-off change.
-- ============================================================================

-- coaches → center_admin sees their own center's coaches.
drop policy coaches_academy_read on public.coaches;
create policy coaches_academy_read on public.coaches
  for select using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.center_admin_sees_center(center_id))
  );

-- leads → center_admin sees their own center's leads (by preferred_center_id);
-- parents/students still excluded.
drop policy leads_academy_read on public.leads;
create policy leads_academy_read on public.leads
  for select using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.current_user_role() not in ('parent', 'student')
      and public.center_admin_sees_center(preferred_center_id)
    )
  );

-- inventory_items → center_admin sees their own center's items.
drop policy inv_items_academy_read on public.inventory_items;
create policy inv_items_academy_read on public.inventory_items
  for select using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.current_user_role() not in ('parent', 'student')
      and public.center_admin_sees_center(center_id)
    )
  );

-- events → center_admin sees their own center's events; the published-event
-- visibility for parents/students is preserved (they're not center_admins, so
-- center_admin_sees_center short-circuits true for them).
drop policy events_academy_read on public.events;
create policy events_academy_read on public.events
  for select using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.center_admin_sees_center(center_id)
      and (
        public.current_user_role() not in ('parent', 'student')
        or status in ('published', 'registration_closed', 'in_progress', 'completed')
      )
    )
  );

-- batch_staff → center_admin sees assignments for their own center's batches.
drop policy batch_staff_academy_read on public.batch_staff;
create policy batch_staff_academy_read on public.batch_staff
  for select using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.center_admin_sees_batch(batch_id))
  );

-- announcements → non-admins see only announcements delivered to them (a
-- recipient row) or that they created; admins keep the full academy view.
drop policy announcements_academy_read on public.announcements;
create policy announcements_read on public.announcements
  for select using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and (
        public.has_admin_or_higher()
        or created_by = auth.uid()
        or exists (
          select 1 from public.announcement_recipients r
          where r.announcement_id = announcements.id
            and r.user_id = auth.uid()
        )
      )
    )
  );



-- ============================================================================
-- All 6 hierarchy migrations applied. Review the result, then commit:
commit;
