-- eToro, segunda parte: precio de eToro como respaldo y logos.
--
-- - positions.broker_price: el precio actual que informa eToro para cada
--   posición importada (`unrealizedPnL.closeRate`, en USD para las acciones
--   de EE.UU.). La app lo usa solo si no consigue cotización propia; antes
--   se valuaba al precio de compra (P&L en 0). Momento: `synced_at`.
-- - etoro_instruments.logo_url: el logo que eToro publica para cada
--   instrumento (`images[]`). La app lo usa donde Finnhub no tiene logo.
--
-- El efectivo y los "otros activos" (cripto, CFD, fuera de EE.UU.) no
-- necesitan columnas: viajan en etoro_connections.last_result, que la app ya
-- lee.

alter table public.positions
  add column if not exists broker_price numeric;

alter table public.etoro_instruments
  add column if not exists logo_url text;

-- Es solo un caché (24 h): se vacía para que el próximo sync traiga los
-- logos en vez de esperar a que venza lo guardado sin logo.
delete from public.etoro_instruments where logo_url is null;

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
    source, external_id, synced_at, broker_price
  )
  select
    (e->>'id')::uuid, p_user_id, e->>'ticker', (e->>'quantity')::numeric,
    (e->>'purchase_price')::numeric, (e->>'purchase_date')::timestamptz,
    'etoro', e->>'external_id', now(), (e->>'broker_price')::numeric
  from jsonb_array_elements(p_positions) e
  on conflict (user_id, source, external_id) do update set
    ticker = excluded.ticker,
    quantity = excluded.quantity,
    purchase_price = excluded.purchase_price,
    purchase_date = excluded.purchase_date,
    synced_at = excluded.synced_at,
    broker_price = excluded.broker_price;

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

-- Igual que antes, pero al conservar como manuales también se borra el
-- precio de eToro: una posición manual se valúa solo con cotización propia.
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
    set source = 'manual', external_id = null, synced_at = null, broker_price = null
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

revoke all on function
  public.etoro_apply_sync(uuid, jsonb, jsonb, jsonb, text, date),
  public.etoro_disconnect(uuid, boolean)
from public, anon, authenticated;

grant execute on function
  public.etoro_apply_sync(uuid, jsonb, jsonb, jsonb, text, date),
  public.etoro_disconnect(uuid, boolean)
to service_role;
