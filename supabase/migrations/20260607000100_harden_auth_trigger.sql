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
