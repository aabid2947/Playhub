-- ============================================================================
-- Drop centers.capacity — no consumer, was a misleading int that admins
-- expected to enforce something. Real scheduling-conflict / membership-cap
-- features (if ever needed) should be modeled explicitly, not on a single
-- nullable column.
-- ============================================================================

alter table public.centers drop column if exists capacity;
