-- ============================================================================
-- Fix: convert_lead() must resolve a NON-NULL center now that students.center_id
-- is NOT NULL (20260710000000). It previously inserted the student with
-- v_lead.preferred_center_id, which the in-app lead form never captures → EVERY
-- lead→student conversion failed with an opaque NOT NULL violation, with no way
-- to recover (the RPC has no center arg).
--
-- Now the center resolves from the lead's preferred center, falling back to the
-- chosen initial batch's center (batches.center_id is NOT NULL as of
-- 20260710000100); if neither yields one it raises a CLEAR error instead of a
-- constraint failure. Signature is UNCHANGED, so no edge-function redeploy is
-- needed — and the mobile convert flow now also stamps the picked center onto
-- the lead's preferred_center_id before calling, so the common path always
-- resolves. `create or replace` (same signature) preserves existing grants.
-- ============================================================================

create or replace function public.convert_lead(
  p_lead_id uuid,
  p_batch_id uuid default null,
  p_parent_user_id uuid default null,
  p_start_date date default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lead public.leads%rowtype;
  v_student_id uuid;
  v_start date := coalesce(p_start_date, current_date);
  v_center_id uuid;
begin
  -- Lock the row to keep the conversion race-free.
  select * into v_lead from public.leads
   where id = p_lead_id for update;
  if not found then raise exception 'lead not found'; end if;
  if v_lead.status = 'converted' then
    raise exception 'lead already converted';
  end if;

  -- students.center_id is NOT NULL. Resolve the student's center: the lead's
  -- preferred center, else the chosen initial batch's center. Fail clearly if
  -- neither is available.
  v_center_id := coalesce(
    v_lead.preferred_center_id,
    (select center_id from public.batches
      where id = p_batch_id and academy_id = v_lead.academy_id)
  );
  if v_center_id is null then
    raise exception
      'a center is required to convert this lead — pick a center or an initial batch';
  end if;

  insert into public.students (
    academy_id, center_id, first_name, last_name, parent_name, email, phone
  ) values (
    v_lead.academy_id,
    v_center_id,
    v_lead.first_name,
    coalesce(v_lead.last_name, ''),
    coalesce(v_lead.parent_name, ''),
    v_lead.email,
    v_lead.phone
  )
  returning id into v_student_id;

  if p_batch_id is not null then
    -- Validate the batch belongs to the same academy.
    if not exists (
      select 1 from public.batches
      where id = p_batch_id and academy_id = v_lead.academy_id
    ) then
      raise exception 'batch not in lead''s academy';
    end if;

    insert into public.batch_enrollments
      (academy_id, batch_id, student_id, enrollment_status, enrolled_at)
    values (v_lead.academy_id, p_batch_id, v_student_id, 'active',
            v_start::timestamptz);
  end if;

  if p_parent_user_id is not null then
    insert into public.parent_links
      (academy_id, parent_user_id, student_id, is_primary)
    values (v_lead.academy_id, p_parent_user_id, v_student_id, true)
    on conflict do nothing;
  end if;

  update public.leads
     set status = 'converted',
         converted_student_id = v_student_id,
         converted_at = now()
   where id = p_lead_id;

  insert into public.lead_activities
    (academy_id, lead_id, user_id, kind, content, metadata)
  values (
    v_lead.academy_id, p_lead_id, auth.uid(),
    'note',
    'Lead converted to student',
    jsonb_build_object('student_id', v_student_id, 'batch_id', p_batch_id)
  );

  return v_student_id;
end;
$$;
