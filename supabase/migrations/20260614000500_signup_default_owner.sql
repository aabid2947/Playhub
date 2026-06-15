-- ============================================================================
-- Self-signup defaults to academy_owner (was 'student'). [Issue: signup role]
--
-- A plain self-signup is someone creating their OWN academy — they should land
-- as academy_owner, not student. Today the hardened trigger (20260607000100)
-- defaults untrusted signups to 'student'; that only "worked" because the signup
-- form immediately calls bootstrap_owner_academy() when email confirmation is
-- OFF. With email confirmation ON, the user verifies, signs in, and is stuck as
-- a student (no inline bootstrap) — the bug the client reported.
--
-- Fix: default the role to 'academy_owner'. Everything else about the security
-- hardening is unchanged — privileged fields (academy_id / center_id / a non-
-- default role / links) are STILL only honoured from a trusted source
-- (app_metadata, or user_metadata when invited_at is set). So:
--   • self-signup → academy_owner with academy_id = NULL. An owner with no
--     academy can't read/write ANY tenant (every RLS gate is academy_id =
--     current_user_academy_id(), which is NULL → matches nothing) — they can
--     only call bootstrap_owner_academy() on their own row. No escalation.
--   • RoleDashboard sees needsAcademySetup (owner + null academy) and shows the
--     SetupAcademyPage → bootstrap → home. The email-confirm path now completes.
--   • Invited users (parent/coach/etc.) are unaffected — their role comes from
--     the trusted invite path (invited_at set), not this default.
--   • The forged-academy_id escalation stays closed (academy_id is still NULL
--     for self-signups).
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
  -- Untrusted self-signup → academy_owner (creating their own academy); a
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
