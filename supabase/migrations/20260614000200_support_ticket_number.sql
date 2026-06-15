-- ============================================================================
-- Human-readable support ticket number. [Issue #10]
--
-- Tickets only had a UUID id — useless for a non-technical academy user to quote
-- ("show me the ticket number"). Add a friendly sequential `ticket_number`
-- (global sequence; unique, increasing) shown on the ticket + the raise
-- confirmation. No new table/RLS — it's a column on the existing
-- support_tickets (its RLS is unchanged), so no pgTAP needed here.
-- ============================================================================

create sequence if not exists public.support_ticket_number_seq;

alter table public.support_tickets
  add column ticket_number bigint;

-- Backfill existing tickets in creation order so early tickets get low numbers.
with ordered as (
  select id, row_number() over (order by created_at, id) as rn
  from public.support_tickets
)
update public.support_tickets t
  set ticket_number = o.rn
  from ordered o
  where o.id = t.id;

-- Advance the sequence past the highest assigned number.
select setval(
  'public.support_ticket_number_seq',
  coalesce((select max(ticket_number) from public.support_tickets), 0) + 1,
  false
);

alter table public.support_tickets
  alter column ticket_number set default nextval('public.support_ticket_number_seq'),
  alter column ticket_number set not null;

create unique index uq_support_tickets_number
  on public.support_tickets(ticket_number);
