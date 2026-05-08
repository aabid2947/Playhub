-- ============================================================================
-- convert_lead — atomic transaction used by the convert-lead-to-student
-- Edge Function. Returns the new student id.
--
-- Steps inside the function:
--   1. Lock the lead row, verify it's not already converted.
--   2. Insert into students (first/last/parent_name/email/phone/sport).
--   3. If p_batch_id is non-null, insert a batch_enrollments row.
--   4. If p_parent_user_id is non-null, insert a parent_links row.
--   5. Update leads.status='converted', set converted_student_id +
--      converted_at.
--   6. Append a 'note' lead_activity describing the conversion.
-- ============================================================================

create or replace function public.convert_lead(
  p_lead_id uuid,
  p_batch_id uuid default null,
  p_parent_user_id uuid default null,
  p_start_date date default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_lead public.leads%rowtype;
  v_student_id uuid;
  v_start date := coalesce(p_start_date, current_date);
begin
  -- Lock the row to keep the conversion racy-free.
  select * into v_lead from public.leads
   where id = p_lead_id for update;
  if not found then raise exception 'lead not found'; end if;
  if v_lead.status = 'converted' then
    raise exception 'lead already converted';
  end if;

  insert into public.students (
    academy_id, first_name, last_name, parent_name, email, phone
  ) values (
    v_lead.academy_id,
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

grant execute on function public.convert_lead(uuid, uuid, uuid, date)
  to authenticated;
