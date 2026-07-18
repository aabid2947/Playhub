-- COMBINED branch migrations (ui-revamo) — run ONCE against a DB already at main.
-- Every migration unique to this branch, in timestamp order, in one transaction.
-- All DROPs are guarded (if exists) and functions use create-or-replace, so it
-- is safe to re-run / safe if some parts were already applied.
--
-- Order:
--   1. 20260605000000_perf_media_parent_scope
--   2. 20260606000000_trainer_student_media
--   3. 20260606000100_batch_thread_admin_participant
--   4. 20260606000200_center_admin_vendors_items
--   5. 20260606000300_center_admin_coach_sports
--
-- Prereq: the DB has main (incl. 20260527* role capabilities providing
-- can_admin_center_scope / can_manage_enrollment / can_manage_batches).

begin;

-- 1) perf_media_parent_scope
--    Narrow the performance_media STORAGE read policy to mirror table-level
--    parent/student scoping. Staff keep academy-wide read.
create index if not exists idx_perf_media_file_path
  on public.performance_media (file_path);

drop policy if exists "perf_media_member_select" on storage.objects;

create policy "perf_media_member_select"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'performance_media'
    and (storage.foldername(name))[1] = public.current_user_academy_id()::text
    and (
      public.current_user_role() not in ('parent', 'student')
      or exists (
        select 1
        from public.performance_media pm
        where pm.file_path = storage.objects.name
          and public.parent_can_see_student(pm.student_id)
      )
    )
  );

-- 2) trainer_student_media
--    Standalone student media (null assessment_id) gated by
--    can_upload_student_media; trainers/coaches qualify for their own students.
alter table public.performance_media
  alter column assessment_id drop not null;

create or replace function public.student_in_my_batch(p_student_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.batch_enrollments be
    join public.batches b on b.id = be.batch_id
    join public.coaches c on c.id = b.coach_id
    where be.student_id = p_student_id
      and c.user_id = auth.uid()
  );
$$;

create or replace function public.student_in_my_center(p_student_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select s.center_id is null
        or s.center_id = public.current_user_center_id()
    from public.students s
    where s.id = p_student_id
  ), false);
$$;

create or replace function public.can_upload_student_media(p_student_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case (select role from public.users where id = auth.uid())
    when 'academy_owner' then true
    when 'academy_admin' then true
    when 'center_admin'  then public.student_in_my_center(p_student_id)
    when 'head_coach'    then public.student_in_my_center(p_student_id)
    when 'coach'         then public.student_in_my_batch(p_student_id)
    when 'trainer'       then public.student_in_my_batch(p_student_id)
    else false
  end;
$$;

grant execute on function public.student_in_my_batch(uuid)        to authenticated;
grant execute on function public.student_in_my_center(uuid)       to authenticated;
grant execute on function public.can_upload_student_media(uuid)   to authenticated;

drop policy if exists perf_media_write_insert on public.performance_media;
drop policy if exists perf_media_write_update on public.performance_media;
drop policy if exists perf_media_write_delete on public.performance_media;

create policy perf_media_write_insert on public.performance_media
  for insert with check (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and (
        (assessment_id is not null
           and public.can_record_perf_for_assessment(assessment_id))
        or (assessment_id is null
           and public.can_upload_student_media(student_id))
      )
    )
  );

create policy perf_media_write_update on public.performance_media
  for update using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and (
        (assessment_id is not null
           and public.can_record_perf_for_assessment(assessment_id))
        or (assessment_id is null
           and public.can_upload_student_media(student_id))
      )
    )
  ) with check (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and (
        (assessment_id is not null
           and public.can_record_perf_for_assessment(assessment_id))
        or (assessment_id is null
           and public.can_upload_student_media(student_id))
      )
    )
  );

create policy perf_media_write_delete on public.performance_media
  for delete using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and (
        (assessment_id is not null
           and public.can_record_perf_for_assessment(assessment_id))
        or (assessment_id is null
           and public.can_upload_student_media(student_id))
      )
    )
  );

drop policy if exists "perf_media_coach_insert" on storage.objects;
drop policy if exists "perf_media_staff_insert" on storage.objects;

create policy "perf_media_staff_insert"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'performance_media'
    and (storage.foldername(name))[1] = public.current_user_academy_id()::text
    and public.current_user_role() in (
      'academy_owner', 'academy_admin', 'center_admin',
      'head_coach', 'coach', 'trainer'
    )
  );

-- 3) batch_thread_admin_participant
--    ensure_batch_thread() also adds the calling manager as a participant so
--    admins / center_admin / head_coach can read AND post in batch chats.
create or replace function public.ensure_batch_thread(p_batch_id uuid)
returns uuid
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_academy_id uuid;
  v_thread_id uuid;
begin
  select academy_id into v_academy_id from public.batches where id = p_batch_id;
  if v_academy_id is null then
    raise exception 'batch not found';
  end if;
  if v_academy_id is distinct from public.current_user_academy_id() then
    raise exception 'cross-academy access denied';
  end if;

  insert into public.message_threads (academy_id, kind, batch_id, created_by)
  values (v_academy_id, 'batch', p_batch_id, auth.uid())
  on conflict do nothing
  returning id into v_thread_id;

  if v_thread_id is null then
    select id into v_thread_id from public.message_threads
     where kind = 'batch' and batch_id = p_batch_id;
  end if;

  insert into public.thread_participants (thread_id, user_id, academy_id)
  select v_thread_id, c.user_id, v_academy_id
    from public.batches b
    join public.coaches c on c.id = b.coach_id
   where b.id = p_batch_id and c.user_id is not null
  on conflict do nothing;

  insert into public.thread_participants (thread_id, user_id, academy_id)
  select v_thread_id, pl.parent_user_id, v_academy_id
    from public.batch_enrollments be
    join public.parent_links pl on pl.student_id = be.student_id
   where be.batch_id = p_batch_id and be.enrollment_status = 'active'
  on conflict do nothing;

  insert into public.thread_participants (thread_id, user_id, academy_id)
  select v_thread_id, s.user_id, v_academy_id
    from public.batch_enrollments be
    join public.students s on s.id = be.student_id
   where be.batch_id = p_batch_id and be.enrollment_status = 'active'
     and s.user_id is not null
  on conflict do nothing;

  if public.can_manage_enrollment(p_batch_id) then
    insert into public.thread_participants (thread_id, user_id, academy_id)
    values (v_thread_id, auth.uid(), v_academy_id)
    on conflict do nothing;
  end if;

  return v_thread_id;
end;
$$;

grant execute on function public.ensure_batch_thread(uuid) to authenticated;

-- 4) center_admin_vendors_items
--    inventory_items is center-scoped (has center_id). vendors are
--    ACADEMY-level (no center_id), so they're gated on
--    can_admin_center_scope(null) → owner/admin + center_admin (academy-wide).
drop policy if exists vendors_admin_insert  on public.vendors;
drop policy if exists vendors_admin_update  on public.vendors;
drop policy if exists vendors_admin_delete  on public.vendors;
drop policy if exists vendors_write_insert  on public.vendors;
drop policy if exists vendors_write_update  on public.vendors;
drop policy if exists vendors_write_delete  on public.vendors;

create policy vendors_write_insert on public.vendors
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_admin_center_scope(null::uuid))
  );

create policy vendors_write_update on public.vendors
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_admin_center_scope(null::uuid))
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_admin_center_scope(null::uuid))
  );

create policy vendors_write_delete on public.vendors
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_admin_center_scope(null::uuid))
  );

drop policy if exists inv_items_admin_insert  on public.inventory_items;
drop policy if exists inv_items_admin_update  on public.inventory_items;
drop policy if exists inv_items_admin_delete  on public.inventory_items;
drop policy if exists inv_items_write_insert  on public.inventory_items;
drop policy if exists inv_items_write_update  on public.inventory_items;
drop policy if exists inv_items_write_delete  on public.inventory_items;

create policy inv_items_write_insert on public.inventory_items
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_admin_center_scope(center_id))
  );

create policy inv_items_write_update on public.inventory_items
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_admin_center_scope(center_id))
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_admin_center_scope(center_id))
  );

create policy inv_items_write_delete on public.inventory_items
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_admin_center_scope(center_id))
  );

-- 5) center_admin_coach_sports
--    coach_sports write scoped to the coach's center (matches coaches).
create or replace function public.can_manage_coach(p_coach_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.can_admin_center_scope(
    (select center_id from public.coaches where id = p_coach_id)
  );
$$;

grant execute on function public.can_manage_coach(uuid) to authenticated;

drop policy if exists coach_sports_admin_insert  on public.coach_sports;
drop policy if exists coach_sports_admin_update  on public.coach_sports;
drop policy if exists coach_sports_admin_delete  on public.coach_sports;
drop policy if exists coach_sports_write_insert  on public.coach_sports;
drop policy if exists coach_sports_write_update  on public.coach_sports;
drop policy if exists coach_sports_write_delete  on public.coach_sports;

create policy coach_sports_write_insert on public.coach_sports
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_coach(coach_id))
  );

create policy coach_sports_write_update on public.coach_sports
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_coach(coach_id))
  ) with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_coach(coach_id))
  );

create policy coach_sports_write_delete on public.coach_sports
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id()
        and public.can_manage_coach(coach_id))
  );

commit;
