-- ============================================================================
-- Sprint 1 — coaches table per SRD §7.1
-- ============================================================================

create table public.coaches (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies(id) on delete cascade,
  -- Optional link to a public.users row when this coach has app login.
  -- Created lazily by an admin via the "invite to app" flow (later sprint).
  user_id uuid references public.users(id) on delete set null,
  center_id uuid references public.centers(id) on delete set null,

  first_name text not null,
  last_name text not null,
  email text,
  phone text,
  photo text,

  specialization text[] not null default '{}',
  experience_years int,
  qualifications text[] not null default '{}',
  certifications text[] not null default '{}',

  salary numeric(10, 2),
  payment_type text check (payment_type in ('monthly', 'hourly', 'session')),

  join_date date not null default current_date,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index idx_coaches_academy on public.coaches(academy_id);
create index idx_coaches_center on public.coaches(center_id);
create index idx_coaches_user on public.coaches(user_id);

create trigger trg_coaches_updated before update on public.coaches
  for each row execute function public.set_updated_at();

alter table public.coaches enable row level security;

create policy coaches_academy_read on public.coaches
  for select using (
    public.is_super_admin()
    or academy_id = public.current_user_academy_id()
  );

create policy coaches_admin_write on public.coaches
  for all using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  )
  with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );
