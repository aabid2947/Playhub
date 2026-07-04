# PlayHub — Academy Owner's Guide (Step by Step)

A plain-English walkthrough for setting up and running your academy in PlayHub.
No technical knowledge needed. Follow the parts **in order** — each part builds
on the one before it.

---

## The big picture (why order matters)

Think of your academy like a building. You can't hang a door before the walls
are up. In PlayHub the "walls first" order is:

```
1. Your Academy        ← created once, everything lives inside it
2. Centers  +  Sports  ← your locations and the games you teach
3. Your Team           ← admins, head coaches, coaches, trainers
4. Batches             ← a class = one sport + one center + one coach + a schedule
5. Students            ← the children/players
6. Fees + Payments     ← what each student owes and how they pay
7. Attendance + Performance  ← the daily running
8. Parent / Student logins   ← families get their own app access
```

If you try to do a later step first (e.g. create a batch before you've added a
sport or a coach), the app won't let you finish it — because the pieces it needs
don't exist yet. So just go top to bottom the first time.

**One golden rule:** you must **create your Academy first**. Every other thing —
every center, coach, student, batch, payment — is automatically tied to your
academy. Nobody can see another academy's data.

---

## Part 1 — Create your account and your academy

This is the only thing you do before anything else.

1. Open the PlayHub app and tap **Sign up**.
2. Enter your **email** and a **password**, and confirm your email if asked.
3. When you log in the first time, PlayHub sees you don't have an academy yet and
   shows the **"Set up your academy"** screen.
4. Type your **Academy name** (for example, *Elite Cricket Academy*).
5. Choose how to start:
   - **Start 14-day free trial** — try everything free. *(The free trial is
     limited: 1 sport, up to 2 coaches, 2 batches, and 5 students. Subscribe to
     lift these limits.)*
   - **Subscribe — ₹100/month** — unlock the full academy right away.
6. Tap it. Your academy is created and you land on the **Home** screen.

You are now the **Academy Owner** — the top of the ladder. You can do everything.

> **Where am I now?** The bottom of the screen has five tabs:
> **Home · Students · Coaches · Batches · Settings.** You'll use all of them.

---

## Part 2 — Set up your academy's structure

Go to the **Settings** tab (bottom right). Under **Academy** you'll do three
things: Centers, Sports, and Payments.

### 2a. Add your Centers (locations)

A "center" is a physical location (a ground, a hall, a branch). Even if you have
only one location, add it — batches and staff are attached to a center.

1. **Settings → Centers.**
2. Tap **Add** (the **+**), enter the center's name and address, and save.
3. Repeat for each location you run.

### 2b. Choose your Sports

Batches are always tied to a sport, so turn on your sports before making batches.

1. **Settings → Sports.**
2. Search for a sport (e.g. *Cricket*) and turn it **on** for your center.
3. If your sport isn't in the list, type its name and tap **Create "…"** to add
   your own custom sport, then enable it.

### 2c. Set up online payments (so students can pay in the app)

To let parents/students pay fees inside the app, connect your own payment account
(Razorpay or Paytm).

1. **Settings → Payment gateways.**
2. Enter your Razorpay (or Paytm) keys and turn the gateway **on**.
3. *(Owner-only — even an academy admin can't see or change these keys.)*

> You can skip this for now and still record cash/manual payments — but the
> **"Pay"** button for families only works once a gateway is switched on.

---

## Part 3 — Build your team (who to create first)

Now invite the people who help you run the academy. PlayHub has a **ladder** —
each role can do the roles below it, scoped to where they work. Create them in
this order:

| Order | Role | What they do | Where they work |
|------|------|--------------|-----------------|
| 1 | **Academy Admin** | Almost everything you do (except academy settings, subscription, payment keys) | Whole academy |
| 2 | **Center Admin** | Runs one (or more) centers end-to-end: students, coaches, batches, fees for that center | Their center(s) |
| 3 | **Head Coach** | Runs a sport at a center: its batches, students, attendance | Their center + their sport |
| 4 | **Coach** | Runs the specific batches assigned to them | Their batches |
| 5 | **Trainer** | Assists on batches: attendance + performance | Their batches |

*(You'll invite Parents and Students later, in Part 8 — they need student records
to link to first.)*

**How to invite a team member:**

1. **Settings → Team → Invite** (the **+**).
2. Enter their **email**, pick their **role**, and (for center staff) their
   **center**.
3. Send it. They get an email, click the link, set their own password, and log
   in — landing straight in the right screens for their role.

> You don't have to invite everyone now. At minimum, you can run the academy
> yourself and add staff as you grow.

---

## Part 4 — Add your Coaches

Before you can create a batch, you need at least one **coach record** — that's the
coach you'll put in charge of the class.

1. Go to the **Coaches** tab (bottom bar).
2. Tap **New coach**.
3. Fill in their name, sport(s), center, and details, then save.

> **Two different things:** a *coach record* (here, in the Coaches tab) is the
> profile you assign to batches. Giving that coach *app access* is a separate
> step — invite them in **Settings → Team** as a *Coach* or *Head Coach*, which
> links their login to this record. A coach can exist as a record without a login,
> and you can add their login later.

---

## Part 5 — Create your Batches (classes)

A **batch** is one class. It needs: a **center**, a **sport**, a **coach**, a
**schedule**, and a **capacity**. That's why Parts 2–4 came first.

1. Go to the **Batches** tab.
2. Tap **New batch**.
3. Choose the **center**, the **sport**, the **coach** in charge, the **days &
   times**, and the **maximum number of students** (capacity).
4. Save. The batch now appears in your list.

---

## Part 6 — Add your Students

1. Go to the **Students** tab.
2. To add one student, tap **New student** and fill in the child's details
   (name, parent/guardian name and phone, center, sport, etc.).
3. To add many at once, tap the **Import CSV** icon (top of the Students list)
   and upload a spreadsheet.

At this stage a student exists but isn't in any class yet.

> **Important:** adding a student here creates a **record only** — it does **not**
> send any email and does **not** create a login for the student. It's just their
> information in your system (so you can enroll, bill, and track them). Giving a
> student or parent their own app access (which *does* send an email) is a
> separate step — see **Part 12**.

---

## Part 7 — Put students into batches (enroll)

1. Go to the **Batches** tab and **open the batch** you want.
2. Tap **Enroll** (or the add-student control) and pick the students to add.
3. They now appear on that batch's roster. (If the batch is full, extra students
   go on a waitlist you can promote later.)

> A student can be in more than one batch.

---

## Part 8 — Set up Fees and assign them

### 8a. Create a fee

1. From the **Home** tab, tap **Billing** → the **Fees** tab.
   *(Or open a batch/student and use its Fees section.)*
2. Tap **New fee** and set it up:
   - **Name** (e.g. *Monthly Cricket Fee*)
   - **How often** it's charged: *weekly, monthly, quarterly, yearly,* or
     *one-time*
   - **Amount** and any **tax**.

### 8b. Assign the fee (this is what creates the bill)

You can charge a whole batch at once, or a single student.

- **A whole batch:** open the batch → **Fees** section → **Assign fee to batch**.
- **One student:** open the student → **Fees** section → **Assign fee**.

The moment you assign a fee, PlayHub creates that period's **invoice** for each
affected student straight away — you don't wait for the next day. The student (and
their parent) will see the amount due and a **Pay** button.

> **Note:** if you add a fee to a batch and *later* enroll a new student into that
> batch, re-assign the fee (or wait for the nightly run) so the new student also
> gets billed.

---

## Part 9 — Collect payments

- **Online:** the parent/student taps **Pay** on their dues and pays by card/UPI
  through your connected gateway (Part 2c). The invoice is marked paid
  automatically.
- **Cash / manual:** open the invoice and record the payment yourself.
- **Download an invoice:** anyone viewing a bill can tap the download icon to get
  a PDF.

> The **Pay** button only works after you've switched on a payment gateway in
> **Settings → Payment gateways.** Without it, the button shows a "set up
> payments" message.

---

## Part 10 — Mark attendance

Two easy ways:

- **Fastest:** on the **Home** tab, tap **Today's sessions** to see the classes
  running today, then mark who's present.
- **From a batch:** open any batch and tap **Mark attendance** (top of the batch
  screen).

Tick each student present/absent and save. There's also a **Live attendance**
view on Home to watch attendance across all batches in real time.

> A coach or trainer can only mark attendance for **their own batches**. A head
> coach covers **their sport at their center**. You and your admins can mark any
> batch.

---

## Part 11 — Record performance (optional)

To log skills, scores, or progress notes:

1. Open a **student** (or a **batch**), and choose to record a performance
   assessment or attach a photo/video.
2. Coaches and trainers can do this for their own batches; you and admins,
   anywhere.

---

## Part 12 — Give parents and students their own logins

So families can see attendance, progress, and dues — and pay — give them app
access. Do this **after** the student records exist (Part 6).

- **Parent login:** **Settings → Team → Invite**, choose role **Parent**, and
  link them to their child's student record. They'll see only their own child.
- **Student login:** invite with role **Student**, linked to that student record.
  They'll see only themselves.

They get an email, set a password, and log in to their own simplified view.

---

## Part 13 — Running it day to day

From the **Home** tab you also get:

- **KPI dashboard** — revenue, enrollment, attendance trends, sport breakdown.
- **Announcements** — send notices to families (and staff) by push/in-app/email.
- **Leads** — track prospective students through your enquiry funnel.
- **Events** — tournaments, workshops, certificates.
- **Inventory** — track equipment and stock across centers.
- **Messages / Notifications** — chat and your in-app alert feed.

---

## Quick reference — "Where do I…?"

| I want to… | Go to |
|---|---|
| Create my academy | First login → **Set up your academy** |
| Add a location | **Settings → Centers** |
| Turn on a sport | **Settings → Sports** |
| Connect online payments | **Settings → Payment gateways** |
| Invite an admin / coach / trainer | **Settings → Team → Invite** |
| Add a coach record | **Coaches → New coach** |
| Create a class | **Batches → New batch** |
| Add a student | **Students → New student** (or **Import CSV**) |
| Put a student in a class | **Batches → open batch → Enroll** |
| Create a fee | **Home → Billing → Fees → New fee** |
| Charge a batch / student | Batch or student → **Fees → Assign fee** |
| See who owes money | **Home → Billing → Invoices** |
| Mark attendance | **Home → Today's sessions**, or **Batch → Mark attendance** |
| See revenue & trends | **Home → KPI dashboard** |
| Give a parent/student a login | **Settings → Team → Invite** (role Parent/Student) |
| Edit academy name/logo | **Settings → Academy settings** (owner only) |

---

## The shortest possible path (if you just want to start today)

1. Sign up → name your academy → start the free trial.
2. **Settings → Centers:** add one center.
3. **Settings → Sports:** turn on one sport.
4. **Coaches → New coach:** add one coach.
5. **Batches → New batch:** create one class.
6. **Students → New student:** add a student (or import many).
7. Open the batch → **Enroll** the student.
8. **Home → Billing → Fees → New fee**, then **Assign fee to batch**.
9. **Home → Today's sessions:** mark attendance.

That's a fully running academy. Everything else (payments online, more staff,
parent logins, reports) you can layer on whenever you're ready.
