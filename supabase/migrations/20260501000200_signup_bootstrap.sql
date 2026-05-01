-- ============================================================================
-- Sprint 0 close-out: signup metadata capture + owner-academy bootstrap
-- ============================================================================

-- Extend the auth trigger to also pull first_name / last_name from the
-- user_meta_data set during supabase.auth.signUp().
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.users (id, email, phone, role, first_name, last_name)
  values (
    new.id,
    new.email,
    new.phone,
    coalesce((new.raw_user_meta_data->>'role')::public.user_role, 'student'),
    new.raw_user_meta_data->>'first_name',
    new.raw_user_meta_data->>'last_name'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- ----------------------------------------------------------------------------
-- bootstrap_owner_academy(name)
--
-- Called by an authenticated user who wants to create their own academy and
-- become its owner. Atomic: either both the academy row and the user-update
-- happen, or neither do.
--
-- Idempotent: if the user already has an academy, returns the existing one
-- without modification.
--
-- Runs as SECURITY DEFINER so the inserts bypass RLS — but the function
-- only ever acts on auth.uid()'s own rows, so there is no escalation path.
-- ----------------------------------------------------------------------------
create or replace function public.bootstrap_owner_academy(p_academy_name text)
returns public.academies
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_existing_academy_id uuid;
  v_academy public.academies;
  v_clean_name text := nullif(trim(p_academy_name), '');
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  if v_clean_name is null then
    raise exception 'academy_name is required';
  end if;

  -- Idempotency: already linked to an academy
  select academy_id into v_existing_academy_id
  from public.users where id = v_user_id;

  if v_existing_academy_id is not null then
    select * into v_academy from public.academies where id = v_existing_academy_id;
    return v_academy;
  end if;

  -- Create the academy with this user as owner
  insert into public.academies (name, owner_id)
  values (v_clean_name, v_user_id)
  returning * into v_academy;

  -- Promote the user to academy_owner and link them
  update public.users
  set role = 'academy_owner',
      academy_id = v_academy.id
  where id = v_user_id;

  return v_academy;
end;
$$;

revoke all on function public.bootstrap_owner_academy(text) from public;
grant execute on function public.bootstrap_owner_academy(text) to authenticated;
