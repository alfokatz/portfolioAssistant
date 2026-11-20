-- Fecha de compra desconocida: algunos brókers (por SnapTrade) no informan
-- cuándo se compró. La fila lleva la fecha de la sincronización y
-- `purchase_date_known = false`: la app muestra "Fecha de compra
-- desconocida" y, en el gráfico, la cuenta como que ya estaba al empezar
-- el período (en vez de una compra de hoy). Todo lo demás: true.

alter table public.positions
  add column if not exists purchase_date_known boolean not null default true;

-- p_positions: [{id, external_id, ticker, quantity, purchase_price,
--   purchase_date, purchase_date_known, broker_price}].
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
    purchase_date_known, source, external_id, synced_at, broker_price
  )
  select
    (e->>'id')::uuid, p_user_id, e->>'ticker', (e->>'quantity')::numeric,
    (e->>'purchase_price')::numeric, (e->>'purchase_date')::timestamptz,
    coalesce((e->>'purchase_date_known')::boolean, true),
    'snaptrade', e->>'external_id', now(), (e->>'broker_price')::numeric
  from jsonb_array_elements(p_positions) e
  on conflict (user_id, source, external_id) do update set
    ticker = excluded.ticker,
    quantity = excluded.quantity,
    purchase_price = excluded.purchase_price,
    purchase_date = excluded.purchase_date,
    purchase_date_known = excluded.purchase_date_known,
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

revoke all on function public.snaptrade_apply_sync(uuid, jsonb, jsonb, jsonb, jsonb)
from public, anon, authenticated;
grant execute on function public.snaptrade_apply_sync(uuid, jsonb, jsonb, jsonb, jsonb)
to service_role;
