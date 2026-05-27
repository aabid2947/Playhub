-- ============================================================================
-- PlayHub — SURGICAL WIPE of all tenant/operational data.
--
-- Run this in the Supabase dashboard SQL editor (or psql) on the target DB,
-- THEN run seed.sql, THEN create_demo_users.mjs. No DB password needed if you
-- use the dashboard SQL editor.
--
-- What it CLEARS: every tenant + operational table (academies → cascades to
-- centers, users, students, coaches, batches, attendance, invoices, payments,
-- leads, events, inventory, messages, notifications, audit_logs, support, …).
-- public.users is included; auth.users LOGINS are cleared separately by
-- create_demo_users.mjs --wipe-all-users.
--
-- What it PRESERVES (untouched): the schema, RLS, functions, triggers, the
-- cron schema + ALL cron.job entries, the Vault secret, the extensions,
-- storage buckets, and the migration-seeded CATALOG — public.sports,
-- public.sport_skills, public.subscription_plans (NOT listed below).
--
-- TRUNCATE ... CASCADE handles FK ordering. Every tenant table chains back to
-- academies, so CASCADE also sweeps up anything not explicitly named here.
-- ============================================================================

begin;

truncate table
  public.academies,
  public.centers,
  public.users,
  public.coaches,
  public.coach_documents,
  public.coach_sports,
  public.students,
  public.student_documents,
  public.parent_links,
  public.center_sports,
  public.batches,
  public.batch_enrollments,
  public.attendance_records,
  public.performance_assessments,
  public.performance_skills,
  public.performance_media,
  public.fee_structures,
  public.student_fee_assignments,
  public.batch_fee_assignments,
  public.discount_structures,
  public.student_discount_assignments,
  public.batch_discount_assignments,
  public.academy_invoice_counters,
  public.invoices,
  public.invoice_line_items,
  public.payments,
  public.payment_attempts,
  public.refunds,
  public.leads,
  public.lead_activities,
  public.announcements,
  public.announcement_recipients,
  public.message_threads,
  public.messages,
  public.thread_participants,
  public.notifications,
  public.notification_preferences,
  public.device_tokens,
  public.audit_logs,
  public.events,
  public.event_registrations,
  public.event_results,
  public.vendors,
  public.inventory_categories,
  public.inventory_items,
  public.inventory_movements,
  public.academy_subscriptions,
  public.saas_invoices,
  public.saas_payments,
  public.support_tickets,
  public.support_ticket_messages
cascade;

commit;
