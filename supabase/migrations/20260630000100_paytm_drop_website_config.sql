-- Paytm `websiteName` is no longer a per-academy setting — it's hardcoded in
-- the edge layer (_shared/paytm.ts: 'WEBSTAGING' for stage, 'DEFAULT' for prod)
-- so owners can't mis-enter it (a wrong website was causing "System Error" on
-- initiateTransaction). This recreates set_payment_gateway with the enable-time
-- validation relaxed to require only `environment` (stage|prod), not `website`.
--
-- Existing rows that still carry config.website are harmless — resolvePaytmCreds
-- ignores it and derives the website from environment. Append-only per
-- invariant #5; the body is identical to 20260615000000 except the Paytm check.

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
  -- Paytm needs an environment to route to the right host; the websiteName is
  -- derived from it in the edge layer, so it is NOT required here anymore.
  if p_enabled and p_provider = 'paytm'
     and coalesce(v_final_config->>'environment', '') not in ('stage', 'prod') then
    raise exception 'cannot enable paytm: environment (stage|prod) is required'
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
