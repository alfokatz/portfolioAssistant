-- Borrado de cuenta: el trigger de limpieza no puede fallar por una tabla
-- opcional que no existe en el entorno.
--
-- En producción `public.waitlist` no existe (la lista de espera de la landing
-- no está en esta base) y `_account_purge_before_delete` cortaba el
-- `auth.admin.deleteUser` con 42P01: ninguna cuenta se podía borrar. Ahora
-- cada limpieza de una tabla que no es del núcleo de la app (waitlist,
-- subscription_sync_log, app_config) se saltea si la tabla no está. El resto
-- de la función queda igual que en 20261102130000_account_deletion.sql.

create or replace function public._account_purge_before_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := old.id::text;
  v_ids text[] := array[old.id::text, upper(old.id::text)];
  v_tier text;
begin
  -- a) Secretos de Vault: los apuntados por las tablas puntero y los
  --    huérfanos con el nombre del usuario (fallas viejas a mitad de un save).
  delete from vault.secrets
  where id in (
          select vault_secret_id from public.binance_keys where user_id = old.id
          union all
          select vault_secret_id from public.etoro_tokens where user_id = old.id
          union all
          select vault_secret_id from public.snaptrade_users where user_id = old.id
        )
     or name in ('binance_keys_' || v_uid, 'etoro_tokens_' || v_uid, 'snaptrade_user_' || v_uid);

  -- b) Log del webhook de RevenueCat.
  if to_regclass('public.subscription_sync_log') is not null then
    delete from public.subscription_sync_log where user_id = any (v_ids);
  end if;

  -- c) Flags de rollout: sacar el uuid de `users` y `allow_users`, en todas
  --    las claves.
  if to_regclass('public.app_config') is not null then
    update public.app_config
    set value = jsonb_set(value, '{users}', (value->'users') - v_ids), updated_at = now()
    where jsonb_typeof(value->'users') = 'array' and (value->'users') ?| v_ids;

    update public.app_config
    set value = jsonb_set(value, '{allow_users}', (value->'allow_users') - v_ids), updated_at = now()
    where jsonb_typeof(value->'allow_users') = 'array' and (value->'allow_users') ?| v_ids;
  end if;

  -- d) Waitlist de la landing, solo con un mail verificable (si la tabla
  --    existe en este entorno).
  if to_regclass('public.waitlist') is not null
     and old.email is not null
     and (old.email_confirmed_at is not null
          or coalesce(old.raw_app_meta_data->>'provider', 'email') <> 'email') then
    delete from public.waitlist where email = lower(old.email);
  end if;

  -- e) Contador. El cascade de user_subscriptions corre después de este
  --    trigger, así que el plan todavía se puede leer. Un plan con otro
  --    nombre cuenta como free: el contador nunca frena un borrado.
  select tier into v_tier from public.user_subscriptions where user_id = old.id;
  insert into public.account_deletions_daily (day, tier, deletions)
  values (
    (now() at time zone 'utc')::date,
    case when v_tier in ('free', 'premium', 'gold') then v_tier else 'free' end,
    1
  )
  on conflict (day, tier) do update
    set deletions = public.account_deletions_daily.deletions + 1;

  return old;
end;
$$;

revoke all on function public._account_purge_before_delete() from public, anon, authenticated;
