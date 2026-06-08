-- ============================================================================
-- Surface "student has unpaid (overdue) fees" to the coaching roles.
--
-- Coaches / head_coaches / trainers see NO finance (Phase 4), so they can't
-- read invoices to know who hasn't paid. This adds a derived boolean on the
-- students table — which they CAN read — exposing only the standing (no
-- amounts). It flips true when the student has ≥1 OVERDUE invoice (past due,
-- set by the mark-overdue cron) and false again when none remain (e.g. paid).
--
-- Maintained by a trigger on invoices so it stays correct in real time (the
-- razorpay webhook / record-payment flip status → paid outside the cron). It
-- does NOT touch students.status — lifecycle (paused/graduated) is separate.
-- ============================================================================

alter table public.students
  add column if not exists fee_overdue boolean not null default false;

-- Recompute one student's flag from their invoices. SECURITY DEFINER so it can
-- write students regardless of who changed the invoice (cron/service/webhook/
-- center_admin); owner bypasses RLS. Cheap: one indexed EXISTS per fired row.
create or replace function public.refresh_student_fee_overdue()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student uuid := coalesce(NEW.student_id, OLD.student_id);
  v_overdue boolean;
begin
  if v_student is null then
    return coalesce(NEW, OLD);
  end if;
  select exists (
    select 1 from public.invoices i
    where i.student_id = v_student and i.status = 'overdue'
  ) into v_overdue;
  update public.students
     set fee_overdue = v_overdue
   where id = v_student
     and fee_overdue is distinct from v_overdue;
  return coalesce(NEW, OLD);
end;
$$;

drop trigger if exists trg_invoices_fee_overdue on public.invoices;
create trigger trg_invoices_fee_overdue
  after insert or update or delete on public.invoices
  for each row execute function public.refresh_student_fee_overdue();

-- Backfill existing students from current invoice state.
update public.students s
   set fee_overdue = exists (
     select 1 from public.invoices i
     where i.student_id = s.id and i.status = 'overdue'
   )
 where s.fee_overdue is distinct from exists (
     select 1 from public.invoices i
     where i.student_id = s.id and i.status = 'overdue'
   );
