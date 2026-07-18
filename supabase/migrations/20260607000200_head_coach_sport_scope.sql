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
