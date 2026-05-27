import { admin, loadCreds, clearCreds } from "./_admin";

export default async function globalTeardown() {
  try {
    const a = admin();
    const creds = loadCreds();
    for (const id of creds.academyIds) await a.from("academies").delete().eq("id", id);
    for (const id of creds.userIds)
      await a.auth.admin.deleteUser(id).catch(() => undefined);
  } catch {
    // nothing seeded / already cleaned
  } finally {
    clearCreds();
  }
}
