-- ============================================================================
-- Multi-center admins — a center_admin (or any center-scoped staffer) may now
-- be assigned to MORE THAN ONE center.
--
-- Background: until now `users.center_id` was a single FK and every center
-- gate compared `row.center_id = current_user_center_id()`. The client needs
-- one center_admin to manage several centers (e.g. JP Nagar + Satyapura +
-- Arativeli in Bangalore).
--
-- Design (minimal-ripple, RLS stays the gate — invariant #1/#2):
--   • New `user_centers` join table = the EXTRA centers granted to a user.
--     `users.center_id` is kept as the user's PRIMARY/home center (shown in UI,
--     used as the form default); the join table holds the additional grants.
--   • New membership helper `current_user_in_center(center_id)` returns true
--     when center_id is the caller's home center OR appears in user_centers.
--     For a user with NO extra grants this is byte-identical to the old
--     `= current_user_center_id()` check, so single-center roles
--     (head_coach / coach with no grants) are completely unaffected.
--   • Every center-equality check inside the existing scope helpers is swapped
--     for current_user_in_center(...). The RLS POLICIES are untouched — they
--     call the helpers, so read/write across all granted centers "just works"
--     (students, batches, attendance, performance, finance, coaches, leads,
--     inventory, events, provisioning, announcement targeting).
--
-- Who may grant centers: admin tier only (academy_owner / academy_admin /
-- super_admin) — a center_admin can NOT expand their own scope (the write gate
-- is has_admin_or_higher(), which excludes center_admin).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- user_centers — additional center grants (primary center stays on users).
-- ----------------------------------------------------------------------------
create table public.user_centers (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  center_id uuid not null references public.centers(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint user_centers_unique unique (user_id, center_id)
);
create index idx_user_centers_user    on public.user_centers(user_id);
create index idx_user_centers_center  on public.user_centers(center_id);
create index idx_user_centers_academy on public.user_centers(academy_id);

create trigger trg_user_centers_updated before update on public.user_centers
  for each row execute function public.set_updated_at();

-- Useful too: the old single-center model never indexed users.center_id.
create index if not exists idx_users_center on public.users(center_id)
  where center_id is not null;

alter table public.user_centers enable row level security;

-- READ: a user always sees their OWN grants (so the app can load its scope);
-- admin tier sees the whole academy's grants. super_admin sees all.
create policy user_centers_read on public.user_centers
  for select using (
    public.is_super_admin()
    or user_id = auth.uid()
    or (academy_id = public.current_user_academy_id()
        and public.has_admin_or_higher())
  );

-- WRITE: admin tier only, within their academy, and the referenced user +
-- center must both belong to that academy (defence against cross-tenant
-- stitching via a forged academy_id).
create policy user_centers_admin_insert on public.user_centers
  for insert with check (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.has_admin_or_higher()
      and exists (select 1 from public.users u
                   where u.id = user_id and u.academy_id = academy_id)
      and exists (select 1 from public.centers c
                   where c.id = center_id and c.academy_id = academy_id)
    )
  );

create policy user_centers_admin_update on public.user_centers
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.has_admin_or_higher())
  ) with check (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.has_admin_or_higher()
      and exists (select 1 from public.users u
                   where u.id = user_id and u.academy_id = academy_id)
      and exists (select 1 from public.centers c
                   where c.id = center_id and c.academy_id = academy_id)
    )
  );

create policy user_centers_admin_delete on public.user_centers
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.has_admin_or_higher())
  );

-- ----------------------------------------------------------------------------
-- current_user_in_center — the new membership vocabulary. NULL handling stays
-- with the callers (they keep their `center_id is null or ...` relaxation),
-- so this only answers the non-null "is this one of MY centers?" question.
-- ----------------------------------------------------------------------------
create or replace function public.current_user_in_center(p_center_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p_center_id is not null
    and (
      p_center_id = (select center_id from public.users where id = auth.uid())
      or exists (
        select 1 from public.user_centers uc
        where uc.user_id = auth.uid()
          and uc.center_id = p_center_id
      )
    );
$$;

grant execute on function public.current_user_in_center(uuid) to authenticated;

-- ============================================================================
-- Restate the scope helpers, swapping `= current_user_center_id()` (and the
-- inline `= (select center_id from users …)`) for current_user_in_center(…).
-- Bodies are otherwise identical to their latest definitions — only the center
-- membership test changes. Single-center users see no behavioural difference.
-- ============================================================================

-- --- center_admin read helpers (20260509000400) -----------------------------
create or replace function public.center_admin_sees_center(p_center_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select case
    when (select role from public.users where id = auth.uid()) <> 'center_admin'
      then true
    else
      p_center_id is null
      or public.current_user_in_center(p_center_id)
  end;
$$;

create or replace function public.center_admin_sees_student(p_student_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select case
    when (select role from public.users where id = auth.uid()) <> 'center_admin'
      then true
    else
      exists (
        select 1 from public.students s
        where s.id = p_student_id
          and (s.center_id is null
               or public.current_user_in_center(s.center_id))
      )
  end;
$$;

create or replace function public.center_admin_sees_batch(p_batch_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select case
    when (select role from public.users where id = auth.uid()) <> 'center_admin'
      then true
    else
      exists (
        select 1 from public.batches b
        where b.id = p_batch_id
          and (b.center_id is null
               or public.current_user_in_center(b.center_id))
      )
  end;
$$;

-- --- batch_in_my_center (20260527000000) ------------------------------------
create or replace function public.batch_in_my_center(p_batch_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.batches b
    where b.id = p_batch_id
      and (b.center_id is null
           or public.current_user_in_center(b.center_id))
  );
$$;

-- --- can_admin_center_scope (20260527000000) — feeds students/coaches/leads/
--     inventory/center_sports writes AND all of center-scoped finance. --------
create or replace function public.can_admin_center_scope(p_center_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select case (select role from public.users where id = auth.uid())
    when 'academy_owner' then true
    when 'academy_admin' then true
    when 'center_admin'  then
      p_center_id is null or public.current_user_in_center(p_center_id)
    else false
  end;
$$;

-- --- can_manage_batches (20260527000000) — events (center, not sport-bound) --
create or replace function public.can_manage_batches(p_center_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select case (select role from public.users where id = auth.uid())
    when 'academy_owner' then true
    when 'academy_admin' then true
    when 'center_admin'  then
      p_center_id is null or public.current_user_in_center(p_center_id)
    when 'head_coach'    then
      p_center_id is null or public.current_user_in_center(p_center_id)
    else false
  end;
$$;

-- --- student_in_my_center (20260606000000) — standalone media gate ----------
create or replace function public.student_in_my_center(p_student_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select coalesce((
    select s.center_id is null
        or public.current_user_in_center(s.center_id)
    from public.students s
    where s.id = p_student_id
  ), false);
$$;

-- --- can_provision_role (20260607000000) — who may create whom --------------
create or replace function public.can_provision_role(
  p_target_role public.user_role,
  p_center_id uuid
)
returns boolean language sql stable security definer set search_path = public
as $$
  select case
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
  end;
$$;

-- --- can_manage_batch_fields (latest 20260607000600) — batch writes ---------
create or replace function public.can_manage_batch_fields(
  p_center_id uuid,
  p_sport_id uuid
)
returns boolean language sql stable security definer set search_path = public
as $$
  select case (select role from public.users where id = auth.uid())
    when 'academy_owner' then true
    when 'academy_admin' then true
    when 'center_admin'  then
      p_center_id is null or public.current_user_in_center(p_center_id)
    when 'head_coach'    then
      (p_center_id is null or public.current_user_in_center(p_center_id))
      and (p_sport_id is null or public.head_coach_owns_sport(p_sport_id))
    else false
  end;
$$;

-- --- can_manage_student (latest 20260608000200) — student create/edit -------
create or replace function public.can_manage_student(p_center_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select case (select role from public.users where id = auth.uid())
    when 'academy_owner' then true
    when 'academy_admin' then true
    when 'center_admin'  then
      p_center_id is null or public.current_user_in_center(p_center_id)
    when 'head_coach'    then
      p_center_id is null or public.current_user_in_center(p_center_id)
    else false
  end;
$$;

-- --- can_manage_coach_record (20260607000800) — coach create/edit -----------
create or replace function public.can_manage_coach_record(p_center_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select case (select role from public.users where id = auth.uid())
    when 'academy_owner' then true
    when 'academy_admin' then true
    when 'center_admin'  then
      p_center_id is null or public.current_user_in_center(p_center_id)
    when 'head_coach'    then
      p_center_id is null or public.current_user_in_center(p_center_id)
    else false
  end;
$$;

-- --- head_coach_sees_coach (20260608000100) — coaches read narrowing --------
create or replace function public.head_coach_sees_coach(p_coach_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select case (select role from public.users where id = auth.uid())
    when 'head_coach' then exists (
      select 1
      from public.coaches c
      where c.id = p_coach_id
        and (c.center_id is null
             or public.current_user_in_center(c.center_id))
        and (
          not exists (
            select 1 from public.coach_sports cs where cs.coach_id = c.id
          )
          or exists (
            select 1 from public.coach_sports cs
            where cs.coach_id = c.id
              and public.head_coach_owns_sport(cs.sport_id)
          )
        )
    )
    else true
  end;
$$;

-- --- can_target_announcement (20260608000000) — center_admin/head_coach
--     compose targeting. Only the center-membership tests change; head_coach
--     stays sport-scoped. NOTE: send-announcement still resolves sport-target
--     recipients against current_user_center_id() (primary center only) — a
--     multi-center center_admin targeting a sport enabled only at a NON-primary
--     center will pass validation but reach no one there until that edge fn is
--     widened. Tracked in the change log.
create or replace function public.can_target_announcement(
  p_target_roles   public.user_role[],
  p_target_batches uuid[],
  p_target_centers uuid[],
  p_target_sports  uuid[]
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_role public.user_role := (select role from public.users where id = auth.uid());
  b uuid;
  c uuid;
  s uuid;
  v_has_roles   boolean := coalesce(array_length(p_target_roles,   1), 0) > 0;
  v_has_batches boolean := coalesce(array_length(p_target_batches, 1), 0) > 0;
  v_has_centers boolean := coalesce(array_length(p_target_centers, 1), 0) > 0;
  v_has_sports  boolean := coalesce(array_length(p_target_sports,  1), 0) > 0;
begin
  if v_role in ('academy_owner', 'academy_admin') then
    return true;
  end if;

  if v_has_roles then
    return false;
  end if;
  if not (v_has_batches or v_has_centers or v_has_sports) then
    return false;
  end if;

  if v_role = 'center_admin' then
    foreach c in array coalesce(p_target_centers, '{}'::uuid[]) loop
      if not public.current_user_in_center(c) then
        return false;
      end if;
    end loop;
    foreach b in array coalesce(p_target_batches, '{}'::uuid[]) loop
      if not public.batch_in_my_center(b) then
        return false;
      end if;
    end loop;
    foreach s in array coalesce(p_target_sports, '{}'::uuid[]) loop
      if not exists (
        select 1 from public.center_sports cs
        where public.current_user_in_center(cs.center_id)
          and cs.sport_id = s
      ) then
        return false;
      end if;
    end loop;
    return true;

  elsif v_role = 'head_coach' then
    if v_has_centers then
      return false;
    end if;
    foreach b in array coalesce(p_target_batches, '{}'::uuid[]) loop
      if not (public.batch_in_my_center(b) and public.batch_in_my_sport(b)) then
        return false;
      end if;
    end loop;
    foreach s in array coalesce(p_target_sports, '{}'::uuid[]) loop
      if not public.head_coach_owns_sport(s) then
        return false;
      end if;
    end loop;
    return true;

  elsif v_role = 'coach' then
    if v_has_centers or v_has_sports then
      return false;
    end if;
    foreach b in array coalesce(p_target_batches, '{}'::uuid[]) loop
      if not public.coach_owns_batch(b) then
        return false;
      end if;
    end loop;
    return true;
  end if;

  return false;
end;
$$;
