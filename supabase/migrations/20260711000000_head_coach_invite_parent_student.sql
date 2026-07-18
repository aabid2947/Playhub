-- ============================================================================
-- Allow a head_coach to provision parent/student LOGINS (owner decision).
--
-- A head_coach already creates + manages the students in their center
-- (can_manage_student is center-scoped for them), and the student edit screen's
-- "Logins & access" cards were already shown to them — but can_provision_role
-- routed parent/student through can_admin_center_scope(), which is admin-tier +
-- center_admin only, so a head_coach's invite 403'd.
--
-- Widen ONLY the parent/student branch of can_provision_role to also accept a
-- head_coach scoped to their own center(s). can_admin_center_scope() is left
-- UNTOUCHED (it's reused by the finance READ gate can_view_student_finance —
-- gating it there would block finance reads). Signature unchanged, so
-- create-or-replace preserves grants. Client mirror: capabilities.dart adds
-- parent/student to head_coach.invitableRoles.
-- ============================================================================

create or replace function public.can_provision_role(
  p_target_role user_role,
  p_center_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.academy_writes_allowed() and (
    case
      when (select role from public.users where id = auth.uid()) = 'super_admin'
        then true
      when public.role_rank((select role from public.users where id = auth.uid()))
           <= public.role_rank(p_target_role)
        then false
      when p_target_role in ('parent', 'student')
        then public.can_admin_center_scope(p_center_id)
          or (
            (select role from public.users where id = auth.uid()) = 'head_coach'
            and (p_center_id is null or public.current_user_in_center(p_center_id))
          )
      else case (select role from public.users where id = auth.uid())
        when 'academy_owner' then true
        when 'academy_admin' then true
        when 'center_admin'  then
          p_center_id is null or public.current_user_in_center(p_center_id)
        when 'head_coach'    then
          p_center_id is null or public.current_user_in_center(p_center_id)
        when 'coach'         then
          p_center_id is null or public.current_user_in_center(p_center_id)
        else false
      end
    end
  );
$$;
