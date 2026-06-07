// ============================================================================
// PlayHub — create the per-role demo logins on a Supabase project.
//
// Run AFTER supabase/wipe.sql + supabase/seed.sql (the surgical wipe/seed,
// applied via the dashboard SQL editor or psql). The seed creates the demo
// academy, coaches and students with the deterministic UUIDs referenced below;
// this script creates the 9 auth logins and lets the handle_new_auth_user
// trigger wire them to those rows via user_metadata.
//
//   # from repo root, against the LINKED/remote project (always pass --wipe-all-users
//   # so stale logins orphaned by the wipe are cleared):
//   export $(grep -v '^#' .env | grep -E 'SUPABASE_(URL|SERVICE_ROLE_KEY)=' | xargs)
//   node apps/web-admin/scripts/create_demo_users.mjs --wipe-all-users
//
//   # against the LOCAL stack instead:
//   export $(supabase status -o env | grep -E 'API_URL|SERVICE_ROLE_KEY')
//   SUPABASE_URL="$API_URL" SUPABASE_SERVICE_ROLE_KEY="$SERVICE_ROLE_KEY" \
//     node apps/web-admin/scripts/create_demo_users.mjs --wipe-all-users
//
// Flags:
//   --wipe-all-users   delete EVERY existing auth user first (full clean slate).
//                      Without it, only the 9 demo emails are recreated.
//
// Needs only SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY (no DB password).
// Lives under apps/web-admin/ so it resolves that app's @supabase/supabase-js.
// ============================================================================

import { createClient } from "@supabase/supabase-js";

const SUPABASE_URL = process.env.SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!SUPABASE_URL || !SERVICE_KEY) {
  console.error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY in env.");
  process.exit(1);
}
const WIPE_ALL = process.argv.includes("--wipe-all-users");

// ---- Deterministic IDs (must match supabase/seed.sql) ----------------------
const ACADEMY = "a0000000-0000-4000-8000-000000000001";
const CENTER_A = "0ce00000-0000-4000-8000-00000000000a";
const CENTER_B = "0ce00000-0000-4000-8000-00000000000b";
const COACH_HEAD = "0c000000-0000-4000-8000-000000000001";
const COACH_1 = "0c000000-0000-4000-8000-000000000002";
const COACH_2 = "0c000000-0000-4000-8000-000000000003";
const STUDENT_1 = "05000000-0000-4000-8000-000000000001";
const STUDENT_2 = "05000000-0000-4000-8000-000000000002";

const PASSWORD = "Demo@1234"; // same for every demo login (change if you like)

// One login per role. `meta` is read by the handle_new_auth_user trigger:
// it sets role/academy_id/center_id and performs parent/coach/student linking.
const USERS = [
  { role: "super_admin", email: "superadmin@playhubdemo.in", first_name: "Platform", last_name: "Admin",
    meta: { role: "super_admin" } }, // no academy: super_admin is platform-level
  { role: "academy_owner", email: "owner@playhubdemo.in", first_name: "Owner", last_name: "Demo",
    meta: { role: "academy_owner", academy_id: ACADEMY } },
  { role: "academy_admin", email: "admin@playhubdemo.in", first_name: "Admin", last_name: "Demo",
    meta: { role: "academy_admin", academy_id: ACADEMY } },
  { role: "center_admin", email: "centeradmin@playhubdemo.in", first_name: "Center", last_name: "Admin",
    meta: { role: "center_admin", academy_id: ACADEMY, center_id: CENTER_A } },
  { role: "head_coach", email: "headcoach@playhubdemo.in", first_name: "Rahul", last_name: "Sharma",
    meta: { role: "head_coach", academy_id: ACADEMY, center_id: CENTER_A, link_coach_id: COACH_HEAD } },
  { role: "coach", email: "coach@playhubdemo.in", first_name: "Priya", last_name: "Nair",
    meta: { role: "coach", academy_id: ACADEMY, center_id: CENTER_A, link_coach_id: COACH_1 } },
  { role: "trainer", email: "trainer@playhubdemo.in", first_name: "Arjun", last_name: "Mehta",
    meta: { role: "trainer", academy_id: ACADEMY, center_id: CENTER_B, link_coach_id: COACH_2 } },
  { role: "parent", email: "parent@playhubdemo.in", first_name: "Sunita", last_name: "Gupta",
    meta: { role: "parent", academy_id: ACADEMY, link_to_student_id: STUDENT_1, link_relationship: "parent" } },
  { role: "student", email: "student@playhubdemo.in", first_name: "Aarav", last_name: "Gupta",
    meta: { role: "student", academy_id: ACADEMY, center_id: CENTER_A, link_student_login_id: STUDENT_1 } },
];

const admin = createClient(SUPABASE_URL, SERVICE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

async function listAllUsers() {
  const all = [];
  let page = 1;
  for (;;) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage: 1000 });
    if (error) throw error;
    all.push(...data.users.map((u) => ({ id: u.id, email: u.email ?? "" })));
    if (data.users.length < 1000) break;
    page++;
  }
  return all;
}

async function main() {
  console.log(`Target: ${SUPABASE_URL}`);
  const demoEmails = new Set(USERS.map((u) => u.email));
  const existing = await listAllUsers();

  // Delete prior logins so re-runs are clean (and a full wipe if requested).
  const toDelete = existing.filter((u) => (WIPE_ALL ? true : demoEmails.has(u.email)));
  if (toDelete.length) {
    console.log(`Deleting ${toDelete.length} existing auth user(s)${WIPE_ALL ? " (--wipe-all-users)" : ""}…`);
    for (const u of toDelete) {
      const { error } = await admin.auth.admin.deleteUser(u.id);
      if (error) console.warn(`  ! could not delete ${u.email}: ${error.message}`);
    }
  }

  // Create the 9 logins. The auth-user trigger creates the public.users row and
  // performs the metadata-driven linking.
  const created = [];
  for (const u of USERS) {
    const { data, error } = await admin.auth.admin.createUser({
      email: u.email,
      password: PASSWORD,
      email_confirm: true,
      // Privileged fields (role / academy_id / center_id / links) go in
      // app_metadata: handle_new_auth_user only trusts privileged fields from
      // app_metadata (service-role-only) or from invited users, never from
      // client-supplied user_metadata. See 20260607000100_harden_auth_trigger.
      user_metadata: { first_name: u.first_name, last_name: u.last_name },
      app_metadata: u.meta,
    });
    if (error || !data.user) {
      console.error(`  ! create ${u.email} failed: ${error?.message}`);
      process.exit(1);
    }
    created.push({ role: u.role, email: u.email, id: data.user.id });
    console.log(`  + ${u.role.padEnd(14)} ${u.email}`);
  }

  const idByRole = Object.fromEntries(created.map((c) => [c.role, c.id]));

  // The trigger sets must_change_password=true for invited (role+academy) users.
  // These are seeded demo logins — let them sign in directly with the password.
  {
    const ids = created.filter((c) => c.role !== "super_admin").map((c) => c.id);
    const { error } = await admin.from("users").update({ must_change_password: false }).in("id", ids);
    if (error) console.warn(`  ! clear must_change_password: ${error.message}`);
  }

  // Point the academy's owner_id at the academy_owner login.
  {
    const { error } = await admin.from("academies").update({ owner_id: idByRole["academy_owner"] }).eq("id", ACADEMY);
    if (error) console.warn(`  ! set academy owner_id: ${error.message}`);
  }

  // The trigger linked parent → student1. Add the parent's 2nd child (student2).
  {
    const { error } = await admin.from("parent_links").upsert(
      { academy_id: ACADEMY, parent_user_id: idByRole["parent"], student_id: STUDENT_2, relationship: "parent", is_primary: false },
      { onConflict: "parent_user_id,student_id", ignoreDuplicates: true },
    );
    if (error) console.warn(`  ! 2nd parent link: ${error.message}`);
  }

  console.log(`\n=== PlayHub demo logins (all password: ${PASSWORD}) ===`);
  for (const c of created) console.log(`  ${c.role.padEnd(14)} ${c.email}`);
  console.log("\nDone.");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
