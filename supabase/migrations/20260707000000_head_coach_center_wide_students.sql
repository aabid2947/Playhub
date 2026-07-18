-- ============================================================================
-- head_coach STUDENT read widened to their CENTER (reverses 20260608000500).
--
-- 20260608000500 narrowed a head_coach's student view to "students actively
-- enrolled in a batch in their center AND their sport". That dead-ended
-- onboarding: a head_coach can CREATE a student (can_manage_student is
-- center-wide) but the new, not-yet-enrolled student was invisible to them AND
-- absent from the batch "Enrol" picker (both draw from the students read), so
-- they could never enrol the student they had just added.
--
-- Product decision (owner sign-off): a head_coach may now SEE every student in
-- their own center — home center + any user_centers grant, or a null-center
-- student — the same reach as their existing center-wide student WRITE
-- (can_manage_student) and as center_admin. This removes the read < write
-- asymmetry for head_coach students and makes the add -> enrol loop work.
--
-- Reuses student_in_my_center() (student's center in my center set, or null).
-- TRADEOFF: a head_coach now also sees OTHER sports' students in their center.
-- Batches and coaches stay center+sport-scoped; only the STUDENT read changed.
-- No tenancy change — still bounded to the head_coach's academy + center(s).
--
-- Backend-only: the mobile studentsProvider already relies on RLS for
-- head_coach (no client-side center/sport filter), so this needs no app change.
-- ============================================================================

create or replace function public.head_coach_sees_student(p_student_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case (select role from public.users where id = auth.uid())
    when 'head_coach' then public.student_in_my_center(p_student_id)
    else true  -- every other role governed by the existing read clauses
  end;
$$;
