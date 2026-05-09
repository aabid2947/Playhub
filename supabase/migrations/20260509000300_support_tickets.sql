-- ============================================================================
-- Sprint 5 — Support tickets: academy owners file, super_admin replies.
--
-- Two tables:
--   support_tickets         — one row per ticket
--   support_ticket_messages — append-only thread of replies
--
-- Visibility:
--   - The owner / admin who filed it (or anyone in their academy) can read
--     and post replies.
--   - super_admin can read + reply on any ticket.
-- ============================================================================

create type public.support_ticket_status as enum (
  'open',
  'in_progress',
  'waiting_on_user',
  'resolved',
  'closed'
);

create table public.support_tickets (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies(id) on delete cascade,
  opened_by uuid references public.users(id) on delete set null,

  subject text not null,
  body text not null,
  category text,                          -- 'billing', 'bug', 'feature', 'other'
  priority text not null default 'normal'
    check (priority in ('low', 'normal', 'high', 'urgent')),
  status public.support_ticket_status not null default 'open',

  assigned_to uuid references public.users(id) on delete set null,
  resolved_at timestamptz,
  closed_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index idx_support_tickets_academy on public.support_tickets(academy_id, status);
create index idx_support_tickets_status on public.support_tickets(status, created_at desc);

create trigger trg_support_tickets_updated before update on public.support_tickets
  for each row execute function public.set_updated_at();

create table public.support_ticket_messages (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null references public.support_tickets(id) on delete cascade,
  academy_id uuid not null references public.academies(id) on delete cascade,
  author_id uuid references public.users(id) on delete set null,
  is_staff boolean not null default false,    -- true when sent by super_admin
  body text not null,
  created_at timestamptz not null default now()
);

create index idx_support_msgs_ticket
  on public.support_ticket_messages(ticket_id, created_at);

-- ============================================================================
-- RLS
-- ============================================================================

alter table public.support_tickets         enable row level security;
alter table public.support_ticket_messages enable row level security;

-- Reads: super_admin sees all; same-academy owner/admin/center_admin see all
-- their academy's tickets.
create policy support_tickets_read on public.support_tickets
  for select using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.current_user_role() in (
        'academy_owner', 'academy_admin', 'center_admin'
      )
    )
  );

create policy support_tickets_owner_insert on public.support_tickets
  for insert with check (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.current_user_role() in ('academy_owner', 'academy_admin')
    )
  );

-- Owners can update *their own* ticket (close it, change priority).
-- super_admin can update anything (assign, change status).
create policy support_tickets_update on public.support_tickets
  for update using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.current_user_role() in ('academy_owner', 'academy_admin')
    )
  )
  with check (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.current_user_role() in ('academy_owner', 'academy_admin')
    )
  );

create policy support_tickets_super_admin_delete on public.support_tickets
  for delete using (public.is_super_admin());

-- Messages: anyone who can read the ticket can read the messages.
create policy support_msgs_read on public.support_ticket_messages
  for select using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.current_user_role() in (
        'academy_owner', 'academy_admin', 'center_admin'
      )
    )
  );

create policy support_msgs_insert on public.support_ticket_messages
  for insert with check (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.current_user_role() in ('academy_owner', 'academy_admin')
      and is_staff = false
    )
  );

-- Audit hooks
create trigger trg_audit_support_tickets
  after insert or update or delete on public.support_tickets
  for each row execute function public.write_audit_log();

create trigger trg_audit_support_ticket_messages
  after insert or update or delete on public.support_ticket_messages
  for each row execute function public.write_audit_log();
