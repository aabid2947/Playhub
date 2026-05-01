-- ============================================================================
-- Academy operating hours + holiday calendar
-- ============================================================================

alter table public.academies
  add column if not exists hours_open time,
  add column if not exists hours_close time,
  add column if not exists holidays date[] not null default '{}';
