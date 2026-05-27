import { randomUUID } from "node:crypto";
import { admin, saveCreds, PASSWORD, type Creds } from "./_admin";

/** Seeds one super-admin and one ordinary academy_owner for the E2E run. */
export default async function globalSetup() {
  const a = admin();
  const superEmail = `e2e-super-${randomUUID()}@example.invalid`;
  const ownerEmail = `e2e-owner-${randomUUID()}@example.invalid`;
  const creds: Creds = { superEmail, ownerEmail, userIds: [], academyIds: [] };

  const su = await a.auth.admin.createUser({
    email: superEmail,
    password: PASSWORD,
    email_confirm: true,
    user_metadata: { role: "super_admin" },
  });
  if (su.error || !su.data.user) throw su.error ?? new Error("super create failed");
  creds.userIds.push(su.data.user.id);

  const acad = await a.from("academies").insert({ name: `E2E ${Date.now()}` }).select("id").single();
  if (acad.error) throw acad.error;
  creds.academyIds.push(acad.data.id);

  const owner = await a.auth.admin.createUser({
    email: ownerEmail,
    password: PASSWORD,
    email_confirm: true,
    user_metadata: { role: "academy_owner" },
  });
  if (owner.error || !owner.data.user) throw owner.error ?? new Error("owner create failed");
  creds.userIds.push(owner.data.user.id);
  await a.from("users").update({ academy_id: acad.data.id }).eq("id", owner.data.user.id);

  saveCreds(creds);
}
