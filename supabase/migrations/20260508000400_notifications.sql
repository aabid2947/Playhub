-- ============================================================================
-- Notifications — in-app feed + per-channel preferences.
--
-- Two tables:
--   notification_preferences — one row per user, per category.
--   notifications            — append-only feed; clients mark read_at.
--
-- The send-announcement / lead-followup-reminder / payment-related Edge
-- Functions write to this table directly (service role) when fanning out;
-- they also push FCM and email per the user's preferences.
-- ============================================================================

create type public.notification_category as enum (
  'announcement',
  'message',
  'attendance',
  'performance',
  'invoice',
  'payment',
  'lead',
  'system'
);

create type public.notification_channel as enum (
  'push',
  'email',
  'in_app'
);

create table public.notification_preferences (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  academy_id uuid references public.academies(id) on delete cascade,
  category public.notification_category not null,
  channel public.notification_channel not null,
  enabled boolean not null default true,
  updated_at timestamptz not null default now(),
  unique (user_id, category, channel)
);

create index idx_notif_prefs_user on public.notification_preferences(user_id);

create trigger trg_notif_prefs_updated before update on public.notification_preferences
  for each row execute function public.set_updated_at();

-- ============================================================================
-- notifications — in-app feed entries. One per delivered in-app target.
-- ============================================================================
create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  academy_id uuid not null references public.academies(id) on delete cascade,

  category public.notification_category not null,
  title text not null,
  body text,
  -- A go_router-style deep link, e.g.  "/announcements/<id>"
  -- or "/threads/<id>" / "/invoices/<id>".
  deep_link text,

  -- Optional FK back to the originating record. Polymorphic: keep both
  -- entity_type + entity_id for client-side routing fallbacks.
  entity_type text,
  entity_id uuid,

  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index idx_notifications_user_unread
  on public.notifications(user_id, created_at desc)
  where read_at is null;
create index idx_notifications_user_all
  on public.notifications(user_id, created_at desc);

-- ============================================================================
-- device_tokens — FCM registration tokens, one row per (user, device).
-- The Flutter app upserts these on first launch + every refresh. The
-- send-announcement function reads this table to fan out push.
-- ============================================================================
create table public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  academy_id uuid references public.academies(id) on delete cascade,
  fcm_token text not null,
  platform text not null check (platform in ('android', 'ios', 'web')),
  device_id text,                      -- stable id per device
  app_version text,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  -- Same token never duplicated; if a token rotates between users we keep
  -- only the latest claim.
  unique (fcm_token)
);

create index idx_device_tokens_user on public.device_tokens(user_id);

-- ============================================================================
-- Helpers
-- ============================================================================

-- mark_notification_read(p_id) — caller must own the row.
create or replace function public.mark_notification_read(p_id uuid)
returns void
language sql
volatile
security definer
set search_path = public
as $$
  update public.notifications
     set read_at = now()
   where id = p_id and user_id = auth.uid() and read_at is null
$$;

grant execute on function public.mark_notification_read(uuid) to authenticated;

-- mark_all_notifications_read() — bulk for the bell-icon UX.
create or replace function public.mark_all_notifications_read()
returns int
language plpgsql
volatile
security definer
set search_path = public
as $$
declare v_count int;
begin
  with upd as (
    update public.notifications
       set read_at = now()
     where user_id = auth.uid() and read_at is null
     returning 1
  )
  select count(*) into v_count from upd;
  return v_count;
end;
$$;

grant execute on function public.mark_all_notifications_read() to authenticated;

-- unread_notification_count() — drives the bell badge.
create or replace function public.unread_notification_count()
returns int
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::int from public.notifications
   where user_id = auth.uid() and read_at is null
$$;

grant execute on function public.unread_notification_count() to authenticated;

-- register_device_token(token, platform, device_id, app_version) — upsert.
create or replace function public.register_device_token(
  p_token text,
  p_platform text,
  p_device_id text default null,
  p_app_version text default null
)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare v_academy uuid;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if p_token is null or length(trim(p_token)) = 0 then
    raise exception 'token required';
  end if;

  select academy_id into v_academy from public.users where id = auth.uid();

  insert into public.device_tokens (
    user_id, academy_id, fcm_token, platform, device_id, app_version
  ) values (
    auth.uid(), v_academy, p_token, p_platform, p_device_id, p_app_version
  )
  on conflict (fcm_token) do update
    set user_id = excluded.user_id,
        academy_id = excluded.academy_id,
        platform = excluded.platform,
        device_id = excluded.device_id,
        app_version = excluded.app_version,
        last_seen_at = now();
end;
$$;

grant execute on function public.register_device_token(text, text, text, text)
  to authenticated;

-- ============================================================================
-- RLS
--   prefs:          self-only read + upsert.
--   notifications:  self-only read + update read_at.
--   device_tokens:  self-only read + upsert via register_device_token.
--
-- Inserts to notifications happen via service role from Edge Functions —
-- no INSERT policy exposed to app callers.
-- ============================================================================

alter table public.notification_preferences enable row level security;
alter table public.notifications            enable row level security;
alter table public.device_tokens            enable row level security;

create policy notif_prefs_self_read on public.notification_preferences
  for select using (user_id = auth.uid() or public.is_super_admin());

create policy notif_prefs_self_insert on public.notification_preferences
  for insert with check (user_id = auth.uid());

create policy notif_prefs_self_update on public.notification_preferences
  for update using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy notif_prefs_self_delete on public.notification_preferences
  for delete using (user_id = auth.uid());

create policy notifications_self_read on public.notifications
  for select using (user_id = auth.uid() or public.is_super_admin());

-- Self-update: only setting read_at. (We don't enforce column-level RLS in
-- v0.x — relying on UI + helper RPCs.)
create policy notifications_self_update on public.notifications
  for update using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy notifications_self_delete on public.notifications
  for delete using (user_id = auth.uid());

-- device_tokens — self-only.
create policy device_tokens_self_read on public.device_tokens
  for select using (user_id = auth.uid() or public.is_super_admin());

create policy device_tokens_self_write on public.device_tokens
  for all using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Realtime for notifications so the bell badge updates live.
alter publication supabase_realtime add table public.notifications;
