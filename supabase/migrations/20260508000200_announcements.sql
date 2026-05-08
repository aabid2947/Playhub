-- ============================================================================
-- Announcements — admin/owner composes; targeted at any combination of:
--   - role list (e.g. all parents)
--   - batch list (e.g. parents+students of these batches)
--   - center list
--
-- The `send-announcement` Edge Function fans out to FCM + email + in-app
-- notifications and inserts one announcement_recipients row per delivered
-- target user (used for read receipts).
--
-- The recipients table is the source of truth for "did this user see it?";
-- the announcements table is the source of truth for "what was sent."
-- ============================================================================

create table public.announcements (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies(id) on delete cascade,

  subject text not null,
  body text not null,
  -- Optional rich body for in-app rendering (markdown / html).
  body_html text,

  -- Targeting (any combination; an empty target_roles + target_batches +
  -- target_centers means "everyone in the academy").
  target_roles public.user_role[] not null default array[]::public.user_role[],
  target_batches uuid[] not null default array[]::uuid[],
  target_centers uuid[] not null default array[]::uuid[],

  -- Delivery channels (push/email/in_app are independent on/off flags).
  via_push boolean not null default true,
  via_email boolean not null default false,
  via_in_app boolean not null default true,

  scheduled_for timestamptz,                          -- null = send now
  sent_at timestamptz,                                -- set by send-announcement
  sent_count int,                                     -- recipients delivered
  failed_count int,                                   -- recipients failed

  created_by uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index idx_announcements_academy_created
  on public.announcements(academy_id, created_at desc);
create index idx_announcements_scheduled
  on public.announcements(scheduled_for)
  where scheduled_for is not null and sent_at is null;

create trigger trg_announcements_updated before update on public.announcements
  for each row execute function public.set_updated_at();

-- ============================================================================
-- announcement_recipients — one row per (announcement, user) actually
-- delivered. read_at is a per-user read receipt.
-- ============================================================================
create table public.announcement_recipients (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies(id) on delete cascade,
  announcement_id uuid not null references public.announcements(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  delivered_at timestamptz not null default now(),
  read_at timestamptz,
  unique (announcement_id, user_id)
);

create index idx_announcement_recipients_user
  on public.announcement_recipients(user_id, read_at);
create index idx_announcement_recipients_academy
  on public.announcement_recipients(academy_id);

-- ============================================================================
-- RLS
--   Announcements:
--     - Read: any same-academy user (the feed shows your own audience).
--             Per-user filtering happens via announcement_recipients.
--     - Write: admin-or-higher.
--   Recipients:
--     - Read: the recipient themselves (and same-academy admins).
--     - Update: only the recipient, only the read_at column-via-policy.
--     - Insert/Delete: service-role only (no policies = blocked).
-- ============================================================================

alter table public.announcements           enable row level security;
alter table public.announcement_recipients enable row level security;

create policy announcements_academy_read on public.announcements
  for select using (
    public.is_super_admin()
    or academy_id = public.current_user_academy_id()
  );

create policy announcements_admin_insert on public.announcements
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create policy announcements_admin_update on public.announcements
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  )
  with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create policy announcements_admin_delete on public.announcements
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create policy announcement_recipients_self_read on public.announcement_recipients
  for select using (
    public.is_super_admin()
    or user_id = auth.uid()
    or (
      academy_id = public.current_user_academy_id()
      and public.has_admin_or_higher()
    )
  );

-- Self-update: recipient can mark their own row read (sets read_at).
create policy announcement_recipients_self_update on public.announcement_recipients
  for update using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- No insert / delete policies — only the SECURITY DEFINER fan-out path
-- (send-announcement Edge Function via service role) creates rows.

-- Audit hooks
create trigger trg_audit_announcements
  after insert or update or delete on public.announcements
  for each row execute function public.write_audit_log();

-- recipients table doesn't need an audit log — too noisy (one row per
-- delivered user per announcement). The parent announcements table is
-- already audited.

-- ============================================================================
-- Helper: mark an announcement read for the current user. Single round-trip
-- replacing a manual upsert.
-- ============================================================================
create or replace function public.mark_announcement_read(p_announcement_id uuid)
returns void
language sql
volatile
security definer
set search_path = public
as $$
  update public.announcement_recipients
     set read_at = now()
   where announcement_id = p_announcement_id
     and user_id = auth.uid()
     and read_at is null
$$;

grant execute on function public.mark_announcement_read(uuid) to authenticated;
