-- ============================================================================
-- A batch now REQUIRES a center (was nullable). Completes batch scoping: with
-- sport_id + coach_id already NOT NULL (20260710000000), every batch is fully
-- scoped to center + sport + coach. Mirrors the app form guard.
--
-- The FK flips ON DELETE SET NULL -> RESTRICT for consistency with the other
-- creation-chain FKs: deleting a center still referenced by a batch is now
-- blocked (reassign the batch first) rather than silently nulling it.
--
-- Safe as a plain SET NOT NULL because the batches table is empty at apply time;
-- had any null-center batch existed the statement (and the whole tx) would abort.
-- ============================================================================

begin;

alter table public.batches
  drop constraint batches_center_id_fkey,
  add  constraint batches_center_id_fkey
       foreign key (center_id) references public.centers(id) on delete restrict;

alter table public.batches alter column center_id set not null;

commit;
