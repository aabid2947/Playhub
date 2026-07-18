-- Add optional per-day pricing metadata to fee_structures.
--
-- price_per_day is informational — it records the daily rate the owner used
-- to derive base_amount so the UI can show it when editing the fee.
-- base_amount remains the single source of truth for what gets billed.
-- No RLS change: existing fee_structures policies cover all columns.

alter table fee_structures
  add column if not exists price_per_day decimal(10, 2) null,
  add column if not exists days_per_week  smallint        null
    check (days_per_week between 1 and 7);

comment on column fee_structures.price_per_day is
  'Optional daily rate (INR) used when the fee was set up with per-day pricing. Informational — base_amount is the billed figure.';
comment on column fee_structures.days_per_week is
  'Number of days per week the batch meets, stored alongside price_per_day so the calculation can be reconstructed on edit.';
