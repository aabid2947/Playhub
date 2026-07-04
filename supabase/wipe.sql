-- ============================================================================
-- PlayHub — SURGICAL WIPE of all tenant/operational data.
--
-- Run this in the Supabase dashboard SQL editor (runs as `postgres`), THEN
-- run create_demo_users.mjs --wipe-all-users (which clears auth.users logins
-- AND re-seeds the demo tenant). No DB password needed in the SQL editor.
--
-- What it CLEARS: every tenant + operational row (academies, centers, users,
-- students, coaches, batches, attendance, invoices, payments, leads, events,
-- inventory, messages, notifications, audit_logs, support, subscriptions, …).
-- public.users IS included; auth.users LOGINS are cleared separately.
--
-- What it PRESERVES: schema, RLS, functions, triggers, cron, Vault, storage
-- buckets, AND the migration-seeded CATALOG — public.sports, sport_skills,
-- subscription_plans (seed.sql assumes these already exist; it never re-inserts
-- them, so we must NOT drop them here).
--
-- ⚠️ WHY DELETE, NOT `TRUNCATE ... CASCADE` (changed 2026-07-04):
--   • `sports` now has a live FK `sports.academy_id → academies` (custom
--     sports, migration 20260614000400). `TRUNCATE academies CASCADE` would
--     therefore truncate the ENTIRE sports table (all global sports too) and
--     cascade on to sport_skills — destroying the catalog seed.sql depends on.
--   • Row DELETEs fire the `write_audit_log()` triggers on every table, which
--     insert an audit_logs row referencing the row's (being-deleted) academy →
--     self-referential FK violation mid-cascade.
--   Both problems vanish under `session_replication_role = replica`, which
--   disables user triggers AND referential-integrity (FK) triggers for the
--   session. So we DELETE an explicit tenant-table list (never touching the
--   catalog), order-independently, with no audit writes and no cascade.
-- ============================================================================

begin;

-- Disable audit triggers + FK enforcement for this transaction only.
-- Requires the `postgres` role (the SQL editor's default). If this errors with
-- "permission denied to set parameter", run the SQL editor as the project owner.
set local session_replication_role = replica;

do $$
declare
  t text;
  -- Every tenant/operational table. Guarded by to_regclass so a table that
  -- doesn't exist on a drifted DB is skipped rather than aborting the wipe.
  -- Catalog tables (sports, sport_skills, subscription_plans) are deliberately
  -- ABSENT from this list — they are preserved.
  tenant_tables text[] := array[
    -- org
    'academies','centers','users','user_centers',
    -- people
    'coaches','coach_documents','coach_sports',
    'students','student_documents','parent_links','center_sports',
    -- batches / activity
    'batches','batch_enrollments','batch_staff',
    'attendance_records',
    'performance_assessments','performance_skills','performance_media',
    -- billing
    'fee_structures','student_fee_assignments','batch_fee_assignments',
    'discount_structures','student_discount_assignments','batch_discount_assignments',
    'academy_invoice_counters','invoices','invoice_line_items',
    'payments','payment_attempts','refunds',
    'academy_payment_gateways',
    -- crm / comms
    'leads','lead_activities',
    'announcements','announcement_recipients',
    'message_threads','messages','thread_participants',
    'notifications','notification_preferences','device_tokens',
    'audit_logs',
    -- events
    'events','event_registrations','event_results',
    -- inventory
    'vendors','inventory_categories','inventory_items','inventory_movements','inventory_stock',
    -- saas billing / support
    'academy_subscriptions','saas_invoices','saas_payments',
    'support_tickets','support_ticket_messages'
  ];
begin
  foreach t in array tenant_tables loop
    if to_regclass('public.' || t) is not null then
      execute format('delete from public.%I', t);
    end if;
  end loop;
end $$;

-- session_replication_role reset happens automatically at COMMIT (set LOCAL).
commit;

-- ---- Verify: tenant tables empty, catalog intact -----------------------------
select 'academies' as t, count(*) from public.academies
union all select 'users', count(*) from public.users
union all select 'students', count(*) from public.students
union all select 'invoices', count(*) from public.invoices
union all select 'payments', count(*) from public.payments
union all select 'audit_logs', count(*) from public.audit_logs
union all select '--- catalog (should be > 0) ---', null
union all select 'sports (PRESERVED)', count(*) from public.sports
union all select 'sport_skills (PRESERVED)', count(*) from public.sport_skills
union all select 'subscription_plans (PRESERVED)', count(*) from public.subscription_plans
order by 1;
