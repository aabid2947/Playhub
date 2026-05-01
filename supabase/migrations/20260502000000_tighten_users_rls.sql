-- ============================================================================
-- RLS fix: users_admin_write was `for all` without an academy_id filter,
-- which let any academy_owner SELECT every user row in the database.
-- The `tests/rls_tenancy.sql` regression caught it.
--
-- The two existing read policies (users_self_read, users_same_academy_read)
-- correctly scope SELECT. So we replace `users_admin_write` with explicit
-- INSERT / UPDATE / DELETE policies that don't grant a SELECT bypass.
-- ============================================================================

drop policy if exists users_admin_write on public.users;

-- INSERT — admins of an academy create staff records inside it.
-- (Self-signup goes through the SECURITY DEFINER trigger, which bypasses RLS.)
create policy users_admin_insert on public.users
  for insert
  with check (
    public.is_super_admin()
    or (
      academy_id is not null
      and academy_id = public.current_user_academy_id()
      and public.has_admin_or_higher()
    )
  );

-- UPDATE — admins update staff in their academy.
-- (users_self_update already covers self-edits with role-change blocked.)
create policy users_admin_update on public.users
  for update
  using (
    public.is_super_admin()
    or (
      academy_id is not null
      and academy_id = public.current_user_academy_id()
      and public.has_admin_or_higher()
    )
  )
  with check (
    public.is_super_admin()
    or (
      academy_id is not null
      and academy_id = public.current_user_academy_id()
      and public.has_admin_or_higher()
    )
  );

-- DELETE — admins remove staff in their academy.
create policy users_admin_delete on public.users
  for delete
  using (
    public.is_super_admin()
    or (
      academy_id is not null
      and academy_id = public.current_user_academy_id()
      and public.has_admin_or_higher()
    )
  );
