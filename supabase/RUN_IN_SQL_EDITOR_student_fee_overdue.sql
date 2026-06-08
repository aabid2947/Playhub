-- ============================================================================
-- PlayHub — "Unpaid (overdue fees)" indicator for the coaching roles.
-- Paste-and-run in the Supabase SQL editor. Idempotent (safe to re-run).
-- Mirrors migration 20260608000300_student_fee_overdue_flag.sql.
--
-- Adds students.fee_overdue (true when the student has >=1 OVERDUE invoice),
-- kept in sync by a trigger on invoices, plus a one-time backfill. Coaches /
-- head_coaches / trainers (who can't read finance) read this boolean off the
-- students table to show an "Unpaid" badge. Lifecycle status is untouched.
-- ============================================================================

alter table public.students
  add column if not exists fee_overdue boolean not null default false;

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

update public.students s
   set fee_overdue = exists (
     select 1 from public.invoices i
     where i.student_id = s.id and i.status = 'overdue'
   )
 where s.fee_overdue is distinct from exists (
     select 1 from public.invoices i
     where i.student_id = s.id and i.status = 'overdue'
   );
