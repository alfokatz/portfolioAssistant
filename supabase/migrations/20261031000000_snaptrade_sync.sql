-- Conexión de solo lectura con brókers vía SnapTrade (agregador), para los
-- que Porty no conecta directo (IBKR, Schwab…). Ver
-- docs/runbooks/snaptrade-sync.md.
--
-- - Cada usuario de Porty que conecta tiene un usuario en SnapTrade
--   (`userId` propio, al azar, y `userSecret`). Los dos van cifrados en
--   Supabase Vault y nunca vuelven a la app.
-- - La conexión con el bróker se hace en el Connection Portal de SnapTrade
--   siempre con `connectionType = read`: Porty no puede operar.
-- - Las posiciones se importan como `source = 'snaptrade'`, de solo lectura
--   para la app (el trigger `_etoro_rows_read_only` ya cubre todo lo que no
--   es manual).
-- - Cada sincronización es la foto completa y se aplica entera o no se
--   aplica (`snaptrade_apply_sync`).
-- - SnapTrade cobra por usuario conectado: al desconectar, la edge function
--   borra el usuario en SnapTrade y acá se borra el secreto.

-- ---------------------------------------------------------------------------
-- Origen de las posiciones
-- ---------------------------------------------------------------------------

alter table public.positions drop constraint if exists positions_source_check;
alter table public.positions
  add constraint positions_source_check check (source in ('manual', 'etoro', 'binance', 'snaptrade'));

alter table public.closed_positions drop constraint if exists closed_positions_source_check;
alter table public.closed_positions
  add constraint closed_positions_source_check check (source in ('manual', 'etoro', 'binance', 'snaptrade'));

-- ---------------------------------------------------------------------------
-- Estado de la conexión (lo lee la app)
-- ---------------------------------------------------------------------------

create table if not exists public.snaptrade_connections (
  user_id uuid primary key references auth.users (id) on delete cascade,
  -- pending: tiene usuario en SnapTrade pero todavía no conectó un bróker.
  status text not null default 'pending'
    check (status in ('pending', 'connected', 'reconnect_required', 'disconnected')),
  -- [{id, name, slug, disabled, imported}]: los brókers conectados en
  -- SnapTrade. `imported` = false si el plan no alcanza (Premium: uno).
  brokerages jsonb not null default '[]'::jsonb,
  connected_at timestamptz,
  last_sync_at timestamptz,
  last_sync_status text check (last_sync_status in ('ok', 'error')),
  last_error_type text,
  -- {imported, notImported: [{ticker, broker, reason}], estimatedCost: [ticker], syncedAt}.
  last_result jsonb,
  -- Actualizaciones manuales (Gold): SnapTrade cobra cada una.
  refresh_day date,
  refresh_count int not null default 0,
  -- Lease: una sola sincronización a la vez por usuario.
  sync_lock_until timestamptz,
  updated_at timestamptz not null default now()
);

alter table public.snaptrade_connections enable row level security;

drop policy if exists "Users read own snaptrade connection" on public.snaptrade_connections;
create policy "Users read own snaptrade connection" on public.snaptrade_connections
  for select using (auth.uid() = user_id);

-- Puntero al secreto de Vault con {user_id, user_secret}. Solo service role.
create table if not exists public.snaptrade_users (
  user_id uuid primary key references auth.users (id) on delete cascade,
  vault_secret_id uuid not null,
  updated_at timestamptz not null default now()
);
alter table public.snaptrade_users enable row level security;

-- ---------------------------------------------------------------------------
-- Secreto del usuario de SnapTrade en Vault
-- ---------------------------------------------------------------------------

create or replace function public.snaptrade_secret_save(p_user_id uuid, p_payload text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_secret_id uuid;
begin
  select vault_secret_id into v_secret_id
  from public.snaptrade_users where user_id = p_user_id
  for update;

  if v_secret_id is null then
    v_secret_id := vault.create_secret(
      p_payload,
      'snaptrade_user_' || p_user_id::text,
      'SnapTrade user (read-only connections)'
    );
    insert into public.snaptrade_users (user_id, vault_secret_id)
    values (p_user_id, v_secret_id);
  else
    perform vault.update_secret(v_secret_id, p_payload);
    update public.snaptrade_users set updated_at = now() where user_id = p_user_id;
  end if;
end;
$$;

create or replace function public.snaptrade_secret_read(p_user_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select s.decrypted_secret
  from public.snaptrade_users u
  join vault.decrypted_secrets s on s.id = u.vault_secret_id
  where u.user_id = p_user_id;
$$;

create or replace function public.snaptrade_secret_delete(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_secret_id uuid;
begin
  delete from public.snaptrade_users where user_id = p_user_id
  returning vault_secret_id into v_secret_id;
  if v_secret_id is not null then
    delete from vault.secrets where id = v_secret_id;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Lease de sincronización
-- ---------------------------------------------------------------------------

create or replace function public.snaptrade_try_lock(p_user_id uuid, p_seconds int)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ok boolean;
begin
  update public.snaptrade_connections
  set sync_lock_until = now() + make_interval(secs => p_seconds)
  where user_id = p_user_id
    and (sync_lock_until is null or sync_lock_until < now())
  returning true into v_ok;
  return coalesce(v_ok, false);
end;
$$;

create or replace function public.snaptrade_unlock(p_user_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.snaptrade_connections set sync_lock_until = null where user_id = p_user_id;
$$;

-- ---------------------------------------------------------------------------
-- Actualización manual: cupo diario (UTC), atómico
-- ---------------------------------------------------------------------------

-- true si quedaba cupo hoy (y lo consume).
create or replace function public.snaptrade_take_refresh(p_user_id uuid, p_per_day int)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ok boolean;
begin
  update public.snaptrade_connections set
    refresh_count = case when refresh_day = current_date then refresh_count + 1 else 1 end,
    refresh_day = current_date,
    updated_at = now()
  where user_id = p_user_id
    and (refresh_day is distinct from current_date or refresh_count < p_per_day)
  returning true into v_ok;
  return coalesce(v_ok, false);
end;
$$;

-- ---------------------------------------------------------------------------
-- Aplicar una sincronización (todo o nada)
-- ---------------------------------------------------------------------------

-- p_positions: [{id, external_id, ticker, quantity, purchase_price,
--   purchase_date, broker_price}] — la foto COMPLETA de lo importable: las
--   filas snaptrade que ya no vienen se borran.
create or replace function public.snaptrade_apply_sync(
  p_user_id uuid,
  p_positions jsonb,
  p_brokerages jsonb,
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
    and p.source = 'snaptrade'
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
    'snaptrade', e->>'external_id', now(), (e->>'broker_price')::numeric
  from jsonb_array_elements(p_positions) e
  on conflict (user_id, source, external_id) do update set
    ticker = excluded.ticker,
    quantity = excluded.quantity,
    purchase_price = excluded.purchase_price,
    -- La fecha de la primera vez que se vio: SnapTrade no informa cuándo
    -- se compró, y no tiene que correrse en cada sincronización.
    synced_at = excluded.synced_at,
    broker_price = excluded.broker_price;

  update public.snaptrade_connections set
    status = case when jsonb_array_length(p_brokerages) = 0 then 'pending' else 'connected' end,
    connected_at = coalesce(connected_at, case when jsonb_array_length(p_brokerages) > 0 then now() end),
    brokerages = p_brokerages,
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
-- Desconectar (la edge function ya borró el usuario en SnapTrade)
-- ---------------------------------------------------------------------------

create or replace function public.snaptrade_disconnect(p_user_id uuid, p_keep_as_manual boolean)
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
    where user_id = p_user_id and source = 'snaptrade';
  else
    delete from public.positions where user_id = p_user_id and source = 'snaptrade';
  end if;
  get diagnostics v_open = row_count;

  perform public.snaptrade_secret_delete(p_user_id);

  update public.snaptrade_connections set
    status = 'disconnected',
    brokerages = '[]'::jsonb,
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
  public.snaptrade_secret_save(uuid, text),
  public.snaptrade_secret_read(uuid),
  public.snaptrade_secret_delete(uuid),
  public.snaptrade_try_lock(uuid, int),
  public.snaptrade_unlock(uuid),
  public.snaptrade_take_refresh(uuid, int),
  public.snaptrade_apply_sync(uuid, jsonb, jsonb, jsonb),
  public.snaptrade_disconnect(uuid, boolean)
from public, anon, authenticated;

grant execute on function
  public.snaptrade_secret_save(uuid, text),
  public.snaptrade_secret_read(uuid),
  public.snaptrade_secret_delete(uuid),
  public.snaptrade_try_lock(uuid, int),
  public.snaptrade_unlock(uuid),
  public.snaptrade_take_refresh(uuid, int),
  public.snaptrade_apply_sync(uuid, jsonb, jsonb, jsonb),
  public.snaptrade_disconnect(uuid, boolean)
to service_role;

grant select, insert, update, delete on public.snaptrade_connections, public.snaptrade_users to service_role;
revoke all on public.snaptrade_users from anon, authenticated;
revoke all on public.snaptrade_connections from anon, authenticated;
grant select on public.snaptrade_connections to authenticated;
