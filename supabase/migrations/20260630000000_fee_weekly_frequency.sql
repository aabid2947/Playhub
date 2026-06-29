-- Add a 'weekly' billing frequency to fee structures.
--
-- The original fees migration (20260504000000) constrained type to
-- ('monthly','quarterly','annual','one_time'). Weekly billing was requested for
-- short-cycle programmes (camps, weekly drop-in coaching). The recur-invoice
-- cron anchors weekly periods to the assignment's start_date (rolling 7-day
-- windows), so billing_day stays NULL for weekly fees — no other column change.
--
-- Append-only per invariant #5: drop the auto-named inline check and re-add it
-- widened. Idempotent so it applies cleanly on the manually-maintained DB.

alter table public.fee_structures
  drop constraint if exists fee_structures_type_check;

alter table public.fee_structures
  add constraint fee_structures_type_check
  check (type in ('weekly', 'monthly', 'quarterly', 'annual', 'one_time'));
