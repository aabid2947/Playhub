-- ============================================================================
-- PlayHub — Announcements: scoped compose for coaches + photos/videos.
-- Paste-and-run in the Supabase SQL editor. Idempotent (safe to re-run).
--
-- Mirrors migration 20260608000000_announcement_compose_and_media.sql. If you
-- apply this by hand, the migration file is already in supabase/migrations, so
-- a future `supabase db reset` will replay the same DDL — that is expected and
-- harmless (this is the same statements, guarded with IF [NOT] EXISTS).
-- ============================================================================

-- ---------- New columns ------------------------------------------------------
alter table public.announcements
  add column if not exists target_sports uuid[] not null default array[]::uuid[];

-- Attached photos/videos. Each element: { "path", "type": image|video, "mime" }.
alter table public.announcements
  add column if not exists media jsonb not null default '[]'::jsonb;

-- ---------- Scope validator --------------------------------------------------
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
    return v_has_batches;
  end if;

  return false;  -- trainer / parent / student: cannot compose
end;
$$;

grant execute on function public.can_target_announcement(
  public.user_role[], uuid[], uuid[], uuid[]
) to authenticated;

-- ---------- Recompose the write policies -------------------------------------
drop policy if exists announcements_admin_insert   on public.announcements;
drop policy if exists announcements_admin_update   on public.announcements;
drop policy if exists announcements_admin_delete   on public.announcements;
drop policy if exists announcements_compose_insert on public.announcements;
drop policy if exists announcements_compose_update on public.announcements;
drop policy if exists announcements_compose_delete on public.announcements;

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

-- ---------- announcement_media storage bucket + policies ---------------------
insert into storage.buckets (id, name, public)
values ('announcement_media', 'announcement_media', false)
on conflict (id) do nothing;

drop policy if exists "announcement_media_member_select"  on storage.objects;
drop policy if exists "announcement_media_compose_insert" on storage.objects;
drop policy if exists "announcement_media_compose_update" on storage.objects;
drop policy if exists "announcement_media_compose_delete" on storage.objects;

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
