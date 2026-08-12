#!/usr/bin/env bash
# Create (or repair) a super_admin login on the hosted Supabase project.
#
#   bash scripts/create_super_admin.sh [email]
#
# Defaults to Ssadmin@sangeetasystems.com. Prompts for the password twice; the
# password is never echoed, never passed as an argv, and never written to disk.
#
# Needs only SUPABASE_URL + SUPABASE_SERVICE_KEY (the sbp_ Management PAT) from
# .env — the service_role JWT required by the Auth admin API is fetched at run
# time from the Management API, so no long-lived secret has to sit in .env.
#
# WHY app_metadata: handle_new_auth_user() only trusts privileged fields
# (role/academy_id/…) from raw_app_meta_data, or from user_metadata when
# invited_at is set (2026-06-07 hardening). A role passed in user_metadata on a
# plain createUser is IGNORED and the account silently lands as academy_owner.
#
# GOTCHA (observed 2026-07-31): app_metadata alone is NOT enough on current
# GoTrue. The admin createUser endpoint INSERTs auth.users first and merges
# app_metadata ~160ms later in a second statement, so the AFTER INSERT trigger
# sees raw_app_meta_data WITHOUT `role` and defaults the profile to
# academy_owner. We therefore force the role in public.users after creation
# rather than trusting the trigger. Same race applies to
# apps/web-admin/scripts/create_demo_users.mjs.
set -euo pipefail

EMAIL="${1:-Ssadmin@sangeetasystems.com}"
FIRST_NAME="Sangeeta"
LAST_NAME="Admin"

cd "$(dirname "$0")/.."
[ -f .env ] || { echo "ERROR: .env not found in $(pwd)" >&2; exit 1; }
set -a; . ./.env; set +a
: "${SUPABASE_URL:?missing in .env}"
: "${SUPABASE_SERVICE_KEY:?missing in .env}"

TMPRESP="$(mktemp)"
trap 'rm -f "$TMPRESP"' EXIT

REF="$(printf '%s' "$SUPABASE_URL" | sed -E 's#https://([^.]+)\..*#\1#')"
echo "Project : $REF"
echo "Email   : $EMAIL"
echo

# ---- password prompt (hidden, confirmed) ------------------------------------
read -rsp "Password for $EMAIL: " PW1; echo
read -rsp "Confirm password:    " PW2; echo
[ -n "$PW1" ]        || { echo "ERROR: password cannot be empty" >&2; exit 1; }
[ "$PW1" = "$PW2" ]  || { echo "ERROR: passwords do not match" >&2; exit 1; }
[ "${#PW1}" -ge 8 ]  || { echo "ERROR: use at least 8 characters" >&2; exit 1; }
unset PW2

# ---- fetch the service_role JWT (Auth admin API won't accept the sbp_ PAT) ---
echo "Fetching service_role key…"
SR="$(curl -fsS "https://api.supabase.com/v1/projects/$REF/api-keys" \
        -H "Authorization: Bearer $SUPABASE_SERVICE_KEY" \
      | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{
          const k=JSON.parse(s).find(x=>x.name==='service_role');
          if(!k){console.error('service_role key not returned');process.exit(1)}
          process.stdout.write(k.api_key);})")"
[ -n "$SR" ] || { echo "ERROR: could not obtain service_role key" >&2; exit 1; }

# ---- create the user --------------------------------------------------------
# Payload is built by node so the password is JSON-escaped correctly (quotes,
# backslashes, $ etc. survive intact) and stays out of the process list.
echo "Creating user…"
RESP="$(PW="$PW1" EMAIL="$EMAIL" FN="$FIRST_NAME" LN="$LAST_NAME" node -e "
  process.stdout.write(JSON.stringify({
    email: process.env.EMAIL,
    password: process.env.PW,
    email_confirm: true,
    app_metadata: { role: 'super_admin' },
    user_metadata: { first_name: process.env.FN, last_name: process.env.LN },
  }));" \
  | curl -sS -X POST "$SUPABASE_URL/auth/v1/admin/users" \
      -H "apikey: $SR" -H "Authorization: Bearer $SR" \
      -H "Content-Type: application/json" --data-binary @-)"
> "$TMPRESP" <<< "$RESP"

# Idempotent: if the login already exists, PATCH it (reset password + re-assert
# role) instead of failing. Makes re-runs a password reset, not a dead end.
if grep -qiE 'already (been )?registered|already exists' "$TMPRESP"; then
  echo "User already exists — updating password + role instead."
  UID_EXISTING="$(node -e "
      process.stdout.write(JSON.stringify({query:
        \"select id from public.users where lower(email) = lower('\" +
        process.argv[1].replace(/'/g,\"''\") + \"');\"}));" "$EMAIL" \
    | curl -sS -X POST "https://api.supabase.com/v1/projects/$REF/database/query" \
        -H "Authorization: Bearer $SUPABASE_SERVICE_KEY" \
        -H "Content-Type: application/json" --data-binary @- \
    | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{
        const r=JSON.parse(s); if(!r[0]){console.error('no profile row for that email');process.exit(1)}
        process.stdout.write(r[0].id);})")"
  [ -n "$UID_EXISTING" ] || { echo "ERROR: could not resolve existing user id" >&2; exit 1; }

  RESP="$(PW="$PW1" node -e "
      process.stdout.write(JSON.stringify({
        password: process.env.PW,
        email_confirm: true,
        app_metadata: { role: 'super_admin' },
      }));" \
    | curl -sS -X PUT "$SUPABASE_URL/auth/v1/admin/users/$UID_EXISTING" \
        -H "apikey: $SR" -H "Authorization: Bearer $SR" \
        -H "Content-Type: application/json" --data-binary @-)"
  > "$TMPRESP" <<< "$RESP"
fi
unset PW1

node -e "
let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{
  let j; try { j = JSON.parse(s) } catch (e) { console.error('Unparseable response: '+s); process.exit(1) }
  if (j.id) { console.log('OK  auth user ready: '+j.id+'  ('+j.email+')'); process.exit(0) }
  console.error('FAILED: '+(j.msg||j.message||j.error_description||JSON.stringify(j)));
  process.exit(1);})" < "$TMPRESP"

# ---- force the role, then verify --------------------------------------------
# The trigger cannot be relied on (see GOTCHA above), so set the role
# explicitly. Idempotent: re-running on an already-correct row is a no-op.
echo "Forcing role=super_admin on public.users…"
node -e "
  const email = process.argv[1].replace(/'/g, \"''\");
  process.stdout.write(JSON.stringify({query:
    \"update public.users set role = 'super_admin', academy_id = null, \"+
    \"center_id = null, must_change_password = false \"+
    \"where lower(email) = lower('\" + email + \"'); \"+
    \"select p.id, p.email, p.role, p.academy_id, p.is_active, p.must_change_password, \"+
    \"(select count(*) from auth.identities i where i.user_id = p.id) as identities \"+
    \"from public.users p where lower(p.email) = lower('\" + email + \"');\"}));
  " "$EMAIL" \
| curl -sS -X POST "https://api.supabase.com/v1/projects/$REF/database/query" \
    -H "Authorization: Bearer $SUPABASE_SERVICE_KEY" \
    -H "Content-Type: application/json" --data-binary @- \
| node -e "
let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{
  const r=JSON.parse(s)[0];
  if(!r){console.error('FAILED: no public.users row - the auth trigger did not fire');process.exit(1)}
  console.log(JSON.stringify(r,null,2));
  if(r.role!=='super_admin'){
    console.error('');
    console.error('WARNING: role is '+r.role+', NOT super_admin.');
    console.error('The role was not read from app_metadata - do not use this account.');
    process.exit(1);
  }
  console.log('');
  console.log('SUCCESS - super_admin ready. Sign in with the password you just set.');})"
