-- SnapTrade con el historial de operaciones: cada compra abierta es una
-- fila de `positions` (con su fecha y su precio) y cada venta, una de
-- `closed_positions` (source 'snaptrade'). Ver docs/runbooks/snaptrade-sync.md.
--
-- - `snaptrade_apply_sync` suma `p_closed` (la foto completa de las ventas:
--   las que ya no vienen se borran) y ahora actualiza también la fecha de
--   compra, que sale del historial.
-- - `snaptrade_disconnect` trata las ventas igual que las abiertas
--   (conservarlas como manuales o borrarlas).

drop function if exists public.snaptrade_apply_sync(uuid, jsonb, jsonb, jsonb);

-- p_positions: [{id, external_id, ticker, quantity, purchase_price,
--   purchase_date, broker_price}].
-- p_closed: [{id, external_id, ticker, quantity, avg_purchase_price,
--   close_price, close_date, realized_pnl}].
create or replace function public.snaptrade_apply_sync(
  p_user_id uuid,
  p_positions jsonb,
  p_closed jsonb,
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
    purchase_date = excluded.purchase_date,
    synced_at = excluded.synced_at,
    broker_price = excluded.broker_price;

  delete from public.closed_positions c
  where c.user_id = p_user_id
    and c.source = 'snaptrade'
    and not exists (
      select 1 from jsonb_array_elements(p_closed) e
      where e->>'external_id' = c.external_id
    );

  insert into public.closed_positions (
    id, user_id, ticker, quantity, avg_purchase_price, close_price,
    close_date, closed_at, source, external_id, synced_at, realized_pnl
  )
  select
    (e->>'id')::uuid, p_user_id, e->>'ticker', (e->>'quantity')::numeric,
    (e->>'avg_purchase_price')::numeric, (e->>'close_price')::numeric,
    (e->>'close_date')::timestamptz, (e->>'close_date')::timestamptz,
    'snaptrade', e->>'external_id', now(), (e->>'realized_pnl')::numeric
  from jsonb_array_elements(p_closed) e
  on conflict (user_id, source, external_id) do update set
    ticker = excluded.ticker,
    quantity = excluded.quantity,
    avg_purchase_price = excluded.avg_purchase_price,
    close_price = excluded.close_price,
    close_date = excluded.close_date,
    closed_at = excluded.closed_at,
    synced_at = excluded.synced_at,
    realized_pnl = excluded.realized_pnl;

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

create or replace function public.snaptrade_disconnect(p_user_id uuid, p_keep_as_manual boolean)
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
    where user_id = p_user_id and source = 'snaptrade';
    get diagnostics v_open = row_count;
    update public.closed_positions
    set source = 'manual', external_id = null, synced_at = null
    where user_id = p_user_id and source = 'snaptrade';
    get diagnostics v_closed = row_count;
  else
    delete from public.positions where user_id = p_user_id and source = 'snaptrade';
    get diagnostics v_open = row_count;
    delete from public.closed_positions where user_id = p_user_id and source = 'snaptrade';
    get diagnostics v_closed = row_count;
  end if;

  perform public.snaptrade_secret_delete(p_user_id);

  update public.snaptrade_connections set
    status = 'disconnected',
    brokerages = '[]'::jsonb,
    last_result = null,
    last_error_type = null,
    sync_lock_until = null,
    updated_at = now()
  where user_id = p_user_id;

  return jsonb_build_object('open', v_open, 'closed', v_closed, 'keptAsManual', p_keep_as_manual);
end;
$$;

revoke all on function
  public.snaptrade_apply_sync(uuid, jsonb, jsonb, jsonb, jsonb),
  public.snaptrade_disconnect(uuid, boolean)
from public, anon, authenticated;

grant execute on function
  public.snaptrade_apply_sync(uuid, jsonb, jsonb, jsonb, jsonb),
  public.snaptrade_disconnect(uuid, boolean)
to service_role;
