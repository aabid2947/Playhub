import { config } from "dotenv";

// Load local dev env (Supabase URL + keys) for integration tests.
config({ path: ".env.local" });
config({ path: ".env" });
