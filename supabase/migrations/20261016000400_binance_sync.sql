-- Conexión de solo lectura con Binance (F6 de
-- docs/superpowers/plans/2026-10-16-porty-siguiente-nivel.md).
--
-- - El usuario crea una clave de API de SOLO LECTURA en Binance y la pega en
--   la app. La edge function `binance-sync` verifica los permisos de la
--   clave (rechaza cualquiera que pueda operar, retirar o transferir) y la
--   guarda cifrada en Supabase Vault. Nunca vuelve a la app.
-- - Los saldos se importan como posiciones `source = 'binance'`, de solo
--   lectura para la app: el trigger de eToro pasa a cubrir todo lo que no
--   es manual.
-- - Cada sincronización es la foto completa de los saldos y se aplica
--   entera o no se aplica (`binance_apply_sync`).

-- ---------------------------------------------------------------------------
-- Origen de las posiciones
-- ---------------------------------------------------------------------------

alter table public.positions drop constraint if exists positions_source_check;
alter table public.positions
  add constraint positions_source_check check (source in ('manual', 'etoro', 'binance'));

alter table public.closed_positions drop constraint if exists closed_positions_source_check;
alter table public.closed_positions
  add constraint closed_positions_source_check check (source in ('manual', 'etoro', 'binance'));

-- Solo lectura para la app: todo lo importado de un bróker. Mismo nombre de
-- función (los triggers de eToro ya la usan); el error de eToro no cambia.
create or replace function public._etoro_rows_read_only()
returns trigger
language plpgsql
as $$
begin
  if current_user in ('anon', 'authenticated') then
    if (tg_op in ('UPDATE', 'DELETE') and old.source <> 'manual')
       or (tg_op in ('INSERT', 'UPDATE') and new.source <> 'manual') then
      raise exception '%',
        case when coalesce(new.source, old.source) = 'etoro' or old.source = 'etoro'
             then 'etoro_rows_are_read_only' else 'broker_rows_are_read_only' end
        using errcode = '42501',
              hint = 'Las posiciones importadas de un bróker se actualizan solas.';
    end if;
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Estado de la conexión (lo lee la app)
-- ---------------------------------------------------------------------------

create table if not exists public.binance_connections (
  user_id uuid primary key references auth.users (id) on delete cascade,
  status text not null default 'connected'
    check (status in ('connected', 'reconnect_required', 'disconnected')),
  -- Los últimos 4 caracteres de la clave, para que el usuario la reconozca.
  api_key_hint text,
  connected_at timestamptz,
  last_sync_at timestamptz,
  last_sync_status text check (last_sync_status in ('ok', 'error')),
  last_error_type text,
  -- {imported, notImported: [{asset, reason}], estimatedCost: [ticker]}.
  last_result jsonb,
  -- Lease: una sola sincronización a la vez por usuario.
  sync_lock_until timestamptz,
  updated_at timestamptz not null default now()
);

alter table public.binance_connections enable row level security;

drop policy if exists "Users read own binance connection" on public.binance_connections;
create policy "Users read own binance connection" on public.binance_connections
  for select using (auth.uid() = user_id);

-- Puntero al secreto de Vault con {api_key, api_secret}. Solo service role.
create table if not exists public.binance_keys (
  user_id uuid primary key references auth.users (id) on delete cascade,
  vault_secret_id uuid not null,
  updated_at timestamptz not null default now()
);
alter table public.binance_keys enable row level security;

-- ---------------------------------------------------------------------------
-- Claves en Vault
-- ---------------------------------------------------------------------------

create or replace function public.binance_keys_save(p_user_id uuid, p_payload text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_secret_id uuid;
begin
  select vault_secret_id into v_secret_id
  from public.binance_keys where user_id = p_user_id
  for update;

  if v_secret_id is null then
    v_secret_id := vault.create_secret(
      p_payload,
      'binance_keys_' || p_user_id::text,
      'Binance API key (read-only)'
    );
    insert into public.binance_keys (user_id, vault_secret_id)
    values (p_user_id, v_secret_id);
  else
    perform vault.update_secret(v_secret_id, p_payload);
    update public.binance_keys set updated_at = now() where user_id = p_user_id;
  end if;
end;
$$;

create or replace function public.binance_keys_read(p_user_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select s.decrypted_secret
  from public.binance_keys k
  join vault.decrypted_secrets s on s.id = k.vault_secret_id
  where k.user_id = p_user_id;
$$;

create or replace function public.binance_keys_delete(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_secret_id uuid;
begin
  delete from public.binance_keys where user_id = p_user_id
  returning vault_secret_id into v_secret_id;
  if v_secret_id is not null then
    delete from vault.secrets where id = v_secret_id;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Lease de sincronización
-- ---------------------------------------------------------------------------

create or replace function public.binance_try_lock(p_user_id uuid, p_seconds int)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ok boolean;
begin
  update public.binance_connections
  set sync_lock_until = now() + make_interval(secs => p_seconds)
  where user_id = p_user_id
    and (sync_lock_until is null or sync_lock_until < now())
  returning true into v_ok;
  return coalesce(v_ok, false);
end;
$$;

create or replace function public.binance_unlock(p_user_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.binance_connections set sync_lock_until = null where user_id = p_user_id;
$$;

-- ---------------------------------------------------------------------------
-- Aplicar una sincronización (todo o nada)
-- ---------------------------------------------------------------------------

-- p_positions: [{id, external_id, ticker, quantity, purchase_price,
--   purchase_date, broker_price}] — la foto COMPLETA de los saldos
--   importables: las filas binance que ya no vienen se borran.
create or replace function public.binance_apply_sync(
  p_user_id uuid,
  p_positions jsonb,
  p_result jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_removed int;
begin
  delete from public.positions p
  where p.user_id = p_user_id
    and p.source = 'binance'
    and not exists (
      select 1 from jsonb_array_elements(p_positions) e
      where e->>'external_id' = p.external_id
    );
  get diagnostics v_removed = row_count;

  insert into public.positions (
    id, user_id, ticker, quantity, purchase_price, purchase_date,
    source, external_id, synced_at, broker_price
  )
  select
    (e->>'id')::uuid, p_user_id, e->>'ticker', (e->>'quantity')::numeric,
    (e->>'purchase_price')::numeric, (e->>'purchase_date')::timestamptz,
    'binance', e->>'external_id', now(), (e->>'broker_price')::numeric
  from jsonb_array_elements(p_positions) e
  on conflict (user_id, source, external_id) do update set
    ticker = excluded.ticker,
    quantity = excluded.quantity,
    purchase_price = excluded.purchase_price,
    purchase_date = excluded.purchase_date,
    synced_at = excluded.synced_at,
    broker_price = excluded.broker_price;

  update public.binance_connections set
    status = 'connected',
    last_sync_at = now(),
    last_sync_status = 'ok',
    last_error_type = null,
    last_result = p_result,
    updated_at = now()
  where user_id = p_user_id;

  return jsonb_build_object('removed', v_removed);
end;
$$;

-- ---------------------------------------------------------------------------
-- Desconectar
-- ---------------------------------------------------------------------------

create or replace function public.binance_disconnect(p_user_id uuid, p_keep_as_manual boolean)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_open int;
begin
  if p_keep_as_manual then
    update public.positions
    set source = 'manual', external_id = null, synced_at = null, broker_price = null
    where user_id = p_user_id and source = 'binance';
  else
    delete from public.positions where user_id = p_user_id and source = 'binance';
  end if;
  get diagnostics v_open = row_count;

  perform public.binance_keys_delete(p_user_id);

  update public.binance_connections set
    status = 'disconnected',
    api_key_hint = null,
    last_result = null,
    last_error_type = null,
    sync_lock_until = null,
    updated_at = now()
  where user_id = p_user_id;

  return jsonb_build_object('open', v_open, 'keptAsManual', p_keep_as_manual);
end;
$$;

-- ---------------------------------------------------------------------------
-- Permisos
-- ---------------------------------------------------------------------------

revoke all on function
  public.binance_keys_save(uuid, text),
  public.binance_keys_read(uuid),
  public.binance_keys_delete(uuid),
  public.binance_try_lock(uuid, int),
  public.binance_unlock(uuid),
  public.binance_apply_sync(uuid, jsonb, jsonb),
  public.binance_disconnect(uuid, boolean)
from public, anon, authenticated;

grant execute on function
  public.binance_keys_save(uuid, text),
  public.binance_keys_read(uuid),
  public.binance_keys_delete(uuid),
  public.binance_try_lock(uuid, int),
  public.binance_unlock(uuid),
  public.binance_apply_sync(uuid, jsonb, jsonb),
  public.binance_disconnect(uuid, boolean)
to service_role;

grant select, insert, update, delete on public.binance_connections, public.binance_keys to service_role;
revoke all on public.binance_keys from anon, authenticated;
revoke all on public.binance_connections from anon, authenticated;
grant select on public.binance_connections to authenticated;
