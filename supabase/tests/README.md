# Supabase RLS tests

These are SQL regression tests that exercise tenant-isolation under RLS.
Each test runs in a transaction that **rolls back at the end**, so they
leave no trace.

## Run locally

```bash
# Bring up local Supabase if not already running
supabase start

# Apply migrations on a clean local DB
supabase db reset

# Get the local DB URL
DB_URL=$(supabase status -o env | awk -F= '/^DB_URL=/{print $2}' | tr -d '"')

# Run a test file
psql "$DB_URL" -f supabase/tests/rls_tenancy.sql
```

A passing run prints `PASS:` notices and ends with
`All RLS isolation tests passed.`. Any failure raises a Postgres
exception and aborts the transaction — the script will not silently
skip a broken policy.

## Run against staging

```bash
psql "$DATABASE_URL" -f supabase/tests/rls_tenancy.sql
```

Safe to run on shared environments because the whole script is wrapped
in `begin … rollback`. The fixture rows it creates are never committed.

## What's covered

- Cross-tenant read isolation on `students`
- Cross-tenant read isolation on `centers`
- Cross-tenant insert blocked
- Cross-tenant `public.users` row read blocked

## Future tests

- Coach + batch + enrollment table read/write
- Storage bucket policies (`avatars`, `student_documents`)
- Role-based permission gates (e.g. coach vs admin write)
- `bootstrap_owner_academy` idempotency
