-- ============================================================================
-- Batch chat: add the calling MANAGER as a thread participant.
--
-- ensure_batch_thread() seeded participants as coach + parents + students only,
-- so an academy_owner / academy_admin / center_admin / head_coach who opened a
-- batch group chat was never a participant. The messages_participant_insert
-- policy requires is_thread_participant() with NO admin bypass (unlike the
-- read policy, which allows has_admin_or_higher), so their send failed under
-- RLS. This restores read↔post symmetry for the full manager set, scoped for
-- center_admin/head_coach to the batch's own center via can_manage_enrollment.
--
-- Idempotent (on conflict do nothing); SECURITY DEFINER bypasses RLS for the
-- participant insert. ensureBatchThread is called on every batch-chat open, so
-- this also back-fills existing threads the next time a manager opens them.
-- ============================================================================
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
  -- Caller must belong to that academy.
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

  -- Participants = batch coach (via coaches.user_id) + parents of currently
  -- active enrollments (via parent_links) + students with their own login.
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

  -- The calling manager (admin tier + center_admin/head_coach scoped to the
  -- batch's center) joins as a participant so they can read AND post — the
  -- messages RLS is participant-gated with no admin escape hatch.
  if public.can_manage_enrollment(p_batch_id) then
    insert into public.thread_participants (thread_id, user_id, academy_id)
    values (v_thread_id, auth.uid(), v_academy_id)
    on conflict do nothing;
  end if;

  return v_thread_id;
end;
$$;

grant execute on function public.ensure_batch_thread(uuid) to authenticated;
