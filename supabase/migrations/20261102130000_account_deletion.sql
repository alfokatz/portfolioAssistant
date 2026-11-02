-- Borrado de cuenta (docs/superpowers/specs/2026-11-02-borrado-de-cuenta.md §3.2).
--
-- La edge function `delete-account` desconecta los brókers, borra el cliente
-- en RevenueCat y después borra `auth.users`. Casi todo lo del usuario se va
-- por `on delete cascade`. Lo que el cascade no alcanza lo limpia el trigger
-- `before delete on auth.users` de abajo, en la misma transacción que el
-- borrado (también si soporte borra a mano desde el dashboard):
--   - los secretos de Vault de Binance, eToro y SnapTrade (las tablas puntero
--     caen por cascade, `vault.secrets` no);
--   - `subscription_sync_log` (user_id text, sin FK);
--   - el uuid en los arrays `users` / `allow_users` de `app_config`;
--   - la fila de `waitlist` con su mail, solo si el mail es verificable
--     (confirmado u OAuth): si no, cualquiera podría borrar el registro de
--     otra persona creando una cuenta con su mail (compliance §6.1).
-- Además cuenta los borrados por día y plan, sin user_id.
--
-- El test de "no queda nada" es supabase/tests/account_deletion_db_test.sql.
-- Antes del db push: correr la consulta de auditoría de
-- docs/runbooks/account-deletion.md en producción.

-- ---------------------------------------------------------------------------
-- 1. Contador agregado (no es dato personal). Solo service role.
-- ---------------------------------------------------------------------------

create table if not exists public.account_deletions_daily (
  day date not null,
  tier text not null check (tier in ('free', 'premium', 'gold')),
  deletions int not null default 0,
  primary key (day, tier)
);

alter table public.account_deletions_daily enable row level security;

revoke all on public.account_deletions_daily from public, anon, authenticated;
grant all on public.account_deletions_daily to service_role;

-- ---------------------------------------------------------------------------
-- 2. Limpieza de lo que el cascade no alcanza + contador.
-- ---------------------------------------------------------------------------

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
  delete from public.subscription_sync_log where user_id = any (v_ids);

  -- c) Flags de rollout: sacar el uuid de `users` y `allow_users`, en todas
  --    las claves.
  update public.app_config
  set value = jsonb_set(value, '{users}', (value->'users') - v_ids), updated_at = now()
  where jsonb_typeof(value->'users') = 'array' and (value->'users') ?| v_ids;

  update public.app_config
  set value = jsonb_set(value, '{allow_users}', (value->'allow_users') - v_ids), updated_at = now()
  where jsonb_typeof(value->'allow_users') = 'array' and (value->'allow_users') ?| v_ids;

  -- d) Waitlist de la landing, solo con un mail verificable.
  if old.email is not null
     and (old.email_confirmed_at is not null
          or coalesce(old.raw_app_meta_data->>'provider', 'email') <> 'email') then
    delete from public.waitlist where email = lower(old.email);
  end if;

  -- e) Contador. El cascade de user_subscriptions corre después de este
  --    trigger, así que el plan todavía se puede leer.
  select tier into v_tier from public.user_subscriptions where user_id = old.id;
  insert into public.account_deletions_daily (day, tier, deletions)
  values ((now() at time zone 'utc')::date, coalesce(v_tier, 'free'), 1)
  on conflict (day, tier) do update
    set deletions = public.account_deletions_daily.deletions + 1;

  return old;
end;
$$;

revoke all on function public._account_purge_before_delete() from public, anon, authenticated;

drop trigger if exists account_purge_before_delete on auth.users;
create trigger account_purge_before_delete
  before delete on auth.users
  for each row execute function public._account_purge_before_delete();

-- ---------------------------------------------------------------------------
-- 3. Cascade asegurado en positions / closed_positions.
--
-- En el remoto se crearon antes de la CLI y su FK es desconocida: sin FK el
-- cascade no las borra; con una FK sin cascade, deleteUser falla. Se borra
-- toda FK user_id → auth.users que no sea cascade y, si no queda ninguna, se
-- agrega una `not valid` (no falla con huérfanos viejos; el cascade igual
-- aplica a los borrados nuevos).
-- ---------------------------------------------------------------------------

do $$
declare
  v_table text;
  v_attnum smallint;
  v_type text;
  v_con record;
begin
  foreach v_table in array array['positions', 'closed_positions'] loop
    if to_regclass('public.' || v_table) is null then
      continue;
    end if;

    select a.attnum, format_type(a.atttypid, a.atttypmod) into v_attnum, v_type
    from pg_attribute a
    where a.attrelid = ('public.' || v_table)::regclass and a.attname = 'user_id' and not a.attisdropped;
    if v_attnum is null or v_type <> 'uuid' then
      raise exception '%.user_id no existe o no es uuid (%): correr la auditoría de docs/runbooks/account-deletion.md',
        v_table, coalesce(v_type, 'sin columna');
    end if;

    for v_con in
      select c.conname
      from pg_constraint c
      where c.conrelid = ('public.' || v_table)::regclass
        and c.contype = 'f'
        and c.confrelid = 'auth.users'::regclass
        and c.conkey = array[v_attnum]
        and c.confdeltype <> 'c'
    loop
      execute format('alter table public.%I drop constraint %I', v_table, v_con.conname);
    end loop;

    if not exists (
      select 1
      from pg_constraint c
      where c.conrelid = ('public.' || v_table)::regclass
        and c.contype = 'f'
        and c.confrelid = 'auth.users'::regclass
        and c.conkey = array[v_attnum]
        and c.confdeltype = 'c'
    ) then
      execute format(
        'alter table public.%I add constraint %I foreign key (user_id) references auth.users (id) on delete cascade not valid',
        v_table, v_table || '_user_id_cascade_fkey'
      );
    end if;
  end loop;
end $$;
