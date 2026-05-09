-- ============================================================================
-- Polish phase 1+2 — Sports as a first-class entity.
--
-- Until now `sport` was free text on students / batches / leads / events /
-- performance_assessments / fee_structures, plus an unconstrained
-- `academies.sports_offered text[]`. That meant 'Cricket' / 'cricket' /
-- 'Cricket (hardball)' became three distinct sports, KPI dashboards couldn't
-- slice cleanly, and skill assessments had no per-sport catalog.
--
-- This migration is purely additive:
--   * sports         — global catalog, super_admin curated, with default skills
--   * academy_sports — which sports an academy offers (per-academy enable list)
--   * sport_skills   — per-sport skill catalog (drives performance UI)
--   * coach_sports   — junction: which sports a coach is qualified to coach
--   * sport_id FK columns on the six "sport" tables (nullable, alongside the
--     existing text columns)
--
-- Backfill: best-effort case-insensitive match from each existing text column
-- to sports.code or sports.name. Anything that doesn't match cleanly stays as
-- text-only. The free-text columns are NOT dropped in this migration —
-- phase 3 (UI swap) lands first so we can verify pickers work end-to-end.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- sports — global catalog
-- ---------------------------------------------------------------------------
create table public.sports (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,            -- slug: 'cricket', 'table_tennis'
  name text not null,                   -- display: 'Cricket', 'Table Tennis'
  category text,                        -- 'team', 'racquet', 'martial', etc.
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

-- Read by every authenticated user (so dropdowns work). Writes by super_admin.
alter table public.sports enable row level security;

create policy sports_authenticated_read on public.sports
  for select to authenticated using (true);

create policy sports_super_admin_write on public.sports
  for all to authenticated
  using (public.is_super_admin())
  with check (public.is_super_admin());

-- ---------------------------------------------------------------------------
-- sport_skills — default skill catalog per sport
-- ---------------------------------------------------------------------------
create table public.sport_skills (
  id uuid primary key default gen_random_uuid(),
  sport_id uuid not null references public.sports(id) on delete cascade,
  name text not null,
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  unique (sport_id, name)
);

create index idx_sport_skills_sport on public.sport_skills(sport_id, sort_order);

alter table public.sport_skills enable row level security;

create policy sport_skills_authenticated_read on public.sport_skills
  for select to authenticated using (true);

create policy sport_skills_super_admin_write on public.sport_skills
  for all to authenticated
  using (public.is_super_admin())
  with check (public.is_super_admin());

-- ---------------------------------------------------------------------------
-- academy_sports — which sports does this academy offer?
-- Optional `custom_name` lets an academy override the display label
-- (e.g. show 'Football' instead of 'Soccer').
-- ---------------------------------------------------------------------------
create table public.academy_sports (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies(id) on delete cascade,
  sport_id uuid not null references public.sports(id) on delete restrict,
  custom_name text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (academy_id, sport_id)
);

create index idx_academy_sports_academy on public.academy_sports(academy_id);

alter table public.academy_sports enable row level security;

create policy academy_sports_member_read on public.academy_sports
  for select using (
    public.is_super_admin()
    or academy_id = public.current_user_academy_id()
  );

create policy academy_sports_admin_insert on public.academy_sports
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create policy academy_sports_admin_update on public.academy_sports
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  )
  with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create policy academy_sports_admin_delete on public.academy_sports
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

-- ---------------------------------------------------------------------------
-- coach_sports — junction; a coach can be qualified for multiple sports.
-- (Replaces / supplements the legacy free-text `coaches.specialization[]`.)
-- ---------------------------------------------------------------------------
create table public.coach_sports (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies(id) on delete cascade,
  coach_id uuid not null references public.coaches(id) on delete cascade,
  sport_id uuid not null references public.sports(id) on delete restrict,
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  unique (coach_id, sport_id)
);

create index idx_coach_sports_coach on public.coach_sports(coach_id);
create index idx_coach_sports_academy on public.coach_sports(academy_id);

alter table public.coach_sports enable row level security;

create policy coach_sports_academy_read on public.coach_sports
  for select using (
    public.is_super_admin()
    or academy_id = public.current_user_academy_id()
  );

create policy coach_sports_admin_insert on public.coach_sports
  for insert with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create policy coach_sports_admin_update on public.coach_sports
  for update using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  )
  with check (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

create policy coach_sports_admin_delete on public.coach_sports
  for delete using (
    public.is_super_admin()
    or (academy_id = public.current_user_academy_id() and public.has_admin_or_higher())
  );

-- ---------------------------------------------------------------------------
-- Add nullable sport_id columns alongside the existing text columns.
-- Phase 3 drops the text. For now we keep both so backfill failures are
-- non-fatal — UIs can fall back to the text.
-- ---------------------------------------------------------------------------

alter table public.students                add column sport_id uuid references public.sports(id) on delete set null;
alter table public.batches                 add column sport_id uuid references public.sports(id) on delete set null;
alter table public.leads                   add column sport_id uuid references public.sports(id) on delete set null;
alter table public.events                  add column sport_id uuid references public.sports(id) on delete set null;
alter table public.performance_assessments add column sport_id uuid references public.sports(id) on delete set null;
alter table public.fee_structures          add column sport_id uuid references public.sports(id) on delete set null;

create index idx_students_sport                on public.students(sport_id)                where sport_id is not null;
create index idx_batches_sport                 on public.batches(sport_id)                 where sport_id is not null;
create index idx_events_sport                  on public.events(sport_id)                  where sport_id is not null;
create index idx_perf_assessments_sport        on public.performance_assessments(sport_id) where sport_id is not null;

-- ---------------------------------------------------------------------------
-- Audit hooks for the new tables.
-- ---------------------------------------------------------------------------
create trigger trg_audit_sports
  after insert or update or delete on public.sports
  for each row execute function public.write_audit_log();

create trigger trg_audit_sport_skills
  after insert or update or delete on public.sport_skills
  for each row execute function public.write_audit_log();

create trigger trg_audit_academy_sports
  after insert or update or delete on public.academy_sports
  for each row execute function public.write_audit_log();

create trigger trg_audit_coach_sports
  after insert or update or delete on public.coach_sports
  for each row execute function public.write_audit_log();

-- ---------------------------------------------------------------------------
-- Seed: India-relevant sports catalog.
-- ---------------------------------------------------------------------------
insert into public.sports (code, name, category) values
  ('cricket',       'Cricket',       'team'),
  ('football',      'Football',      'team'),
  ('badminton',     'Badminton',     'racquet'),
  ('tennis',        'Tennis',        'racquet'),
  ('basketball',    'Basketball',    'team'),
  ('swimming',      'Swimming',      'aquatic'),
  ('athletics',     'Athletics',     'individual'),
  ('hockey',        'Hockey',        'team'),
  ('table_tennis',  'Table Tennis',  'racquet'),
  ('chess',         'Chess',         'mind'),
  ('karate',        'Karate',        'martial'),
  ('taekwondo',     'Taekwondo',     'martial'),
  ('yoga',          'Yoga',          'fitness'),
  ('boxing',        'Boxing',        'martial'),
  ('volleyball',    'Volleyball',    'team'),
  ('kabaddi',       'Kabaddi',       'team'),
  ('squash',        'Squash',        'racquet'),
  ('skating',       'Skating',       'individual'),
  ('archery',       'Archery',       'individual'),
  ('gymnastics',    'Gymnastics',    'individual')
on conflict (code) do nothing;

-- Seed default skill catalog.
do $$
declare
  v_cricket uuid;       v_football uuid;     v_badminton uuid;
  v_tennis uuid;        v_basketball uuid;   v_swimming uuid;
  v_athletics uuid;     v_hockey uuid;       v_table_tennis uuid;
  v_chess uuid;         v_karate uuid;       v_taekwondo uuid;
  v_yoga uuid;          v_boxing uuid;       v_volleyball uuid;
  v_kabaddi uuid;       v_squash uuid;       v_skating uuid;
  v_archery uuid;       v_gymnastics uuid;
begin
  select id into v_cricket      from public.sports where code = 'cricket';
  select id into v_football     from public.sports where code = 'football';
  select id into v_badminton    from public.sports where code = 'badminton';
  select id into v_tennis       from public.sports where code = 'tennis';
  select id into v_basketball   from public.sports where code = 'basketball';
  select id into v_swimming     from public.sports where code = 'swimming';
  select id into v_athletics    from public.sports where code = 'athletics';
  select id into v_hockey       from public.sports where code = 'hockey';
  select id into v_table_tennis from public.sports where code = 'table_tennis';
  select id into v_chess        from public.sports where code = 'chess';
  select id into v_karate       from public.sports where code = 'karate';
  select id into v_taekwondo    from public.sports where code = 'taekwondo';
  select id into v_yoga         from public.sports where code = 'yoga';
  select id into v_boxing       from public.sports where code = 'boxing';
  select id into v_volleyball   from public.sports where code = 'volleyball';
  select id into v_kabaddi      from public.sports where code = 'kabaddi';
  select id into v_squash       from public.sports where code = 'squash';
  select id into v_skating      from public.sports where code = 'skating';
  select id into v_archery      from public.sports where code = 'archery';
  select id into v_gymnastics   from public.sports where code = 'gymnastics';

  insert into public.sport_skills (sport_id, name, sort_order) values
    (v_cricket, 'Batting', 1), (v_cricket, 'Bowling', 2),
    (v_cricket, 'Fielding', 3), (v_cricket, 'Wicket-keeping', 4),

    (v_football, 'Dribbling', 1), (v_football, 'Passing', 2),
    (v_football, 'Shooting', 3), (v_football, 'Defending', 4),
    (v_football, 'Ball control', 5), (v_football, 'Heading', 6),

    (v_badminton, 'Serve', 1), (v_badminton, 'Smash', 2),
    (v_badminton, 'Drop shot', 3), (v_badminton, 'Footwork', 4),
    (v_badminton, 'Net play', 5),

    (v_tennis, 'Forehand', 1), (v_tennis, 'Backhand', 2),
    (v_tennis, 'Serve', 3), (v_tennis, 'Volley', 4),
    (v_tennis, 'Footwork', 5),

    (v_basketball, 'Shooting', 1), (v_basketball, 'Dribbling', 2),
    (v_basketball, 'Passing', 3), (v_basketball, 'Rebounding', 4),
    (v_basketball, 'Defense', 5),

    (v_swimming, 'Freestyle', 1), (v_swimming, 'Backstroke', 2),
    (v_swimming, 'Breaststroke', 3), (v_swimming, 'Butterfly', 4),
    (v_swimming, 'Endurance', 5), (v_swimming, 'Turns', 6),

    (v_athletics, 'Sprint', 1), (v_athletics, 'Distance', 2),
    (v_athletics, 'Jumps', 3), (v_athletics, 'Throws', 4),

    (v_hockey, 'Stick skills', 1), (v_hockey, 'Passing', 2),
    (v_hockey, 'Shooting', 3), (v_hockey, 'Defending', 4),

    (v_table_tennis, 'Forehand', 1), (v_table_tennis, 'Backhand', 2),
    (v_table_tennis, 'Serve', 3), (v_table_tennis, 'Spin', 4),

    (v_chess, 'Openings', 1), (v_chess, 'Middlegame', 2),
    (v_chess, 'Endgame', 3), (v_chess, 'Tactics', 4),

    (v_karate, 'Kihon', 1), (v_karate, 'Kata', 2),
    (v_karate, 'Kumite', 3), (v_karate, 'Conditioning', 4),

    (v_taekwondo, 'Poomsae', 1), (v_taekwondo, 'Kyorugi', 2),
    (v_taekwondo, 'Kicks', 3), (v_taekwondo, 'Conditioning', 4),

    (v_yoga, 'Flexibility', 1), (v_yoga, 'Strength', 2),
    (v_yoga, 'Balance', 3), (v_yoga, 'Breathing', 4),

    (v_boxing, 'Footwork', 1), (v_boxing, 'Jab', 2),
    (v_boxing, 'Cross', 3), (v_boxing, 'Hook', 4),
    (v_boxing, 'Defense', 5),

    (v_volleyball, 'Serve', 1), (v_volleyball, 'Spike', 2),
    (v_volleyball, 'Block', 3), (v_volleyball, 'Setting', 4),
    (v_volleyball, 'Receive', 5),

    (v_kabaddi, 'Raiding', 1), (v_kabaddi, 'Defense', 2),
    (v_kabaddi, 'Tackling', 3), (v_kabaddi, 'Stamina', 4),

    (v_squash, 'Drop', 1), (v_squash, 'Drive', 2),
    (v_squash, 'Volley', 3), (v_squash, 'Boast', 4),

    (v_skating, 'Balance', 1), (v_skating, 'Crossovers', 2),
    (v_skating, 'Stops', 3), (v_skating, 'Tricks', 4),

    (v_archery, 'Stance', 1), (v_archery, 'Aim', 2),
    (v_archery, 'Release', 3), (v_archery, 'Consistency', 4),

    (v_gymnastics, 'Vault', 1), (v_gymnastics, 'Bars', 2),
    (v_gymnastics, 'Beam', 3), (v_gymnastics, 'Floor', 4)
  on conflict (sport_id, name) do nothing;
end $$;

-- ---------------------------------------------------------------------------
-- Backfill: best-effort match from existing text columns to sports.code or
-- sports.name (case-insensitive, trimmed). Rows whose text doesn't match a
-- catalog sport stay sport_id IS NULL — phase 3's UI maps those manually.
-- ---------------------------------------------------------------------------

create or replace function public.match_sport_text(p_text text)
returns uuid
language sql
stable
as $$
  select id from public.sports
  where p_text is not null
    and (lower(code) = lower(trim(p_text))
         or lower(name) = lower(trim(p_text))
         or lower(replace(replace(name, ' ', '_'), '-', '_'))
           = lower(replace(replace(trim(p_text), ' ', '_'), '-', '_')))
  limit 1
$$;

update public.students                set sport_id = public.match_sport_text(sport) where sport is not null and sport_id is null;
update public.batches                 set sport_id = public.match_sport_text(sport) where sport is not null and sport_id is null;
update public.leads                   set sport_id = public.match_sport_text(sport) where sport is not null and sport_id is null;
update public.events                  set sport_id = public.match_sport_text(sport) where sport is not null and sport_id is null;
update public.performance_assessments set sport_id = public.match_sport_text(sport) where sport is not null and sport_id is null;
update public.fee_structures          set sport_id = public.match_sport_text(sport) where sport is not null and sport_id is null;

-- Auto-populate academy_sports for any sport that's in use by an existing row
-- in that academy. Uses the four most authoritative source tables; misses
-- nothing material because if a fee_structure references a sport that no
-- student/batch uses, the academy operator can add it manually.
insert into public.academy_sports (academy_id, sport_id)
select distinct s.academy_id, s.sport_id
from (
  select academy_id, sport_id from public.students                where sport_id is not null
  union
  select academy_id, sport_id from public.batches                 where sport_id is not null
  union
  select academy_id, sport_id from public.leads                   where sport_id is not null
  union
  select academy_id, sport_id from public.events                  where sport_id is not null
  union
  select academy_id, sport_id from public.performance_assessments where sport_id is not null
) s
on conflict (academy_id, sport_id) do nothing;

-- Backfill coach_sports from coaches.specialization[]. Each text element is
-- run through match_sport_text; non-matches are silently skipped.
insert into public.coach_sports (academy_id, coach_id, sport_id)
select c.academy_id, c.id, public.match_sport_text(spec)
from public.coaches c, unnest(c.specialization) spec
where public.match_sport_text(spec) is not null
on conflict (coach_id, sport_id) do nothing;
