-- ============================================================================
-- Sprint 1 — extend academies and centers with full SRD fields
-- ============================================================================

-- Academies: contact, address, branding, configuration -----------------------
alter table public.academies
  add column if not exists logo text,
  add column if not exists email text,
  add column if not exists phone text,
  add column if not exists address text,
  add column if not exists city text,
  add column if not exists state text,
  add column if not exists pincode text,
  add column if not exists website text,
  add column if not exists sports_offered text[] not null default '{}',
  add column if not exists settings jsonb not null default '{}'::jsonb;

-- Centers: physical-location detail + admin assignment ----------------------
alter table public.centers
  add column if not exists address text,
  add column if not exists city text,
  add column if not exists state text,
  add column if not exists pincode text,
  add column if not exists phone text,
  add column if not exists email text,
  add column if not exists facilities text[] not null default '{}',
  add column if not exists capacity int,
  add column if not exists admin_id uuid references public.users(id) on delete set null;

create index if not exists idx_centers_admin on public.centers(admin_id);
