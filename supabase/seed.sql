-- ============================================================================
-- PlayHub — DEMO SEED
--
-- Loaded automatically by `supabase db reset --linked` (config.toml →
-- [db.seed] sql_paths = ["./seed.sql"]) AFTER all migrations replay, so the
-- catalog tables (sports, sport_skills, subscription_plans) already exist and
-- are referenced by code, never re-inserted.
--
-- Runs as the admin/postgres connection → RLS is bypassed and auth.uid() is
-- NULL (audit_logs rows get a null user_id; harmless).
--
-- Deterministic UUIDs let scripts/create_demo_users.ts link the per-role
-- logins to specific coach / student / center rows. Keep these in sync with
-- the constants at the top of that script.
--
-- Single demo tenant: "PlayHub Demo Academy" (Mumbai), two centers.
-- ============================================================================

-- ---- Stable IDs (keep in sync with create_demo_users.ts) -------------------
-- academy  : a0000000-0000-4000-8000-000000000001
-- centerA   : 0ce00000-0000-4000-8000-00000000000a   (Andheri)
-- centerB   : 0ce00000-0000-4000-8000-00000000000b   (Bandra)
-- coachHead : 0c000000-0000-4000-8000-000000000001   ← head_coach login
-- coach1    : 0c000000-0000-4000-8000-000000000002   ← coach login
-- coach2    : 0c000000-0000-4000-8000-000000000003   ← trainer login
-- student1  : 05000000-0000-4000-8000-000000000001   ← student login + parent link
-- ----------------------------------------------------------------------------

begin;

-- == Academy & centers =======================================================
insert into public.academies (id, name, email, phone, city, state, invoice_prefix)
values ('a0000000-0000-4000-8000-000000000001',
        'PlayHub Demo Academy', 'hello@playhubdemo.in', '+919812345670',
        'Mumbai', 'Maharashtra', 'INV');
-- ^ AFTER-INSERT trigger auto-creates a 'basic' academy_subscriptions row.

insert into public.centers (id, academy_id, name, city, state, phone) values
  ('0ce00000-0000-4000-8000-00000000000a', 'a0000000-0000-4000-8000-000000000001',
   'Andheri Center', 'Mumbai', 'Maharashtra', '+919812345671'),
  ('0ce00000-0000-4000-8000-00000000000b', 'a0000000-0000-4000-8000-000000000001',
   'Bandra Center', 'Mumbai', 'Maharashtra', '+919812345672');

-- == Sports enabled per center (reference catalog by code) ===================
insert into public.center_sports (academy_id, center_id, sport_id)
select 'a0000000-0000-4000-8000-000000000001', '0ce00000-0000-4000-8000-00000000000a', id
  from public.sports where code in ('cricket','football','badminton');
insert into public.center_sports (academy_id, center_id, sport_id)
select 'a0000000-0000-4000-8000-000000000001', '0ce00000-0000-4000-8000-00000000000b', id
  from public.sports where code in ('swimming','tennis');

-- == Coaches =================================================================
insert into public.coaches
  (id, academy_id, center_id, first_name, last_name, email, phone,
   specialization, experience_years, qualifications, payment_type, salary)
values
  ('0c000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001',
   '0ce00000-0000-4000-8000-00000000000a','Rahul','Sharma','headcoach@playhubdemo.in','+919812345601',
   '{Senior coaching}', 12, '{Level 3 NCA}', 'monthly', 65000),
  ('0c000000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000001',
   '0ce00000-0000-4000-8000-00000000000a','Priya','Nair','coach@playhubdemo.in','+919812345602',
   '{}', 6, '{Level 2}', 'monthly', 40000),
  ('0c000000-0000-4000-8000-000000000003','a0000000-0000-4000-8000-000000000001',
   '0ce00000-0000-4000-8000-00000000000b','Arjun','Mehta','trainer@playhubdemo.in','+919812345603',
   '{}', 3, '{Swim instructor}', 'hourly', null),
  ('0c000000-0000-4000-8000-000000000004','a0000000-0000-4000-8000-000000000001',
   '0ce00000-0000-4000-8000-00000000000a','Sneha','Iyer',null,'+919812345604',
   '{}', 4, '{}', 'monthly', 38000),
  ('0c000000-0000-4000-8000-000000000005','a0000000-0000-4000-8000-000000000001',
   '0ce00000-0000-4000-8000-00000000000b','Vikram','Rao',null,'+919812345605',
   '{}', 8, '{Tennis Pro}', 'session', null);

insert into public.coach_sports (academy_id, coach_id, sport_id, is_primary)
select 'a0000000-0000-4000-8000-000000000001','0c000000-0000-4000-8000-000000000001', id, true
  from public.sports where code='cricket';
insert into public.coach_sports (academy_id, coach_id, sport_id, is_primary)
select 'a0000000-0000-4000-8000-000000000001','0c000000-0000-4000-8000-000000000002', id, true
  from public.sports where code='football';
insert into public.coach_sports (academy_id, coach_id, sport_id, is_primary)
select 'a0000000-0000-4000-8000-000000000001','0c000000-0000-4000-8000-000000000003', id, true
  from public.sports where code='swimming';
insert into public.coach_sports (academy_id, coach_id, sport_id, is_primary)
select 'a0000000-0000-4000-8000-000000000001','0c000000-0000-4000-8000-000000000005', id, true
  from public.sports where code='tennis';

-- == Students (10) ===========================================================
-- student1 doubles as the "student@" login; parent@ is linked to student1+2.
insert into public.students
  (id, academy_id, center_id, first_name, last_name, date_of_birth, gender,
   parent_name, parent_phone, parent_email, city, state, skill_level, sport_id, status)
select v.id::uuid, 'a0000000-0000-4000-8000-000000000001', v.center::uuid,
       v.fn, v.ln, v.dob::date, v.gender, v.pname, v.pphone, v.pemail,
       'Mumbai','Maharashtra', v.skill, (select id from public.sports where code=v.sport), 'active'
from (values
  ('05000000-0000-4000-8000-000000000001','0ce00000-0000-4000-8000-00000000000a','Aarav','Gupta','2014-03-12','male','Sunita Gupta','+919898000001','parent@playhubdemo.in','beginner','cricket'),
  ('05000000-0000-4000-8000-000000000002','0ce00000-0000-4000-8000-00000000000a','Diya','Gupta','2016-07-08','female','Sunita Gupta','+919898000001','parent@playhubdemo.in','beginner','badminton'),
  ('05000000-0000-4000-8000-000000000003','0ce00000-0000-4000-8000-00000000000a','Kabir','Singh','2013-01-22','male','Manpreet Singh','+919898000003',null,'intermediate','cricket'),
  ('05000000-0000-4000-8000-000000000004','0ce00000-0000-4000-8000-00000000000a','Ananya','Reddy','2015-11-30','female','Lakshmi Reddy','+919898000004',null,'beginner','football'),
  ('05000000-0000-4000-8000-000000000005','0ce00000-0000-4000-8000-00000000000a','Ishaan','Khan','2012-05-15','male','Imran Khan','+919898000005',null,'advanced','cricket'),
  ('05000000-0000-4000-8000-000000000006','0ce00000-0000-4000-8000-00000000000a','Myra','Joshi','2014-09-19','female','Neha Joshi','+919898000006',null,'beginner','football'),
  ('05000000-0000-4000-8000-000000000007','0ce00000-0000-4000-8000-00000000000b','Vivaan','Patel','2013-12-03','male','Hiren Patel','+919898000007',null,'intermediate','swimming'),
  ('05000000-0000-4000-8000-000000000008','0ce00000-0000-4000-8000-00000000000b','Saanvi','Desai','2015-02-27','female','Rupa Desai','+919898000008',null,'beginner','swimming'),
  ('05000000-0000-4000-8000-000000000009','0ce00000-0000-4000-8000-00000000000b','Reyansh','Shah','2011-08-11','male','Bhavin Shah','+919898000009',null,'advanced','tennis'),
  ('05000000-0000-4000-8000-000000000010','0ce00000-0000-4000-8000-00000000000b','Aadhya','Menon','2016-04-05','female','Gita Menon','+919898000010',null,'beginner','tennis')
) as v(id,center,fn,ln,dob,gender,pname,pphone,pemail,skill,sport);

-- == Batches =================================================================
insert into public.batches
  (id, academy_id, center_id, coach_id, name, sport_id, schedule, capacity,
   age_group, skill_level, start_date)
select v.id::uuid, 'a0000000-0000-4000-8000-000000000001', v.center::uuid, v.coach::uuid,
       v.name, (select id from public.sports where code=v.sport),
       v.sched::jsonb, v.cap, v.age, v.skill, current_date - 60
from (values
  ('0ba00000-0000-4000-8000-000000000001','0ce00000-0000-4000-8000-00000000000a','0c000000-0000-4000-8000-000000000001',
   'Cricket Juniors (Morning)','cricket','{"days":["mon","wed","fri"],"start_time":"07:00","end_time":"08:30"}',20,'8-12','beginner'),
  ('0ba00000-0000-4000-8000-000000000002','0ce00000-0000-4000-8000-00000000000a','0c000000-0000-4000-8000-000000000002',
   'Football Evening','football','{"days":["tue","thu","sat"],"start_time":"17:00","end_time":"18:30"}',24,'10-14','mixed'),
  ('0ba00000-0000-4000-8000-000000000003','0ce00000-0000-4000-8000-00000000000b','0c000000-0000-4000-8000-000000000003',
   'Swimming Beginners','swimming','{"days":["mon","wed"],"start_time":"16:00","end_time":"17:00"}',12,'8-12','beginner'),
  ('0ba00000-0000-4000-8000-000000000004','0ce00000-0000-4000-8000-00000000000b','0c000000-0000-4000-8000-000000000005',
   'Tennis Academy','tennis','{"days":["wed","fri","sun"],"start_time":"06:30","end_time":"08:00"}',8,'U-15','intermediate')
) as v(id,center,coach,name,sport,sched,cap,age,skill);

-- == Enrollments =============================================================
insert into public.batch_enrollments (academy_id, batch_id, student_id)
values
  ('a0000000-0000-4000-8000-000000000001','0ba00000-0000-4000-8000-000000000001','05000000-0000-4000-8000-000000000001'),
  ('a0000000-0000-4000-8000-000000000001','0ba00000-0000-4000-8000-000000000001','05000000-0000-4000-8000-000000000003'),
  ('a0000000-0000-4000-8000-000000000001','0ba00000-0000-4000-8000-000000000001','05000000-0000-4000-8000-000000000005'),
  ('a0000000-0000-4000-8000-000000000001','0ba00000-0000-4000-8000-000000000002','05000000-0000-4000-8000-000000000004'),
  ('a0000000-0000-4000-8000-000000000001','0ba00000-0000-4000-8000-000000000002','05000000-0000-4000-8000-000000000006'),
  ('a0000000-0000-4000-8000-000000000001','0ba00000-0000-4000-8000-000000000002','05000000-0000-4000-8000-000000000001'),
  ('a0000000-0000-4000-8000-000000000001','0ba00000-0000-4000-8000-000000000003','05000000-0000-4000-8000-000000000007'),
  ('a0000000-0000-4000-8000-000000000001','0ba00000-0000-4000-8000-000000000003','05000000-0000-4000-8000-000000000008'),
  ('a0000000-0000-4000-8000-000000000001','0ba00000-0000-4000-8000-000000000004','05000000-0000-4000-8000-000000000009'),
  ('a0000000-0000-4000-8000-000000000001','0ba00000-0000-4000-8000-000000000004','05000000-0000-4000-8000-000000000010');

-- == Fee structures + assignments ===========================================
insert into public.fee_structures
  (id, academy_id, name, type, base_amount, tax_pct, sport_id)
select v.id::uuid,'a0000000-0000-4000-8000-000000000001', v.name, v.type, v.amt, 0,
       (select id from public.sports where code=v.sport)
from (values
  ('0fee0000-0000-4000-8000-000000000001','Cricket Monthly','monthly',2000,'cricket'),
  ('0fee0000-0000-4000-8000-000000000002','Football Monthly','monthly',1800,'football'),
  ('0fee0000-0000-4000-8000-000000000003','Swimming Monthly','monthly',2500,'swimming'),
  ('0fee0000-0000-4000-8000-000000000004','Tennis Monthly','monthly',3000,'tennis')
) as v(id,name,type,amt,sport);

insert into public.student_fee_assignments (academy_id, student_id, fee_structure_id)
values
  ('a0000000-0000-4000-8000-000000000001','05000000-0000-4000-8000-000000000001','0fee0000-0000-4000-8000-000000000001'),
  ('a0000000-0000-4000-8000-000000000001','05000000-0000-4000-8000-000000000003','0fee0000-0000-4000-8000-000000000001'),
  ('a0000000-0000-4000-8000-000000000001','05000000-0000-4000-8000-000000000005','0fee0000-0000-4000-8000-000000000001'),
  ('a0000000-0000-4000-8000-000000000001','05000000-0000-4000-8000-000000000004','0fee0000-0000-4000-8000-000000000002'),
  ('a0000000-0000-4000-8000-000000000001','05000000-0000-4000-8000-000000000007','0fee0000-0000-4000-8000-000000000003');

-- == Discounts ===============================================================
insert into public.discount_structures (id, academy_id, name, type, value)
values ('0d1c0000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001',
        'Sibling Discount','percentage',10);
-- Diya (student2) is Aarav's sibling.
insert into public.student_discount_assignments
  (academy_id, student_id, discount_structure_id)
values ('a0000000-0000-4000-8000-000000000001','05000000-0000-4000-8000-000000000002',
        '0d1c0000-0000-4000-8000-000000000001');

-- == Invoices + line items + payments =======================================
-- Generated cols (invoices.amount, invoice_line_items.total_amount) are NOT
-- supplied. amount_paid/status start at issued-with-0; the payment-sync
-- trigger recomputes them when payments insert.
insert into public.invoices
  (id, academy_id, student_id, fee_structure_id, invoice_number, status,
   base_amount, tax_amount, discount_amount, due_date, period_start, period_end)
values
  ('011c0000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001','05000000-0000-4000-8000-000000000001','0fee0000-0000-4000-8000-000000000001','INV-000001','issued',2000,0,0, current_date + 5,  date_trunc('month',current_date)::date, (date_trunc('month',current_date) + interval '1 month - 1 day')::date),
  ('011c0000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000001','05000000-0000-4000-8000-000000000003','0fee0000-0000-4000-8000-000000000001','INV-000002','issued',2000,0,0, current_date + 5,  date_trunc('month',current_date)::date, (date_trunc('month',current_date) + interval '1 month - 1 day')::date),
  ('011c0000-0000-4000-8000-000000000003','a0000000-0000-4000-8000-000000000001','05000000-0000-4000-8000-000000000005','0fee0000-0000-4000-8000-000000000001','INV-000003','overdue',2000,0,0, current_date - 10, (date_trunc('month',current_date) - interval '1 month')::date, (date_trunc('month',current_date) - interval '1 day')::date),
  ('011c0000-0000-4000-8000-000000000004','a0000000-0000-4000-8000-000000000001','05000000-0000-4000-8000-000000000007','0fee0000-0000-4000-8000-000000000003','INV-000004','issued',2500,0,0, current_date + 7,  date_trunc('month',current_date)::date, (date_trunc('month',current_date) + interval '1 month - 1 day')::date);

insert into public.invoice_line_items (invoice_id, academy_id, kind, description, unit_amount, quantity)
values
  ('011c0000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001','base','Cricket Monthly — fee',2000,1),
  ('011c0000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000001','base','Cricket Monthly — fee',2000,1),
  ('011c0000-0000-4000-8000-000000000003','a0000000-0000-4000-8000-000000000001','base','Cricket Monthly — fee',2000,1),
  ('011c0000-0000-4000-8000-000000000004','a0000000-0000-4000-8000-000000000001','base','Swimming Monthly — fee',2500,1);

-- INV-000001 paid in full (→ trigger flips status to paid);
-- INV-000002 partially paid (→ partial); INV-000003/4 unpaid.
insert into public.payments (academy_id, invoice_id, student_id, amount, method, notes)
values
  ('a0000000-0000-4000-8000-000000000001','011c0000-0000-4000-8000-000000000001','05000000-0000-4000-8000-000000000001',2000,'upi_manual','Paid via UPI'),
  ('a0000000-0000-4000-8000-000000000001','011c0000-0000-4000-8000-000000000002','05000000-0000-4000-8000-000000000003',1000,'cash','Part payment');

-- Advance the per-academy invoice counter so app-generated numbers (INV-000005+)
-- don't collide with the seeded ones.
insert into public.academy_invoice_counters (academy_id, next_value)
values ('a0000000-0000-4000-8000-000000000001', 5)
on conflict (academy_id) do update set next_value = excluded.next_value;

-- == Attendance (last ~2 weeks for the cricket batch) ========================
insert into public.attendance_records
  (academy_id, batch_id, student_id, coach_id, date, status)
select 'a0000000-0000-4000-8000-000000000001','0ba00000-0000-4000-8000-000000000001',
       s.student::uuid, '0c000000-0000-4000-8000-000000000001', d.day, s.st
from (values
  ('05000000-0000-4000-8000-000000000001','present'),
  ('05000000-0000-4000-8000-000000000003','present'),
  ('05000000-0000-4000-8000-000000000005','late')
) as s(student, st)
cross join (values
  (current_date - 12), (current_date - 10), (current_date - 7),
  (current_date - 5), (current_date - 3)
) as d(day);

-- A couple of absences to make the % interesting.
update public.attendance_records set status='absent'
 where student_id='05000000-0000-4000-8000-000000000005'
   and date in (current_date - 10, current_date - 5);

-- == Performance assessments =================================================
insert into public.performance_assessments
  (id, academy_id, student_id, batch_id, coach_id, sport_id, assessment_date,
   overall_score, qualitative_feedback)
select v.id::uuid,'a0000000-0000-4000-8000-000000000001', v.student::uuid,
       '0ba00000-0000-4000-8000-000000000001','0c000000-0000-4000-8000-000000000001',
       (select id from public.sports where code='cricket'), current_date - 6,
       v.score, v.fb
from (values
  ('0a550000-0000-4000-8000-000000000001','05000000-0000-4000-8000-000000000001',7.5,'Strong improvement in batting stance.'),
  ('0a550000-0000-4000-8000-000000000002','05000000-0000-4000-8000-000000000005',8.5,'Excellent all-rounder; work on fielding focus.')
) as v(id,student,score,fb);

insert into public.performance_skills
  (assessment_id, academy_id, student_id, skill_name, score)
values
  ('0a550000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001','05000000-0000-4000-8000-000000000001','Batting',8),
  ('0a550000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001','05000000-0000-4000-8000-000000000001','Bowling',6),
  ('0a550000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001','05000000-0000-4000-8000-000000000001','Fielding',7),
  ('0a550000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000001','05000000-0000-4000-8000-000000000005','Batting',9),
  ('0a550000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000001','05000000-0000-4000-8000-000000000005','Bowling',8),
  ('0a550000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000001','05000000-0000-4000-8000-000000000005','Fielding',8);

-- == Leads (every lead has phone OR email per the contact CHECK) =============
insert into public.leads
  (id, academy_id, first_name, last_name, phone, email, status, source,
   preferred_center_id, sport_id, next_followup_at, notes)
select v.id::uuid,'a0000000-0000-4000-8000-000000000001', v.fn, v.ln, v.phone, v.email,
       v.status::public.lead_status, v.source::public.lead_source,
       '0ce00000-0000-4000-8000-00000000000a',
       (select id from public.sports where code=v.sport),
       case when v.followup then now() + interval '2 days' else null end, v.notes
from (values
  ('01ead000-0000-4000-8000-000000000001','Rohan','Verma','+919812000001',null,'new','website','cricket',true,'Enquired about morning cricket batch.'),
  ('01ead000-0000-4000-8000-000000000002','Pooja','Bhatt',null,'pooja.bhatt@example.in','contacted','instagram','badminton',true,'Wants weekend slots.'),
  ('01ead000-0000-4000-8000-000000000003','Karan','Malhotra','+919812000003',null,'trial_scheduled','referral','football',true,'Trial booked for Saturday.'),
  ('01ead000-0000-4000-8000-000000000004','Nisha','Pillai','+919812000004','nisha.p@example.in','lost','walk_in','tennis',false,'Chose a closer academy.')
) as v(id,fn,ln,phone,email,status,source,sport,followup,notes);

insert into public.lead_activities (academy_id, lead_id, kind, content)
values
  ('a0000000-0000-4000-8000-000000000001','01ead000-0000-4000-8000-000000000002','call_logged','Called; interested, asked for fee details.'),
  ('a0000000-0000-4000-8000-000000000001','01ead000-0000-4000-8000-000000000003','trial_scheduled','Trial scheduled for Saturday 9 AM.');

-- == Event + registrations ===================================================
insert into public.events
  (id, academy_id, center_id, title, description, kind, status, sport_id,
   starts_at, ends_at, registration_opens_at, registration_closes_at,
   location, fee_amount, capacity)
select '0e110000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001',
       '0ce00000-0000-4000-8000-00000000000a',
       'Annual Cricket Tournament','Inter-batch knockout tournament.',
       'tournament','published', (select id from public.sports where code='cricket'),
       now() + interval '20 days', now() + interval '20 days 6 hours',
       now() - interval '2 days', now() + interval '15 days',
       'Andheri Center Ground', 300, 40;

insert into public.event_registrations (academy_id, event_id, student_id, fee_paid)
values
  ('a0000000-0000-4000-8000-000000000001','0e110000-0000-4000-8000-000000000001','05000000-0000-4000-8000-000000000001',false),
  ('a0000000-0000-4000-8000-000000000001','0e110000-0000-4000-8000-000000000001','05000000-0000-4000-8000-000000000005',true);

-- == Inventory ===============================================================
insert into public.vendors (id, academy_id, name, contact_name, phone)
values ('0fed0000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001',
        'SportsGear India','Amit Shah','+919811112222');

insert into public.inventory_categories (id, academy_id, name) values
  ('0ca70000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001','Equipment'),
  ('0ca70000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000001','Apparel');

-- on_hand starts at 0 (default) and is driven entirely by the movement ledger
-- below (the after-insert trigger does on_hand += qty). reorder_threshold on
-- the bat is set high so it lands below threshold → "low stock" demo.
insert into public.inventory_items
  (id, academy_id, category_id, center_id, vendor_id, name, sku, unit, unit_cost, reorder_threshold)
values
  ('0171e000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001','0ca70000-0000-4000-8000-000000000001','0ce00000-0000-4000-8000-00000000000a','0fed0000-0000-4000-8000-000000000001','Cricket Bat (SS)','BAT-001','piece',1200,25),
  ('0171e000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000001','0ca70000-0000-4000-8000-000000000001','0ce00000-0000-4000-8000-00000000000a','0fed0000-0000-4000-8000-000000000001','Football (size 5)','FB-005','piece',800,10),
  ('0171e000-0000-4000-8000-000000000003','a0000000-0000-4000-8000-000000000001','0ca70000-0000-4000-8000-000000000002','0ce00000-0000-4000-8000-00000000000a','0fed0000-0000-4000-8000-000000000001','Training Jersey','JER-001','piece',350,40);

-- Movement signs validated by trg_inv_movement_validate: in/return > 0, out < 0.
insert into public.inventory_movements (academy_id, item_id, kind, qty, unit_cost, reference)
values
  ('a0000000-0000-4000-8000-000000000001','0171e000-0000-4000-8000-000000000001','in',20,1200,'PO-1001'),
  ('a0000000-0000-4000-8000-000000000001','0171e000-0000-4000-8000-000000000002','in',30,800,'PO-1001'),
  ('a0000000-0000-4000-8000-000000000001','0171e000-0000-4000-8000-000000000003','in',60,350,'PO-1002'),
  ('a0000000-0000-4000-8000-000000000001','0171e000-0000-4000-8000-000000000001','out',-3,null,'Issued to coaches');
-- Net: Bat on_hand = 17 (< 25 → low stock), Football = 30, Jersey = 60.

-- == Announcement ============================================================
insert into public.announcements
  (academy_id, subject, body, target_roles, via_in_app, via_push, sent_at, sent_count)
values
  ('a0000000-0000-4000-8000-000000000001','Holiday Notice',
   'The academy will remain closed this Sunday for ground maintenance.',
   '{parent,student}'::public.user_role[], true, true, now() - interval '1 day', 10);

-- == Support ticket (for the super-admin demo) ===============================
insert into public.support_tickets (id, academy_id, subject, body, priority, status)
values ('0717c000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001',
        'Need help importing students','We have ~50 students in a spreadsheet. How do we bulk import?',
        'normal','open');
insert into public.support_ticket_messages (ticket_id, academy_id, body, is_staff)
values ('0717c000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001',
        'We have ~50 students in a spreadsheet. How do we bulk import?', false);

-- == Subscription: promote the auto-created basic row to an active Pro plan ==
update public.academy_subscriptions
   set plan_id = (select id from public.subscription_plans where code='pro'),
       status = 'active',
       billing_cycle = 'monthly',
       current_period_start = now(),
       current_period_end = now() + interval '1 month'
 where academy_id = 'a0000000-0000-4000-8000-000000000001';

update public.academies set subscription_status = 'active'
 where id = 'a0000000-0000-4000-8000-000000000001';

commit;
