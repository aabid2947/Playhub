-- ============================================================================
-- FIX: reassert public.handle_new_auth_user() on the hosted DB (drift repair).
--
-- WHY: the live trigger function had drifted - it ignored ALL provisioning
-- metadata and inserted every new auth user as role=academy_owner /
-- academy_id=NULL, regardless of app_metadata (service-role createUser) OR the
-- invited_at->user_metadata invite path. Proven empirically: an invite with
-- invited_at + user_metadata.role='coach' set atomically at insert still landed
-- as academy_owner/NULL. The CORRECT body already lives in
-- migrations/20260614000500_signup_default_owner.sql but was never applied here.
--
-- This script is a pure CREATE OR REPLACE of the authoritative version +
-- an idempotent trigger re-attach. Safe to run repeatedly. It changes NO
-- existing rows (fixes only how FUTURE auth users are provisioned) - so it is
-- exactly what a wipe+reseed needs to produce working demo logins.
--
-- Run in the Supabase dashboard SQL editor. Then paste back the two SELECT
-- outputs at the bottom so we can confirm there's no rogue second trigger.
-- ============================================================================

-- ---- 1. Authoritative function body (identical to 20260614000500) ----------
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
  -- Untrusted self-signup -> academy_owner (creating their own academy); a
  -- trusted source can still specify any role explicitly.
  v_role public.user_role :=
    coalesce((v_trusted->>'role')::public.user_role, 'academy_owner');
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

  -- Parent linking - only when role is 'parent' and the invite carried a link.
  if v_role = 'parent' and v_link_student_id is not null
     and v_academy_id is not null then
    insert into public.parent_links
      (academy_id, parent_user_id, student_id, relationship, is_primary)
    values
      (v_academy_id, new.id, v_link_student_id, v_link_relationship, true)
    on conflict do nothing;
  end if;

  -- Coach login - connect the new user to an existing coaches row.
  if v_link_coach_id is not null then
    update public.coaches set user_id = new.id where id = v_link_coach_id;
  end if;

  -- Student login - connect the new user to an existing students row.
  if v_link_student_login_id is not null then
    update public.students set user_id = new.id where id = v_link_student_login_id;
  end if;

  return new;
end;
$$;

-- ---- 2. Re-attach the trigger idempotently (guards a dropped/renamed one) ---
drop trigger if exists trg_on_auth_user_created on auth.users;
create trigger trg_on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();

-- ---- 3. Diagnostics - paste BOTH outputs back --------------------------------
-- (a) Every non-internal trigger on auth.users. There must be EXACTLY ONE
--     (trg_on_auth_user_created). A second/rogue trigger inserting first would
--     re-introduce the bug via `on conflict do nothing`.
select tgname, pg_get_triggerdef(oid) as def
from pg_trigger
where tgrelid = 'auth.users'::regclass and not tgisinternal;

-- (b) Confirm the function now contains the trusted-source logic.
select proname,
       (prosrc like '%v_app ? ''role''%')      as reads_app_metadata,
       (prosrc like '%invited_at is not null%') as reads_invite_path
from pg_proc
where proname = 'handle_new_auth_user';
