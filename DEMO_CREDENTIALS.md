# PlayHub — Demo Logins & Walkthrough

A fully-seeded **PlayHub Demo Academy** (Mumbai, 2 centers) is loaded for evaluation.
Every account below uses the same password.

> **Password (all accounts):** `Demo@1234`
> **Academy:** PlayHub Demo Academy · **Centers:** Andheri, Bandra

| Role | Email | Where to log in |
|---|---|---|
| Super admin (platform) | `superadmin@playhubdemo.in` | Web admin console / mobile super-admin |
| Academy owner | `owner@playhubdemo.in` | Mobile app |
| Academy admin | `admin@playhubdemo.in` | Mobile app |
| Center admin (Andheri) | `centeradmin@playhubdemo.in` | Mobile app |
| Head coach | `headcoach@playhubdemo.in` | Mobile app |
| Coach | `coach@playhubdemo.in` | Mobile app |
| Trainer | `trainer@playhubdemo.in` | Mobile app |
| Parent (2 children) | `parent@playhubdemo.in` | Mobile app |
| Student | `student@playhubdemo.in` | Mobile app |

> All data is **dummy**. The accounts and data can be wiped and regenerated at any time.

---

## What to try as each role

### Super admin — `superadmin@playhubdemo.in`
Platform-wide view (not tied to an academy). Open the **Health** dashboard, browse
**Academies** (toggle active/inactive), edit **Subscription Plans**, and open the
**Support** tab — there's an open ticket *"Need help importing students"* you can reply to.

### Academy owner — `owner@playhubdemo.in`
The full picture. Check the **KPI dashboard** (collection, revenue, enrolment, by-sport
breakdown), then browse **Students** (10), **Coaches** (5), **Batches** (4), **Fees**,
and **Invoices** — one is **paid**, one **partially paid**, one **overdue**. Look at
**Leads** (4, various stages), the published **Annual Cricket Tournament** event,
**Inventory** (the *Cricket Bat* shows a **low-stock** warning), and **Settings →
Subscription** (on the **Pro** plan, active). Owner-only: Academy Settings & Subscription.

### Academy admin — `admin@playhubdemo.in`
Same operational access as the owner for day-to-day management, **except** Academy
Settings and Subscription (owner-only). Good for showing delegated admin.

### Center admin (Andheri) — `centeradmin@playhubdemo.in`
Scoped to the **Andheri** center. Notice that students, batches and reports are
**narrowed to Andheri only** — Bandra's swimming/tennis batches and students don't appear.

### Head coach — `headcoach@playhubdemo.in`
Academy-wide coaching oversight. Open the **Cricket Juniors** batch — it already has
**attendance** marked and **performance assessments** recorded for two students. Head
coach can manage batches and record attendance/performance.

### Coach — `coach@playhubdemo.in`
Sees **only their own batch** (Football Evening). Mark attendance, record a
performance assessment, and **share photos & videos** of an enrolled student
(student page → **Photos & videos**).

### Trainer — `trainer@playhubdemo.in`
Sees their own batch (Swimming Beginners) and can **mark attendance**. A trainer still
**cannot record a scored assessment** — the "New assessment" action is intentionally
unavailable (trainer is one rung below coach) — but they **can share photos & videos**
of a student: open a student → **Photos & videos → Add photo / Add video**. These show up
on that student's and their parent's dashboard.

### Parent — `parent@playhubdemo.in`
Linked to **two children** (Aarav & Diya). View each child's batches, **attendance %**,
**performance trend**, **photos & videos** shared by their coach/trainer, and
**invoices**. Try **registering a child** for the upcoming *Annual Cricket Tournament*,
and open the chat.

### Student — `student@playhubdemo.in`
The student's own view (Aarav): **upcoming sessions** (next 7 days, from the batch
schedule), **weekly attendance**, **performance**, and **photos & videos** shared by
their coach/trainer.

---

*Generated for client evaluation. To regenerate from scratch (surgical wipe — preserves
schema, cron jobs, Vault, storage, and the seeded catalog): run `supabase/wipe.sql` then
`supabase/seed.sql` in the dashboard SQL editor, then
`node apps/web-admin/scripts/create_demo_users.mjs --wipe-all-users`.*
