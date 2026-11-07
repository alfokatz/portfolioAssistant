-- Conexión de solo lectura con eToro (FASE 2 de
-- docs/superpowers/research/2026-10-08-etoro-integration.md).
--
-- - Los tokens OAuth de eToro viven cifrados en Supabase Vault y solo la
--   service role (edge function `etoro-sync`) los lee o escribe. Nunca llegan
--   a la app ni a una tabla legible por el usuario.
-- - Las posiciones importadas viven en las mismas tablas que las manuales,
--   marcadas con `source = 'etoro'`. Un trigger las vuelve de solo lectura
--   para los roles de la app (anon/authenticated): editarlas, cerrarlas o
--   borrarlas solo lo hace la edge function, al sincronizar o desconectar.
-- - Cada sincronización se aplica entera o no se aplica
--   (`etoro_apply_sync`, una transacción).

-- ---------------------------------------------------------------------------
-- positions / closed_positions
-- ---------------------------------------------------------------------------

-- Las tablas ya existen en el proyecto remoto (se crearon antes de linkear la
-- CLI; ver 20260604171839_remote_baseline.sql). Estas definiciones son las
-- que usa la app (SupabasePortfolioMapper) y solo corren en una base vacía
-- (supabase start / tests); en el remoto `if not exists` las saltea.
create table if not exists public.positions (
  id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  ticker text not null,
  quantity numeric not null,
  purchase_price numeric not null,
  purchase_date timestamptz not null,
  created_at timestamptz not null default now()
);

create table if not exists public.closed_positions (
  id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  ticker text not null,
  quantity numeric not null,
  avg_purchase_price numeric not null,
  close_price numeric not null,
  close_date timestamptz not null,
  closed_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

alter table public.positions enable row level security;
alter table public.closed_positions enable row level security;

-- Policies "cada uno lo suyo" solo si la tabla no tiene ninguna (base
-- local). En el remoto se respetan las que ya existen.
do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'positions') then
    create policy "Users manage own positions" on public.positions
      for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'closed_positions') then
    create policy "Users manage own closed positions" on public.closed_positions
      for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
  end if;
end $$;

grant select, insert, update, delete on public.positions, public.closed_positions to authenticated;
grant select, insert, update, delete on public.positions, public.closed_positions to service_role;

-- Origen de cada fila. Las manuales siguen igual (default 'manual').
alter table public.positions
  add column if not exists source text not null default 'manual',
  add column if not exists external_id text,
  add column if not exists synced_at timestamptz;

alter table public.closed_positions
  add column if not exists source text not null default 'manual',
  add column if not exists external_id text,
  add column if not exists synced_at timestamptz,
  -- Ganancia neta informada por el bróker (eToro: netProfit, ya con
  -- comisiones y dividendos). Null en las manuales: ahí la calcula Porty.
  add column if not exists realized_pnl numeric;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'positions_source_check') then
    alter table public.positions
      add constraint positions_source_check check (source in ('manual', 'etoro'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'closed_positions_source_check') then
    alter table public.closed_positions
      add constraint closed_positions_source_check check (source in ('manual', 'etoro'));
  end if;
  -- Una fila por posición del bróker. Las manuales (external_id null) no
  -- chocan entre sí: en un unique los null son distintos.
  if not exists (select 1 from pg_constraint where conname = 'positions_source_external_key') then
    alter table public.positions
      add constraint positions_source_external_key unique (user_id, source, external_id);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'closed_positions_source_external_key') then
    alter table public.closed_positions
      add constraint closed_positions_source_external_key unique (user_id, source, external_id);
  end if;
end $$;

-- Solo lectura para la app. Va como trigger (y no como policy) para no
-- depender de cómo se llaman las policies que ya existen en el remoto.
-- `current_user` es el rol con el que entra el pedido: anon/authenticated
-- desde la app; service_role o el dueño de las funciones de abajo desde la
-- edge function.
create or replace function public._etoro_rows_read_only()
returns trigger
language plpgsql
as $$
begin
  if current_user in ('anon', 'authenticated') then
    if (tg_op in ('UPDATE', 'DELETE') and old.source = 'etoro')
       or (tg_op in ('INSERT', 'UPDATE') and new.source = 'etoro') then
      raise exception 'etoro_rows_are_read_only'
        using errcode = '42501',
              hint = 'Las posiciones importadas de eToro se actualizan solas.';
    end if;
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists positions_etoro_read_only on public.positions;
create trigger positions_etoro_read_only
  before insert or update or delete on public.positions
  for each row execute function public._etoro_rows_read_only();

drop trigger if exists closed_positions_etoro_read_only on public.closed_positions;
create trigger closed_positions_etoro_read_only
  before insert or update or delete on public.closed_positions
  for each row execute function public._etoro_rows_read_only();

-- ---------------------------------------------------------------------------
-- Estado de la conexión (lo lee la app)
-- ---------------------------------------------------------------------------

create table if not exists public.etoro_connections (
  user_id uuid primary key references auth.users (id) on delete cascade,
  -- `sub` del ID token: identificador pairwise que eToro da a nuestro cliente
  -- (sin datos personales). Ver "Identity and personal data" en la doc SSO.
  etoro_sub text,
  status text not null default 'connected'
    check (status in ('connected', 'reconnect_required', 'disconnected')),
  granted_scopes text[] not null default '{}',
  account_currency text,
  connected_at timestamptz,
  last_sync_at timestamptz,
  last_sync_status text check (last_sync_status in ('ok', 'error')),
  last_error_type text,
  -- Resumen de la última importación para la pantalla de resultado:
  -- {imported, notImported: [{ticker, reason, count}], possibleDuplicates}.
  last_result jsonb,
  -- Hasta qué fecha ya se trajo el historial de cerradas (incremental).
  history_synced_until date,
  -- Lease: una sola sincronización a la vez por usuario (el refresh token
  -- rota y dos refrescos simultáneos se invalidarían entre sí).
  sync_lock_until timestamptz,
  updated_at timestamptz not null default now()
);

alter table public.etoro_connections enable row level security;

drop policy if exists "Users read own etoro connection" on public.etoro_connections;
create policy "Users read own etoro connection" on public.etoro_connections
  for select using (auth.uid() = user_id);
-- Sin policies de escritura: solo la edge function.

-- ---------------------------------------------------------------------------
-- Tablas internas (sin policies: solo service role)
-- ---------------------------------------------------------------------------

-- Puntero al secreto de Vault con {access_token, refresh_token, expires_at}.
create table if not exists public.etoro_tokens (
  user_id uuid primary key references auth.users (id) on delete cascade,
  vault_secret_id uuid not null,
  updated_at timestamptz not null default now()
);
alter table public.etoro_tokens enable row level security;

-- Intentos de conexión en curso: state → usuario, PKCE y nonce. Viven en el
-- servidor; el navegador solo ve `state` y el `code_challenge`.
create table if not exists public.etoro_oauth_states (
  state text primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  code_verifier text not null,
  nonce text not null,
  created_at timestamptz not null default now()
);
alter table public.etoro_oauth_states enable row level security;

-- Caché global de metadata de instrumentos (ticker, tipo, bolsa).
create table if not exists public.etoro_instruments (
  instrument_id int primary key,
  symbol_full text not null,
  display_name text,
  instrument_type_id int,
  instrument_type text,
  exchange_id int,
  exchange text,
  updated_at timestamptz not null default now()
);
alter table public.etoro_instruments enable row level security;

-- ---------------------------------------------------------------------------
-- Tokens en Vault
-- ---------------------------------------------------------------------------

create or replace function public.etoro_tokens_save(p_user_id uuid, p_payload text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_secret_id uuid;
begin
  select vault_secret_id into v_secret_id
  from public.etoro_tokens where user_id = p_user_id
  for update;

  if v_secret_id is null then
    v_secret_id := vault.create_secret(
      p_payload,
      'etoro_tokens_' || p_user_id::text,
      'eToro OAuth tokens (read-only scopes)'
    );
    insert into public.etoro_tokens (user_id, vault_secret_id)
    values (p_user_id, v_secret_id);
  else
    perform vault.update_secret(v_secret_id, p_payload);
    update public.etoro_tokens set updated_at = now() where user_id = p_user_id;
  end if;
end;
$$;

create or replace function public.etoro_tokens_read(p_user_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select s.decrypted_secret
  from public.etoro_tokens t
  join vault.decrypted_secrets s on s.id = t.vault_secret_id
  where t.user_id = p_user_id;
$$;

create or replace function public.etoro_tokens_delete(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_secret_id uuid;
begin
  delete from public.etoro_tokens where user_id = p_user_id
  returning vault_secret_id into v_secret_id;
  if v_secret_id is not null then
    delete from vault.secrets where id = v_secret_id;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Lease de sincronización
-- ---------------------------------------------------------------------------

-- true si este pedido se quedó con el lease (y lo toma por p_seconds).
create or replace function public.etoro_try_lock(p_user_id uuid, p_seconds int)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ok boolean;
begin
  update public.etoro_connections
  set sync_lock_until = now() + make_interval(secs => p_seconds)
  where user_id = p_user_id
    and (sync_lock_until is null or sync_lock_until < now())
  returning true into v_ok;
  return coalesce(v_ok, false);
end;
$$;

create or replace function public.etoro_unlock(p_user_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.etoro_connections set sync_lock_until = null where user_id = p_user_id;
$$;

-- ---------------------------------------------------------------------------
-- Aplicar una sincronización (todo o nada)
-- ---------------------------------------------------------------------------

-- p_positions: [{id, external_id, ticker, quantity, purchase_price, purchase_date}]
--   Es la foto COMPLETA de las abiertas importables: las filas etoro que ya
--   no vienen (cerradas en eToro) se borran.
-- p_closed: [{id, external_id, ticker, quantity, avg_purchase_price,
--   close_price, close_date, realized_pnl}] — solo agrega (el historial no
--   cambia); repetir una ya importada no hace nada.
create or replace function public.etoro_apply_sync(
  p_user_id uuid,
  p_positions jsonb,
  p_closed jsonb,
  p_result jsonb,
  p_account_currency text,
  p_history_until date
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_removed int;
  v_closed_added int;
begin
  delete from public.positions p
  where p.user_id = p_user_id
    and p.source = 'etoro'
    and not exists (
      select 1 from jsonb_array_elements(p_positions) e
      where e->>'external_id' = p.external_id
    );
  get diagnostics v_removed = row_count;

  insert into public.positions (
    id, user_id, ticker, quantity, purchase_price, purchase_date,
    source, external_id, synced_at
  )
  select
    (e->>'id')::uuid, p_user_id, e->>'ticker', (e->>'quantity')::numeric,
    (e->>'purchase_price')::numeric, (e->>'purchase_date')::timestamptz,
    'etoro', e->>'external_id', now()
  from jsonb_array_elements(p_positions) e
  on conflict (user_id, source, external_id) do update set
    ticker = excluded.ticker,
    quantity = excluded.quantity,
    purchase_price = excluded.purchase_price,
    purchase_date = excluded.purchase_date,
    synced_at = excluded.synced_at;

  insert into public.closed_positions (
    id, user_id, ticker, quantity, avg_purchase_price, close_price,
    close_date, closed_at, source, external_id, synced_at, realized_pnl
  )
  select
    (e->>'id')::uuid, p_user_id, e->>'ticker', (e->>'quantity')::numeric,
    (e->>'avg_purchase_price')::numeric, (e->>'close_price')::numeric,
    (e->>'close_date')::timestamptz, (e->>'close_date')::timestamptz,
    'etoro', e->>'external_id', now(), (e->>'realized_pnl')::numeric
  from jsonb_array_elements(p_closed) e
  on conflict (user_id, source, external_id) do nothing;
  get diagnostics v_closed_added = row_count;

  update public.etoro_connections set
    status = 'connected',
    account_currency = coalesce(p_account_currency, account_currency),
    last_sync_at = now(),
    last_sync_status = 'ok',
    last_error_type = null,
    last_result = p_result,
    history_synced_until = coalesce(p_history_until, history_synced_until),
    updated_at = now()
  where user_id = p_user_id;

  return jsonb_build_object(
    'removed', v_removed,
    'closedAdded', v_closed_added
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Desconectar
-- ---------------------------------------------------------------------------

-- Borra los tokens y marca la conexión como desconectada. Con
-- p_keep_as_manual las posiciones importadas pasan a ser manuales (el
-- usuario las edita como cualquier otra); si no, se borran.
create or replace function public.etoro_disconnect(p_user_id uuid, p_keep_as_manual boolean)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_open int;
  v_closed int;
begin
  if p_keep_as_manual then
    update public.positions
    set source = 'manual', external_id = null, synced_at = null
    where user_id = p_user_id and source = 'etoro';
    get diagnostics v_open = row_count;
    update public.closed_positions
    set source = 'manual', external_id = null, synced_at = null
    where user_id = p_user_id and source = 'etoro';
    get diagnostics v_closed = row_count;
  else
    delete from public.positions where user_id = p_user_id and source = 'etoro';
    get diagnostics v_open = row_count;
    delete from public.closed_positions where user_id = p_user_id and source = 'etoro';
    get diagnostics v_closed = row_count;
  end if;

  perform public.etoro_tokens_delete(p_user_id);
  delete from public.etoro_oauth_states where user_id = p_user_id;

  update public.etoro_connections set
    status = 'disconnected',
    granted_scopes = '{}',
    last_result = null,
    last_error_type = null,
    history_synced_until = null,
    sync_lock_until = null,
    updated_at = now()
  where user_id = p_user_id;

  return jsonb_build_object('open', v_open, 'closed', v_closed, 'keptAsManual', p_keep_as_manual);
end;
$$;

-- ---------------------------------------------------------------------------
-- Permisos
-- ---------------------------------------------------------------------------

revoke all on function
  public.etoro_tokens_save(uuid, text),
  public.etoro_tokens_read(uuid),
  public.etoro_tokens_delete(uuid),
  public.etoro_try_lock(uuid, int),
  public.etoro_unlock(uuid),
  public.etoro_apply_sync(uuid, jsonb, jsonb, jsonb, text, date),
  public.etoro_disconnect(uuid, boolean)
from public, anon, authenticated;

grant execute on function
  public.etoro_tokens_save(uuid, text),
  public.etoro_tokens_read(uuid),
  public.etoro_tokens_delete(uuid),
  public.etoro_try_lock(uuid, int),
  public.etoro_unlock(uuid),
  public.etoro_apply_sync(uuid, jsonb, jsonb, jsonb, text, date),
  public.etoro_disconnect(uuid, boolean)
to service_role;

grant select, insert, update, delete on
  public.etoro_connections,
  public.etoro_tokens,
  public.etoro_oauth_states,
  public.etoro_instruments
to service_role;

-- Supabase da por defecto todos los permisos de `public` a anon y
-- authenticated: las tablas internas se cierran también por permisos (no
-- solo por RLS sin policies).
revoke all on
  public.etoro_tokens,
  public.etoro_oauth_states,
  public.etoro_instruments
from anon, authenticated;
revoke all on public.etoro_connections from anon, authenticated;

-- La app solo lee su conexión (la policy filtra por usuario).
grant select on public.etoro_connections to authenticated;
