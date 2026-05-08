-- ============================================================================
-- Messaging — direct (1:1) and batch (group) threads.
--
-- Two thread kinds:
--   direct  — exactly two users: parent ↔ coach (or admin ↔ anyone).
--             user_a < user_b (sorted) so a unique constraint dedupes the pair.
--   batch   — one thread per batch; participants are the batch coach + parents
--             of currently-enrolled students. Materialised in
--             thread_participants so RLS doesn't have to re-derive the set.
--
-- thread_participants is the source of truth for "who can read this thread."
-- It is maintained:
--   - on direct thread creation (RPC ensure_direct_thread)
--   - on batch enrollment changes (trigger, future-proof)
--   - on coach reassignment of a batch (trigger, future-proof)
--
-- For Sprint 4 we ship: direct threads (lazy), batch threads (RPC creates +
-- syncs participants), realtime subscription via the messages table.
-- ============================================================================

create type public.thread_kind as enum ('direct', 'batch');

create table public.message_threads (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies(id) on delete cascade,
  kind public.thread_kind not null,

  -- For direct threads: the canonical sorted user pair (a < b).
  direct_user_a uuid references public.users(id) on delete cascade,
  direct_user_b uuid references public.users(id) on delete cascade,

  -- For batch threads: the batch this thread belongs to.
  batch_id uuid references public.batches(id) on delete cascade,

  title text,                         -- optional — UI renders auto for direct
  last_message_at timestamptz,
  last_message_preview text,
  created_by uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint thread_kind_consistent check (
    (kind = 'direct'
      and direct_user_a is not null and direct_user_b is not null
      and direct_user_a < direct_user_b
      and batch_id is null)
    or (kind = 'batch'
      and batch_id is not null
      and direct_user_a is null and direct_user_b is null)
  )
);

-- One direct thread per (academy, sorted-user-pair).
create unique index uq_threads_direct
  on public.message_threads(academy_id, direct_user_a, direct_user_b)
  where kind = 'direct';

-- One batch thread per batch.
create unique index uq_threads_batch
  on public.message_threads(batch_id)
  where kind = 'batch';

create index idx_threads_academy_last
  on public.message_threads(academy_id, last_message_at desc);

create trigger trg_threads_updated before update on public.message_threads
  for each row execute function public.set_updated_at();

-- ============================================================================
-- thread_participants — denormalised membership.
-- ============================================================================
create table public.thread_participants (
  thread_id uuid not null references public.message_threads(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  academy_id uuid not null references public.academies(id) on delete cascade,
  joined_at timestamptz not null default now(),
  last_read_at timestamptz,
  is_muted boolean not null default false,
  primary key (thread_id, user_id)
);

create index idx_thread_participants_user
  on public.thread_participants(user_id, last_read_at);

-- ============================================================================
-- messages — append-mostly. edited_at + deleted_at are soft.
-- ============================================================================
create table public.messages (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references public.message_threads(id) on delete cascade,
  academy_id uuid not null references public.academies(id) on delete cascade,
  sender_id uuid not null references public.users(id) on delete set null,

  content text not null,
  -- attachments stored in a private storage bucket; this column carries the
  -- list of object paths the client should resolve.
  attachments jsonb not null default '[]'::jsonb,

  edited_at timestamptz,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),

  constraint messages_content_or_attachments check (
    length(trim(content)) > 0 or jsonb_array_length(attachments) > 0
  )
);

create index idx_messages_thread_created
  on public.messages(thread_id, created_at desc);

-- Bumps thread.last_message_at on every insert so the inbox can be sorted
-- by recency without a join.
create or replace function public.bump_thread_last_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.message_threads
     set last_message_at = new.created_at,
         last_message_preview = left(new.content, 200),
         updated_at = now()
   where id = new.thread_id;
  return new;
end;
$$;

create trigger trg_messages_bump_thread
  after insert on public.messages
  for each row execute function public.bump_thread_last_message();

-- ============================================================================
-- Helper: is the calling user a participant in this thread?
-- SECURITY DEFINER + stable so it's cacheable per-row.
-- ============================================================================
create or replace function public.is_thread_participant(p_thread_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    exists (
      select 1 from public.thread_participants
      where thread_id = p_thread_id and user_id = auth.uid()
    ),
    false
  );
$$;

grant execute on function public.is_thread_participant(uuid) to authenticated;

-- ============================================================================
-- RPC: ensure_direct_thread(other_user_id) → uuid
--   Creates (or returns existing) the 1:1 thread between caller and
--   other_user_id. Adds both as participants. Rejects cross-academy.
-- ============================================================================
create or replace function public.ensure_direct_thread(p_other_user_id uuid)
returns uuid
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_caller uuid := auth.uid();
  v_my_academy uuid;
  v_other_academy uuid;
  v_a uuid;
  v_b uuid;
  v_thread_id uuid;
begin
  if v_caller is null then
    raise exception 'not authenticated';
  end if;
  if v_caller = p_other_user_id then
    raise exception 'cannot start a thread with yourself';
  end if;

  select academy_id into v_my_academy from public.users where id = v_caller;
  select academy_id into v_other_academy from public.users where id = p_other_user_id;

  if v_my_academy is null or v_my_academy is distinct from v_other_academy then
    raise exception 'cross-academy threads are not allowed';
  end if;

  if v_caller < p_other_user_id then
    v_a := v_caller; v_b := p_other_user_id;
  else
    v_a := p_other_user_id; v_b := v_caller;
  end if;

  insert into public.message_threads
    (academy_id, kind, direct_user_a, direct_user_b, created_by)
  values
    (v_my_academy, 'direct', v_a, v_b, v_caller)
  on conflict do nothing
  returning id into v_thread_id;

  if v_thread_id is null then
    select id into v_thread_id from public.message_threads
     where academy_id = v_my_academy and kind = 'direct'
       and direct_user_a = v_a and direct_user_b = v_b;
  end if;

  insert into public.thread_participants (thread_id, user_id, academy_id)
  values
    (v_thread_id, v_a, v_my_academy),
    (v_thread_id, v_b, v_my_academy)
  on conflict do nothing;

  return v_thread_id;
end;
$$;

grant execute on function public.ensure_direct_thread(uuid) to authenticated;

-- ============================================================================
-- RPC: ensure_batch_thread(batch_id) → uuid
--   Creates the batch group chat (if needed) and syncs participants from
--   the current coach + parents of currently-enrolled students. Idempotent.
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

  return v_thread_id;
end;
$$;

grant execute on function public.ensure_batch_thread(uuid) to authenticated;

-- ============================================================================
-- mark_thread_read — bump last_read_at for the calling participant.
-- ============================================================================
create or replace function public.mark_thread_read(p_thread_id uuid)
returns void
language sql
volatile
security definer
set search_path = public
as $$
  update public.thread_participants
     set last_read_at = now()
   where thread_id = p_thread_id and user_id = auth.uid()
$$;

grant execute on function public.mark_thread_read(uuid) to authenticated;

-- ============================================================================
-- RLS
--   threads:           participants + same-academy admins read; admins manage.
--   thread_participants: members see their thread's roster; self can update
--                        (mute / mark read); inserts via the RPCs.
--   messages:          participants read + post; sender can edit own message.
-- ============================================================================

alter table public.message_threads      enable row level security;
alter table public.thread_participants  enable row level security;
alter table public.messages             enable row level security;

create policy threads_participant_read on public.message_threads
  for select using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and (
        public.has_admin_or_higher()
        or public.is_thread_participant(id)
      )
    )
  );

-- Threads are mostly created via the two ensure_* RPCs (security definer).
-- Admins may also create / archive threads directly.
create policy threads_admin_write on public.message_threads
  for all using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  )
  with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create policy thread_participants_read on public.thread_participants
  for select using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and (
        public.has_admin_or_higher()
        or user_id = auth.uid()
        or public.is_thread_participant(thread_id)
      )
    )
  );

-- Self-update: mute / mark-read on own row.
create policy thread_participants_self_update on public.thread_participants
  for update using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Admins can add/remove participants (e.g. force-add a parent to a batch
-- chat). Direct/batch RPCs use SECURITY DEFINER; ordinary users cannot.
create policy thread_participants_admin_write on public.thread_participants
  for all using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  )
  with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create policy messages_participant_read on public.messages
  for select using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and (
        public.has_admin_or_higher()
        or public.is_thread_participant(thread_id)
      )
    )
  );

-- Insert: participants only; sender_id must be the caller; academy_id must
-- match the caller's academy.
create policy messages_participant_insert on public.messages
  for insert with check (
    sender_id = auth.uid()
    and academy_id = public.current_user_academy_id()
    and public.is_thread_participant(thread_id)
  );

-- Update: only the sender, only their own row (for edits / soft-delete).
create policy messages_self_update on public.messages
  for update using (sender_id = auth.uid())
  with check (sender_id = auth.uid());

-- No DELETE policy — soft-delete via deleted_at. Admins can hard-delete via
-- service-role if a moderation action is needed.

-- Realtime: enable replication for messages so Supabase Realtime can stream
-- new rows to subscribed clients. (Threads / participants are queried on
-- demand; no realtime needed.)
alter publication supabase_realtime add table public.messages;

-- Audit hooks (lightweight — only message-thread lifecycle, not every msg)
create trigger trg_audit_message_threads
  after insert or update or delete on public.message_threads
  for each row execute function public.write_audit_log();
