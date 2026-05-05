-- ============================================================================
-- Sprint 3 follow-up — collapse the dual-layer late-fee config.
--
-- Before: academies.late_fee_grace_days + late_fee_policy were defaults
-- that fee_structures could override. Two places to set the same thing.
-- After: late-fee config lives only on fee_structures. Manual invoices
-- (no fee_structure_id) get no late fees — `mark-overdue` skips them.
-- invoice_prefix stays on academies (it's branding, not policy).
-- ============================================================================

alter table public.academies
  drop column if exists late_fee_grace_days,
  drop column if exists late_fee_policy;

-- Backfill any nulls left over from the previous nullable design, then
-- pin the columns NOT NULL so the form always writes a value.
update public.fee_structures
  set late_fee_policy = coalesce(late_fee_policy, 'one_time'),
      late_fee_grace_days = coalesce(late_fee_grace_days, 5);

alter table public.fee_structures
  alter column late_fee_policy set default 'one_time',
  alter column late_fee_policy set not null,
  alter column late_fee_grace_days set default 5,
  alter column late_fee_grace_days set not null;
