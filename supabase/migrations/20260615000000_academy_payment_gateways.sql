-- ============================================================================
-- Per-academy payment gateway credentials ("bring your own gateway").
--
-- An academy owner can configure their OWN Razorpay / Paytm merchant
-- credentials; payments in that academy then route through their account
-- (with a fallback to the platform-wide keys when nothing is configured —
-- see supabase/functions/_shared/payment_gateway.ts).
--
-- SECURITY MODEL (invariant #4 — secrets never reach a client):
--   • The API secret + webhook secret are stored in **Supabase Vault**
--     (encrypted at rest), NOT in this table. The table holds only the vault
--     reference (uuid) + the non-secret public identifier (Razorpay key_id /
--     Paytm MID) + flags.
--   • Secrets are **write-only** from any client's perspective. The owner sets
--     them via the SECURITY DEFINER RPC `set_payment_gateway`; no client read
--     path (table RLS, the status view, or the RPC) ever returns a secret.
--   • Only edge functions (service_role) can decrypt, via
--     `get_payment_gateway_credentials`, whose EXECUTE is revoked from
--     anon/authenticated and granted to service_role only.
--   • Clients read the `academy_payment_gateway_status` view, which exposes
--     "configured?" booleans — never the secret or even its vault id.
--
-- Only the academy **owner** manages these (owner-exclusive, like academy
-- settings). RLS is the real gate; the Flutter `Capabilities` mirror only hides
-- the entry point.
-- ============================================================================

create table public.academy_payment_gateways (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies(id) on delete cascade,

  -- Which gateway this row configures.
  provider text not null check (provider in ('razorpay', 'paytm')),

  -- Public, non-secret identifier (Razorpay key_id `rzp_live_…` / Paytm MID).
  -- Safe to return to clients — it's handed to the checkout SDK anyway.
  key_id text,

  -- Vault references for the secrets. NULL = not yet configured. These are
  -- harmless pointers (useless without vault decrypt rights) but are still
  -- excluded from the client-facing status view.
  secret_vault_id uuid,
  webhook_secret_vault_id uuid,

  -- Non-secret provider-specific config. Razorpay uses none. Paytm uses
  -- {"website": "...", "environment": "stage"|"prod"} (the website name and
  -- which Paytm gateway host to hit). Safe to expose to the owner client.
  config jsonb not null default '{}'::jsonb,

  -- Owner toggle: is this the gateway used to charge in this academy? At most
  -- one provider may be enabled per academy (enforced by `set_payment_gateway`).
  is_enabled boolean not null default false,

  -- When the API secret was last written (drives the "configured" UI hint).
  secret_set_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (academy_id, provider)
);

create trigger trg_academy_payment_gateways_updated
  before update on public.academy_payment_gateways
  for each row execute function public.set_updated_at();

alter table public.academy_payment_gateways enable row level security;

-- Read: the academy OWNER (their own academy) + super_admin. Note the read
-- still exposes `secret_vault_id`/`webhook_secret_vault_id` at the table level,
-- so clients must read the status VIEW below, not the table directly.
create policy academy_payment_gateways_owner_read
  on public.academy_payment_gateways
  for select using (
    public.is_super_admin()
    or (
      academy_id = public.current_user_academy_id()
      and public.has_role('academy_owner')
    )
  );

-- Direct writes (DML) are reserved for super_admin (cleanup/troubleshooting).
-- Owners NEVER write this table directly — they go through the SECURITY DEFINER
-- `set_payment_gateway` / `clear_payment_gateway` RPCs, which validate ownership
-- and keep the secret out of the row. This is intentional: it centralises the
-- secret-handling path so no owner-facing policy can ever expose a secret.
create policy academy_payment_gateways_super_write
  on public.academy_payment_gateways
  for all using (public.is_super_admin())
  with check (public.is_super_admin());

-- ----------------------------------------------------------------------------
-- Client-facing status view — safe columns only (no secrets, no vault ids).
-- `security_invoker` so the base-table RLS above still applies per caller.
-- ----------------------------------------------------------------------------
create view public.academy_payment_gateway_status
  with (security_invoker = true)
as
  select
    academy_id,
    provider,
    key_id,
    is_enabled,
    config,
    (secret_vault_id is not null)         as secret_configured,
    (webhook_secret_vault_id is not null) as webhook_configured,
    secret_set_at,
    updated_at
  from public.academy_payment_gateways;

grant select on public.academy_payment_gateway_status to authenticated;

-- ============================================================================
-- RPC: set_payment_gateway — owner writes credentials (secret → Vault).
--   p_api_secret / p_webhook_secret: pass NULL to leave the existing secret
--   unchanged (so the owner can toggle `is_enabled` or update key_id without
--   re-typing secrets). Pass a non-empty string to set/replace.
-- ============================================================================
create or replace function public.set_payment_gateway(
  p_provider text,
  p_key_id text,
  p_api_secret text default null,
  p_webhook_secret text default null,
  p_enabled boolean default false,
  p_config jsonb default null
)
returns void
language plpgsql
security definer
set search_path = public, vault
as $$
declare
  v_academy uuid := public.current_user_academy_id();
  v_role public.user_role := public.current_user_role();
  v_row public.academy_payment_gateways%rowtype;
  v_secret_id uuid;
  v_webhook_id uuid;
  v_name text;
  v_existing_id uuid;
  v_final_key_id text;
  v_final_config jsonb;
begin
  -- Owner-only, own academy only.
  if v_role is distinct from 'academy_owner' or v_academy is null then
    raise exception 'only the academy owner can manage payment gateways'
      using errcode = '42501';
  end if;
  if p_provider not in ('razorpay', 'paytm') then
    raise exception 'unsupported provider: %', p_provider using errcode = '22023';
  end if;

  select * into v_row
    from public.academy_payment_gateways
    where academy_id = v_academy and provider = p_provider;

  v_secret_id := v_row.secret_vault_id;
  v_webhook_id := v_row.webhook_secret_vault_id;

  -- API secret → Vault (create or update by stable name).
  if p_api_secret is not null and length(trim(p_api_secret)) > 0 then
    if v_secret_id is not null then
      perform vault.update_secret(v_secret_id, p_api_secret);
    else
      v_name := 'apg:' || v_academy::text || ':' || p_provider || ':api';
      select id into v_existing_id from vault.secrets where name = v_name;
      if v_existing_id is not null then
        perform vault.update_secret(v_existing_id, p_api_secret);
        v_secret_id := v_existing_id;
      else
        v_secret_id := vault.create_secret(
          p_api_secret, v_name, 'Payment API secret for academy ' || v_academy::text
        );
      end if;
    end if;
  end if;

  -- Webhook signing secret → Vault.
  if p_webhook_secret is not null and length(trim(p_webhook_secret)) > 0 then
    if v_webhook_id is not null then
      perform vault.update_secret(v_webhook_id, p_webhook_secret);
    else
      v_name := 'apg:' || v_academy::text || ':' || p_provider || ':webhook';
      select id into v_existing_id from vault.secrets where name = v_name;
      if v_existing_id is not null then
        perform vault.update_secret(v_existing_id, p_webhook_secret);
        v_webhook_id := v_existing_id;
      else
        v_webhook_id := vault.create_secret(
          p_webhook_secret, v_name, 'Payment webhook secret for academy ' || v_academy::text
        );
      end if;
    end if;
  end if;

  v_final_key_id := coalesce(nullif(trim(coalesce(p_key_id, '')), ''), v_row.key_id);
  -- Merge config: null = unchanged; otherwise shallow-merge over the existing.
  v_final_config := coalesce(v_row.config, '{}'::jsonb) || coalesce(p_config, '{}'::jsonb);

  -- Refuse to enable a half-configured gateway — that would break checkout.
  if p_enabled and (v_final_key_id is null or v_secret_id is null) then
    raise exception 'cannot enable %: key id and API secret are both required',
      p_provider using errcode = '22023';
  end if;
  -- Paytm additionally needs a website name + environment to route correctly.
  if p_enabled and p_provider = 'paytm' and (
       coalesce(v_final_config->>'website', '') = ''
       or coalesce(v_final_config->>'environment', '') not in ('stage', 'prod')
     ) then
    raise exception 'cannot enable paytm: website and environment (stage|prod) are required'
      using errcode = '22023';
  end if;

  insert into public.academy_payment_gateways as g (
    academy_id, provider, key_id, secret_vault_id, webhook_secret_vault_id,
    is_enabled, secret_set_at, config
  )
  values (
    v_academy, p_provider, v_final_key_id, v_secret_id, v_webhook_id,
    p_enabled,
    case when p_api_secret is not null and length(trim(p_api_secret)) > 0
         then now() else v_row.secret_set_at end,
    v_final_config
  )
  on conflict (academy_id, provider) do update set
    key_id = excluded.key_id,
    secret_vault_id = excluded.secret_vault_id,
    webhook_secret_vault_id = excluded.webhook_secret_vault_id,
    is_enabled = excluded.is_enabled,
    secret_set_at = excluded.secret_set_at,
    config = excluded.config,
    updated_at = now();

  -- At most one enabled gateway per academy.
  if p_enabled then
    update public.academy_payment_gateways
      set is_enabled = false, updated_at = now()
      where academy_id = v_academy and provider <> p_provider and is_enabled;
  end if;
end;
$$;

revoke execute on function
  public.set_payment_gateway(text, text, text, text, boolean, jsonb) from public, anon;
grant execute on function
  public.set_payment_gateway(text, text, text, text, boolean, jsonb) to authenticated;

-- ============================================================================
-- RPC: clear_payment_gateway — owner removes a gateway + its vault secrets.
-- ============================================================================
create or replace function public.clear_payment_gateway(p_provider text)
returns void
language plpgsql
security definer
set search_path = public, vault
as $$
declare
  v_academy uuid := public.current_user_academy_id();
  v_role public.user_role := public.current_user_role();
  v_row public.academy_payment_gateways%rowtype;
begin
  if v_role is distinct from 'academy_owner' or v_academy is null then
    raise exception 'only the academy owner can manage payment gateways'
      using errcode = '42501';
  end if;

  select * into v_row
    from public.academy_payment_gateways
    where academy_id = v_academy and provider = p_provider;
  if not found then
    return;
  end if;

  delete from public.academy_payment_gateways where id = v_row.id;

  if v_row.secret_vault_id is not null then
    delete from vault.secrets where id = v_row.secret_vault_id;
  end if;
  if v_row.webhook_secret_vault_id is not null then
    delete from vault.secrets where id = v_row.webhook_secret_vault_id;
  end if;
end;
$$;

revoke execute on function public.clear_payment_gateway(text) from public, anon;
grant execute on function public.clear_payment_gateway(text) to authenticated;

-- ============================================================================
-- RPC: get_payment_gateway_credentials — server-only credential read.
--   Returns DECRYPTED secrets, so EXECUTE is restricted to service_role; edge
--   functions call this with the service-role client. Never exposed to clients.
-- ============================================================================
create or replace function public.get_payment_gateway_credentials(
  p_academy_id uuid,
  p_provider text
)
returns table (
  key_id text,
  api_secret text,
  webhook_secret text,
  is_enabled boolean,
  config jsonb
)
language plpgsql
security definer
set search_path = public, vault
as $$
declare
  v_row public.academy_payment_gateways%rowtype;
begin
  select * into v_row
    from public.academy_payment_gateways
    where academy_id = p_academy_id and provider = p_provider;
  if not found then
    return;
  end if;

  key_id := v_row.key_id;
  is_enabled := v_row.is_enabled;
  config := v_row.config;
  if v_row.secret_vault_id is not null then
    select decrypted_secret into api_secret
      from vault.decrypted_secrets where id = v_row.secret_vault_id;
  end if;
  if v_row.webhook_secret_vault_id is not null then
    select decrypted_secret into webhook_secret
      from vault.decrypted_secrets where id = v_row.webhook_secret_vault_id;
  end if;
  return next;
end;
$$;

revoke execute on function
  public.get_payment_gateway_credentials(uuid, text) from public, anon, authenticated;
grant execute on function
  public.get_payment_gateway_credentials(uuid, text) to service_role;
