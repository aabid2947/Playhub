-- ============================================================================
-- DEV-ONLY / TESTING HACK - DO NOT APPLY TO PRODUCTION
--
-- Makes every INVITED auth user immediately loginable with a fixed password
-- (Test@1234) instead of forcing the email invite-accept then set-password
-- flow. Gated on invited_at, so real self-signups (who set their own password)
-- are untouched. Also pre-confirms the email so sign-in is not blocked.
--
-- SECURITY: this is a known password on ALL invited accounts. It is a hole if
-- it ever reaches prod. Remove it with the DROP block at the bottom before any
-- real use. Pair it with fix_auth_trigger.sql - otherwise invited users still
-- land as academy_owner/NULL (wrong role) and logging in is pointless.
--
-- Run in the Supabase dashboard SQL editor (as postgres). Requires pgcrypto
-- (bcrypt); Supabase ships it in the extensions schema.
-- ============================================================================

create or replace function public.dev_autopassword_on_invite()
returns trigger
language plpgsql
security definer
set search_path = auth, extensions, public
as $$
begin
  -- Only invited users, and only when GoTrue hasn't already set a password.
  if new.invited_at is not null
     and (new.encrypted_password is null or new.encrypted_password = '') then
    new.encrypted_password := crypt('Test@1234', gen_salt('bf'));
    -- Pre-confirm so they can sign in without clicking the invite link.
    new.email_confirmed_at := coalesce(new.email_confirmed_at, now());
  end if;
  return new;
end;
$$;

-- BEFORE INSERT so we can set the columns on NEW directly (fires before the
-- existing AFTER INSERT trg_on_auth_user_created that builds public.users).
drop trigger if exists trg_dev_autopassword on auth.users;
create trigger trg_dev_autopassword
  before insert on auth.users
  for each row execute function public.dev_autopassword_on_invite();

-- ---- TO REMOVE LATER (run this to fully undo the hack) -----------------------
-- drop trigger if exists trg_dev_autopassword on auth.users;
-- drop function if exists public.dev_autopassword_on_invite();
