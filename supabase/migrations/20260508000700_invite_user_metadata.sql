-- ============================================================================
-- Sprint-4 follow-up: extend handle_new_auth_user to honour academy_id +
-- center_id from raw_user_meta_data, and to perform auto-linking when an
-- invited user accepts.
--
-- Metadata keys recognised:
--   role                   public.user_role     (already supported)
--   first_name, last_name  text                 (already supported)
--   academy_id             uuid                 NEW
--   center_id              uuid                 NEW
--   link_to_student_id     uuid                 NEW — create parent_link
--   link_relationship      text                 NEW — parent_link.relationship
--   link_coach_id          uuid                 NEW — set coaches.user_id
--   link_student_login_id  uuid                 NEW — set students.user_id
--
-- Inserts to parent_links / coaches / students bypass RLS (this trigger is
-- SECURITY DEFINER) but only act on rows the inviting admin already had
-- write access to via the invite-user Edge Function. The Edge Function is
-- the gate that validates academy ownership; the trigger is just the
-- finalisation step on user acceptance.
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
begin
  insert into public.users (
    id, email, phone, role, first_name, last_name, academy_id, center_id
  ) values (
    new.id,
    new.email,
    new.phone,
    v_role,
    v_meta->>'first_name',
    v_meta->>'last_name',
    v_academy_id,
    v_center_id
  )
  on conflict (id) do nothing;

  -- Parent linking — applicable only when role is 'parent' and an invite
  -- carried link_to_student_id.
  if v_role = 'parent' and v_link_student_id is not null and v_academy_id is not null then
    insert into public.parent_links
      (academy_id, parent_user_id, student_id, relationship, is_primary)
    values
      (v_academy_id, new.id, v_link_student_id, v_link_relationship, true)
    on conflict do nothing;
  end if;

  -- Coach login — connects the new user to an existing coaches row.
  if v_link_coach_id is not null then
    update public.coaches set user_id = new.id where id = v_link_coach_id;
  end if;

  -- Student login — connects the new user to an existing students row.
  if v_link_student_login_id is not null then
    update public.students set user_id = new.id where id = v_link_student_login_id;
  end if;

  return new;
end;
$$;
