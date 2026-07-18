-- ============================================================================
-- Phase 2 follow-up — head_coach may also manage UNSCOPED (null-sport) batches
-- in their own center, not only batches tagged with one of their sports.
--
-- Phase 2 (20260607000200) made head_coach STRICTLY sport-scoped: a batch with
-- a NULL sport_id was unmanageable by a head_coach. In practice many batches
-- carry no sport_id (legacy data; the create form doesn't force one), which
-- locked head_coaches out of editing / enrolling / attendance on legitimate
-- batches in their own center (RLS 42501 on batches / batch_enrollments / etc).
--
-- New head_coach rule on a batch: in their center AND
--   (the batch has NO sport  OR  the batch's sport is one of theirs).
-- Sport-tagged batches stay limited to the owning head_coach; untagged batches
-- fall back to plain center scope. Tradeoff: a head_coach can now touch any
-- sport-less batch in their center — acceptable vs. locking them out.
--
-- This relaxes every head_coach batch gate at once, because attendance /
-- performance go through batch_in_my_sport() and enrollment / staffing / edit
-- go through can_manage_batch_fields().
-- ============================================================================

create or replace function public.batch_in_my_sport(p_batch_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.batches b
    where b.id = p_batch_id
      and (b.sport_id is null or public.head_coach_owns_sport(b.sport_id))
  );
$$;

create or replace function public.can_manage_batch_fields(
  p_center_id uuid,
  p_sport_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case (select role from public.users where id = auth.uid())
    when 'academy_owner' then true
    when 'academy_admin' then true
    when 'center_admin'  then
      p_center_id is null or p_center_id = public.current_user_center_id()
    when 'head_coach'    then
      (p_center_id is null or p_center_id = public.current_user_center_id())
      and (p_sport_id is null or public.head_coach_owns_sport(p_sport_id))
    else false
  end;
$$;
