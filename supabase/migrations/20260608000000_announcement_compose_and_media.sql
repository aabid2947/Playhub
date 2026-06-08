-- ============================================================================
-- Announcements: let coaches / head_coaches / center_admins compose (scoped),
-- add sport targeting, and attach photos/videos.
--
-- BEFORE: only owner/academy_admin (has_admin_or_higher) could insert; the
-- send-announcement fan-out trusted the targeting arrays as-is. That trust is
-- a hole the moment non-admins compose (a coach could broadcast academy-wide),
-- so targeting is now validated against the composer's scope BY RLS — per the
-- invariant that RLS, not app code, is the real gate.
--
-- Scope ladder (mirrors can_manage_batch_fields / coach_owns_batch):
--   academy_owner / academy_admin → anything in the academy (roles too)
--   center_admin                  → own center / its sports / its batches
--   head_coach                    → own-center + own-sport batches / own sports
--   coach                         → only batches they own
-- Non-admins may NOT target by role, and may NOT leave targets empty
-- ("everyone") — they must name a center/sport/batch within their scope.
--
-- Targeting resolution (in send-announcement) treats batch/sport/center as
-- "the FAMILIES in that scope" = enrolled students' logins + their parents.
-- Role targeting (admin-only) remains the way to reach staff.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- New columns
-- ----------------------------------------------------------------------------
alter table public.announcements
  add column target_sports uuid[] not null default array[]::uuid[];

-- Attached photos/videos. Each element: { "path": "<storage path>",
-- "type": "image" | "video", "mime": "image/jpeg" }. Read inline with the
-- announcement; the client builds signed URLs from `path` against the
-- announcement_media bucket. No child table — media inherits the parent's
-- visibility and is always loaded together.
alter table public.announcements
  add column media jsonb not null default '[]'::jsonb;

-- ----------------------------------------------------------------------------
-- Scope validator: is every targeted entity within the caller's reach?
-- SECURITY DEFINER so it can read users/batches/center_sports past RLS.
-- Returns true for admins (any target), scoped-true for center_admin /
-- head_coach / coach, false for everyone else — so it doubles as the
-- "may this role compose at all?" gate.
-- ----------------------------------------------------------------------------
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
  -- Admin tier: anything within the academy (the policy enforces academy match).
  if v_role in ('academy_owner', 'academy_admin') then
    return true;
  end if;

  -- Non-admins: no role targeting, and must name at least one scope.
  if v_has_roles then
    return false;
  end if;
  if not (v_has_batches or v_has_centers or v_has_sports) then
    return false;
  end if;

  if v_role = 'center_admin' then
    foreach c in array coalesce(p_target_centers, '{}'::uuid[]) loop
      if c is distinct from public.current_user_center_id() then
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
        where cs.center_id = public.current_user_center_id()
          and cs.sport_id = s
      ) then
        return false;
      end if;
    end loop;
    return true;

  elsif v_role = 'head_coach' then
    -- No center-wide targeting; batches must be own-center + own-sport, and
    -- any named sport must be one the head_coach owns.
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
    -- Only their own batches — no center/sport targeting.
    if v_has_centers or v_has_sports then
      return false;
    end if;
    foreach b in array coalesce(p_target_batches, '{}'::uuid[]) loop
      if not public.coach_owns_batch(b) then
        return false;
      end if;
    end loop;
    return v_has_batches;
  end if;

  return false;  -- trainer / parent / student: cannot compose
end;
$$;

grant execute on function public.can_target_announcement(
  public.user_role[], uuid[], uuid[], uuid[]
) to authenticated;

-- ----------------------------------------------------------------------------
-- Recompose the write policies: scope-validated compose for the whole ladder.
-- Read policy is unchanged (delivery-scoped; non-admins already see rows they
-- created — 20260607000500). The service-role fan-out keeps writing sent_at /
-- counts past RLS.
-- ----------------------------------------------------------------------------
drop policy announcements_admin_insert on public.announcements;
drop policy announcements_admin_update on public.announcements;
drop policy announcements_admin_delete on public.announcements;

create policy announcements_compose_insert on public.announcements
  for insert with check (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.can_target_announcement(
        target_roles, target_batches, target_centers, target_sports
      )
    )
  );

-- Edit: admins any row in their academy; non-admin composers only their own,
-- and the (possibly changed) targeting is re-validated against their scope.
create policy announcements_compose_update on public.announcements
  for update using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and (public.has_admin_or_higher() or created_by = auth.uid())
    )
  )
  with check (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
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
      and (public.has_admin_or_higher() or created_by = auth.uid())
    )
  );

-- ============================================================================
-- announcement_media — private storage bucket for announcement photos/videos.
--   Path layout: <academy_id>/announcements/<announcement_id>/<uuid>.<ext>
--   Same same-academy folder pattern + signed-URL reads as performance_media.
--   Read:  any same-academy member (announcements are an academy broadcast).
--   Write: anyone who may compose (has_coach_or_higher), same academy.
-- ============================================================================
insert into storage.buckets (id, name, public)
values ('announcement_media', 'announcement_media', false)
on conflict (id) do nothing;

create policy "announcement_media_member_select"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'announcement_media'
    and (storage.foldername(name))[1] = public.current_user_academy_id()::text
  );

create policy "announcement_media_compose_insert"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'announcement_media'
    and (storage.foldername(name))[1] = public.current_user_academy_id()::text
    and public.has_coach_or_higher()
  );

create policy "announcement_media_compose_update"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'announcement_media'
    and (storage.foldername(name))[1] = public.current_user_academy_id()::text
    and public.has_coach_or_higher()
  );

create policy "announcement_media_compose_delete"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'announcement_media'
    and (storage.foldername(name))[1] = public.current_user_academy_id()::text
    and public.has_coach_or_higher()
  );
