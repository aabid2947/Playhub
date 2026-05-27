import { createClient } from "@supabase/supabase-js";
import { writeFileSync, readFileSync, existsSync, unlinkSync } from "node:fs";
import { join } from "node:path";

const URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SERVICE = process.env.SUPABASE_SERVICE_ROLE_KEY!;
export const CREDS_FILE = join(process.cwd(), "tests/e2e/.creds.json");
export const PASSWORD = "Test-Passw0rd!";

export type Creds = {
  superEmail: string;
  ownerEmail: string;
  userIds: string[];
  academyIds: string[];
};

export function admin() {
  return createClient(URL, SERVICE, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

export function saveCreds(c: Creds) {
  writeFileSync(CREDS_FILE, JSON.stringify(c, null, 2));
}

export function loadCreds(): Creds {
  return JSON.parse(readFileSync(CREDS_FILE, "utf8")) as Creds;
}

export function clearCreds() {
  if (existsSync(CREDS_FILE)) unlinkSync(CREDS_FILE);
}
