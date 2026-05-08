-- ============================================================================
-- Sprint-4 follow-up: invitees land on the "set password" screen.
--
-- Supabase's invite flow signs the user in directly when they click the
-- magic link — they end up with a session but no password set. The
-- existing `must_change_password` column on public.users (added Sprint 0,
-- never used) is exactly the gate we need.
--
-- Strategy: when handle_new_auth_user creates the public.users row from
-- an invited auth.users row, set must_change_password = true whenever
-- the metadata carries our `role` key — i.e., this was an admin-driven
-- invite, not a self-signup. The Flutter shell reads the column and
-- routes to /reset-password until the user sets a password (the
-- SetNewPasswordPage clears the flag after a successful save).
-- ============================================================================

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_meta jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  v_role public.user_role :=
    coalesce((v_meta->>'role')::public.user_role, 'student');
  v_academy_id uuid := nullif(v_meta->>'academy_id', '')::uuid;
  v_center_id uuid := nullif(v_meta->>'center_id', '')::uuid;
  v_link_student_id uuid := nullif(v_meta->>'link_to_student_id', '')::uuid;
  v_link_relationship text := coalesce(v_meta->>'link_relationship', 'parent');
  v_link_coach_id uuid := nullif(v_meta->>'link_coach_id', '')::uuid;
  v_link_student_login_id uuid := nullif(v_meta->>'link_student_login_id', '')::uuid;
  v_must_change boolean := (
    v_meta ? 'role' and v_academy_id is not null
  );
begin
  insert into public.users (
    id, email, phone, role, first_name, last_name,
    academy_id, center_id, must_change_password
  ) values (
    new.id,
    new.email,
    new.phone,
    v_role,
    v_meta->>'first_name',
    v_meta->>'last_name',
    v_academy_id,
    v_center_id,
    v_must_change
  )
  on conflict (id) do nothing;

  if v_role = 'parent' and v_link_student_id is not null and v_academy_id is not null then
    insert into public.parent_links
      (academy_id, parent_user_id, student_id, relationship, is_primary)
    values
      (v_academy_id, new.id, v_link_student_id, v_link_relationship, true)
    on conflict do nothing;
  end if;

  if v_link_coach_id is not null then
    update public.coaches set user_id = new.id where id = v_link_coach_id;
  end if;

  if v_link_student_login_id is not null then
    update public.students set user_id = new.id where id = v_link_student_login_id;
  end if;

  return new;
end;
$$;
