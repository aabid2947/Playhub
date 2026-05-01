-- ============================================================================
-- PlayHub — Sprint 0 foundation: enums, tenancy, users, RLS helpers
-- ============================================================================

-- Extensions ------------------------------------------------------------------
-- Supabase already provisions pgcrypto + uuid-ossp in the `extensions` schema.
-- We use Postgres's built-in gen_random_uuid() (Postgres 13+) so we don't
-- depend on either extension being on the search path.

-- Role enum (9 roles per SRD §2.3) -------------------------------------------
create type public.user_role as enum (
  'super_admin',
  'academy_owner',
  'academy_admin',
  'center_admin',
  'head_coach',
  'coach',
  'trainer',
  'parent',
  'student'
);

create type public.subscription_status as enum (
  'trial',
  'active',
  'past_due',
  'suspended',
  'cancelled'
);

-- Academies -------------------------------------------------------------------
create table public.academies (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  owner_id uuid,                       -- FK added after users table exists
  subscription_status public.subscription_status not null default 'trial',
  trial_ends_at timestamptz default (now() + interval '14 days'),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Centers ---------------------------------------------------------------------
create table public.centers (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies(id) on delete cascade,
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index idx_centers_academy on public.centers(academy_id);

-- Users -----------------------------------------------------------------------
-- Mirrors auth.users; linked 1:1 by id.
create table public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  phone text,
  first_name text,
  last_name text,
  role public.user_role not null,
  academy_id uuid references public.academies(id) on delete cascade,
  center_id uuid references public.centers(id) on delete set null,
  profile_photo text,
  is_active boolean not null default true,
  must_change_password boolean not null default false,
  preferences jsonb not null default '{}'::jsonb,
  last_login timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- super_admin has no academy; everyone else must
  constraint users_academy_required
    check (role = 'super_admin' or academy_id is not null)
);
create index idx_users_academy on public.users(academy_id);
create index idx_users_role on public.users(role);

-- Now add the FK from academies.owner_id back to users
alter table public.academies
  add constraint academies_owner_fk foreign key (owner_id) references public.users(id) on delete set null;

-- updated_at trigger function -------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger trg_users_updated before update on public.users
  for each row execute function public.set_updated_at();
create trigger trg_academies_updated before update on public.academies
  for each row execute function public.set_updated_at();
create trigger trg_centers_updated before update on public.centers
  for each row execute function public.set_updated_at();

-- ============================================================================
-- RLS helper functions
--   These read auth.uid() and the requesting user's row; SECURITY DEFINER lets
--   them bypass RLS to inspect the users table itself.
-- ============================================================================

create or replace function public.current_user_role()
returns public.user_role
language sql
stable
security definer
set search_path = public
as $$
  select role from public.users where id = auth.uid()
$$;

create or replace function public.current_user_academy_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select academy_id from public.users where id = auth.uid()
$$;

create or replace function public.current_user_center_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select center_id from public.users where id = auth.uid()
$$;

create or replace function public.is_super_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select role from public.users where id = auth.uid()) = 'super_admin', false)
$$;

create or replace function public.has_role(check_role public.user_role)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select role from public.users where id = auth.uid()) = check_role, false)
$$;

create or replace function public.has_admin_or_higher()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select role from public.users where id = auth.uid())
      in ('super_admin','academy_owner','academy_admin'),
    false
  )
$$;

-- ============================================================================
-- RLS policies
-- ============================================================================

alter table public.users     enable row level security;
alter table public.academies enable row level security;
alter table public.centers   enable row level security;

-- users: read own row + same-academy reads for admins; super_admin sees all
create policy users_self_read on public.users
  for select using (id = auth.uid());

create policy users_same_academy_read on public.users
  for select using (
    public.is_super_admin()
    or (academy_id is not null and academy_id = public.current_user_academy_id())
  );

create policy users_self_update on public.users
  for update using (id = auth.uid())
  with check (id = auth.uid() and role = (select role from public.users where id = auth.uid()));

create policy users_admin_write on public.users
  for all using (public.has_admin_or_higher())
  with check (public.has_admin_or_higher());

-- academies: visible to its members; writeable by super_admin or owner
create policy academies_member_read on public.academies
  for select using (
    public.is_super_admin()
    or id = public.current_user_academy_id()
  );

create policy academies_owner_write on public.academies
  for all using (
    public.is_super_admin()
    or (id = public.current_user_academy_id() and public.has_role('academy_owner'))
  )
  with check (
    public.is_super_admin()
    or (id = public.current_user_academy_id() and public.has_role('academy_owner'))
  );

-- centers: visible to its academy; writeable by admin-or-higher in same academy
create policy centers_academy_read on public.centers
  for select using (
    public.is_super_admin()
    or academy_id = public.current_user_academy_id()
  );

create policy centers_admin_write on public.centers
  for all using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  )
  with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

-- ============================================================================
-- Auth → public.users sync
--   When a new auth.users row is created, this trigger creates a stub
--   public.users row. The actual role + academy is set by the
--   `signup-bootstrap` Edge Function which runs after.
-- ============================================================================

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Default role 'student'; signup-bootstrap will overwrite as needed.
  insert into public.users (id, email, phone, role)
  values (
    new.id,
    new.email,
    new.phone,
    coalesce((new.raw_user_meta_data->>'role')::public.user_role, 'student')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger trg_on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();
