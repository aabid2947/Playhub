-- ============================================================================
-- FIX: invited users land as academy_owner/NULL (and cannot log in).
--
-- ROOT CAUSE (proven): on this GoTrue version, invited_at + invite metadata are
-- written AFTER the auth.users INSERT, not during it. So at INSERT-trigger time
-- invited_at is NULL:
--   * handle_new_auth_user sees no trusted source -> role defaults to owner/NULL
--   * dev_autopassword sees invited_at NULL -> skips the test password
--
-- FIX part 1 (PROD-worthy): reconcile the public.users row on the UPDATE where
--   GoTrue finally sets invited_at + metadata. Only touches rows still at the
--   untrusted default (role=academy_owner AND academy_id IS NULL), so it never
--   clobbers a later legitimate change. Does not write auth.users -> no recursion.
-- FIX part 2 (DEV-only): gate the test password on "row has no password yet"
--   (true for any invited user at INSERT) instead of invited_at.
--
-- handle_new_auth_user is left as-is (still correct for the app_metadata path
-- and for self-signups). Run in the Supabase SQL editor of the hosted project.
-- ============================================================================

-- ---- Part 1: reconcile invited users once invited_at is set ----------------
create or replace function public.reconcile_invited_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_user jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  v_role public.user_role := (v_user->>'role')::public.user_role;
  v_academy_id uuid := nullif(v_user->>'academy_id','')::uuid;
  v_center_id uuid := nullif(v_user->>'center_id','')::uuid;
  v_link_student_id uuid := nullif(v_user->>'link_to_student_id','')::uuid;
  v_link_relationship text := coalesce(v_user->>'link_relationship','parent');
  v_link_coach_id uuid := nullif(v_user->>'link_coach_id','')::uuid;
  v_link_student_login_id uuid := nullif(v_user->>'link_student_login_id','')::uuid;
begin
  update public.users
     set role = v_role,
         academy_id = v_academy_id,
         center_id = v_center_id,
         first_name = coalesce(nullif(v_user->>'first_name',''), first_name),
         last_name  = coalesce(nullif(v_user->>'last_name',''),  last_name)
   where id = new.id and role = 'academy_owner' and academy_id is null;

  if v_role = 'parent' and v_link_student_id is not null and v_academy_id is not null then
    insert into public.parent_links (academy_id, parent_user_id, student_id, relationship, is_primary)
    values (v_academy_id, new.id, v_link_student_id, v_link_relationship, true)
    on conflict do nothing;
  end if;
  if v_link_coach_id is not null then
    update public.coaches set user_id = new.id where id = v_link_coach_id;
  end if;
  if v_link_student_login_id is not null then
    update public.students set user_id = new.id where id = v_link_student_login_id;
  end if;
  return new;
end $$;

drop trigger if exists trg_reconcile_invited on auth.users;
create trigger trg_reconcile_invited
  after update on auth.users
  for each row
  when (new.invited_at is not null and new.raw_user_meta_data ? 'role')
  execute function public.reconcile_invited_user();

-- ---- Part 2 (DEV-ONLY): set Test@1234 on any password-less user at insert ---
create or replace function public.dev_autopassword_on_invite()
returns trigger language plpgsql security definer set search_path = auth, extensions, public as $$
begin
  if new.encrypted_password is null or new.encrypted_password = '' then
    new.encrypted_password := crypt('Test@1234', gen_salt('bf'));
    new.email_confirmed_at := coalesce(new.email_confirmed_at, now());
  end if;
  return new;
end $$;
-- (trg_dev_autopassword BEFORE INSERT already exists; only its function changed.)
