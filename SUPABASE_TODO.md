# Supabase / Firebase / DNS to-do

Config tasks that need dashboard access (Supabase, Firebase, and the DNS host).
**No code changes here** — all of this is settings, secrets, one function deploy,
and two DNS records.

Context: the app's Android package was renamed `ai.hammad.playhub` → `ai.playhub`
on 2026-07-29, and the Android Firebase config was swapped to a **new Firebase
project `playhub-live`** (the old one was `playhub-348c7`). Items 1–4 below are
fallout from that. Item 5 is older. Item 6 is just a check.

Please tick items off and note anything that was *already* done — a couple of
these we couldn't verify from the code side.

---

## 1. Replace the FCM service-account secret — **push notifications are broken until this is done**

The app now registers device tokens against Firebase project `playhub-live`, but
the edge functions still authenticate as the **old** project. FCM tokens are
project-scoped, so every push currently fails.

- [ ] In **Firebase console → project `playhub-live` → Project settings → Service
      accounts → Generate new private key**. Download the JSON.
- [ ] Set it as a Supabase edge-function secret named **`FCM_SERVICE_ACCOUNT`**
      (the *entire* JSON file contents, as one value):
      Supabase Dashboard → Edge Functions → Secrets, or
      `supabase secrets set FCM_SERVICE_ACCOUNT="$(cat service-account.json)"`
- [ ] **Please confirm what the secret was set to before.** If it didn't exist at
      all, then pushes were already silently failing before the rename — good to
      know either way.

*Verify:* trigger any notification (e.g. post an announcement) and check the
edge-function logs. `FCM_SERVICE_ACCOUNT not configured` = not set;
a 404 / `UNREGISTERED` per token = still the wrong project.

---

## 2. Redeploy `send-announcement`

The shared email helper was fixed (spam-related headers + two bugs). Edge
functions bundle their own copy of `_shared/`, so the fix isn't live until this
one function is redeployed. It's the only function that sends email.

- [x] **DONE 2026-07-31.** `npx supabase functions deploy send-announcement`
      — deployed to project `hrawgduftgslwsdgzliy`; the upload included
      `_shared/email.ts`, so the header/spam fixes are live.

*Verify:* send a test announcement with email enabled; the received mail should
now have a `Date` and `Message-ID` header (check "Show original" in Gmail).

---

## 3. Add the new deep-link URL to the Auth allow-list

Password-reset emails redirect to a custom URL scheme, which changed with the
package rename. If it's not allow-listed, Supabase silently falls back to the
Site URL — the email still arrives, the link just opens a browser instead of the
app. That's easy to misread as an app bug.

- [ ] Supabase Dashboard → **Authentication → URL Configuration → Redirect URLs**
      → add:
      ```
      ai.playhub://login-callback
      ```
- [ ] You can remove the old `ai.hammad.playhub://login-callback` if it's there.
      **Please say whether it was there** — if it never was, password resets were
      already broken before the rename.

*Note:* invite emails do **not** use this scheme (they use the Site URL), so only
password reset / "send reset link" is affected.

---

## 4. Register the iOS app in `playhub-live`

`ios/Runner/GoogleService-Info.plist` in the repo has the **right bundle id
(`ai.playhub`) but the wrong Firebase project** — it was hand-edited, so it still
carries `PROJECT_ID: playhub-348c7` and that project's sender id and API key. iOS
push won't work until it's replaced with a real download from `playhub-live`.

- [ ] Firebase console → project `playhub-live` → **Add app → iOS**, bundle id:
      ```
      ai.playhub
      ```
- [ ] Download `GoogleService-Info.plist` and send it over — a developer needs to
      commit it to `apps/mobile/ios/Runner/`.

*(Skip if iOS isn't shipping yet — Android is unaffected by this one.)*

---

## 5. Email deliverability: SPF + DKIM DNS records

This is the **main reason mail lands in spam**, and it's older than the rename.
Mail is sent via Gmail SMTP but the `From:` address is on our own domain, so
SPF/DKIM authenticate Google's domain while the `From:` claims ours — DMARC
doesn't align, and receivers junk it. Code-side fixes are already done; this part
is DNS-only.

Whoever manages DNS for the sending domain (the domain in the `SMTP_FROM`
secret):

- [ ] **SPF** — add or merge into the existing TXT record at the root:
      ```
      v=spf1 include:_spf.google.com ~all
      ```
      (One SPF record per domain — merge, don't add a second.)
- [ ] **DKIM** — Google Admin console → Apps → Google Workspace → Gmail →
      **Authenticate email** → generate, then add the `google._domainkey` TXT
      record it gives you, then click **Start authentication**.
- [ ] **DMARC** *(after the two above pass)* — TXT at `_dmarc`:
      ```
      v=DMARC1; p=none; rua=mailto:<an address you monitor>
      ```
      Start at `p=none` to collect reports, tighten to `quarantine` later.

*Verify:* send a mail to a Gmail address, open **Show original** — SPF, DKIM and
DMARC should all read **PASS**.

---

## 6. Check which migrations are actually applied

Two migrations were flagged "owed: apply" in earlier work and we can't tell from
the repo whether they ever landed on the hosted DB.

- [ ] Confirm these are present in the hosted DB's migration history:
      - `20260630000000_fee_weekly_frequency`
      - `20260630000100_paytm_drop_website_config`
- [ ] If `20260630000000` is **missing**, apply it and redeploy
      `recur-invoice-generation` — one-time fees don't generate an invoice (so no
      Pay button, ever) and the `weekly` fee frequency doesn't work without it.

*How to check:* `supabase migration list --project-ref <ref>`, or query
`select version from supabase_migrations.schema_migrations order by version desc;`

---

## Priority

| Priority | Items | Impact if skipped |
|---|---|---|
| **P0 — broken now** | 1 | No push notifications at all |
| **P1** | 2, 3 | Email fixes not live; password-reset links don't open the app |
| **P2** | 5, 6 | Mail keeps landing in spam; possible unbilled one-time fees |
| **P3** | 4 | iOS push only (skip if iOS isn't shipping) |

Questions worth answering back to the dev side: whether `FCM_SERVICE_ACCOUNT`
already existed (item 1), whether the old redirect URL was allow-listed (item 3),
and the result of item 6.
