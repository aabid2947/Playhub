-- ============================================================================
-- Trial usage quota — cap batches at 2 during a free trial. Same RESTRICTIVE
-- policy pattern as 20260629000000 (independent of the freeze layer; INSERT
-- only; excludes the new row by id to keep the count boundary unambiguous).
-- ============================================================================

create or replace function public.trial_allows_batch(
  p_academy_id uuid,
  p_row_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select not public.academy_on_trial()
    or (
      select count(*) from public.batches b
      where b.academy_id = p_academy_id
        and b.id <> p_row_id
    ) < 2;
$$;

grant execute on function public.trial_allows_batch(uuid, uuid) to authenticated;

drop policy if exists trial_quota_batches_insert on public.batches;
create policy trial_quota_batches_insert on public.batches
  as restrictive
  for insert
  with check (public.trial_allows_batch(academy_id, id));
