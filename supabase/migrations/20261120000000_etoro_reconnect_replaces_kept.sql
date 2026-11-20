-- eToro: reconectar reemplaza lo que se había conservado como manual.
--
-- Al desconectar conservando las posiciones (`etoro_disconnect(..., true)`)
-- o al cerrar una importación gratis (`etoro_finish_free_import`), lo
-- importado pasa a `source = 'manual'` con el MISMO id. La edge function
-- arma los ids de forma estable (usuario + tipo + id de eToro), así que al
-- volver a conectar la sincronización traía esos mismos ids y el insert
-- chocaba con `positions_pkey`: el sync fallaba entero ("no se pudo
-- actualizar desde eToro") y el usuario veía la foto vieja.
--
-- Ahora, antes de insertar, se borran las manuales del usuario cuyo id es
-- el de una posición que llega de eToro:
--   - abiertas: el id de cada posición abierta que llega, y el id que tuvo
--     como abierta cada cerrada que llega (`open_id`, lo manda la edge
--     function; si no viene, no se usa). Así una posición que se cerró
--     mientras estaba desconectado no queda duplicada como abierta manual.
--   - cerradas: el id de cada cerrada que llega.
-- El usuario ve lo de eToro en lugar de la copia vieja, sin duplicados.
-- Las manuales cargadas a mano tienen ids aleatorios y no se tocan.

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
  v_replaced int;
  v_replaced_closed int;
begin
  -- Copias manuales de lo que llega de eToro (ver arriba).
  delete from public.positions p
  where p.user_id = p_user_id
    and p.source = 'manual'
    and p.id in (
      select (e->>'id')::uuid from jsonb_array_elements(p_positions) e
      union
      select (e->>'open_id')::uuid from jsonb_array_elements(p_closed) e
      where e->>'open_id' is not null
    );
  get diagnostics v_replaced = row_count;

  delete from public.closed_positions c
  where c.user_id = p_user_id
    and c.source = 'manual'
    and c.id in (select (e->>'id')::uuid from jsonb_array_elements(p_closed) e);
  get diagnostics v_replaced_closed = row_count;

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
    'closedAdded', v_closed_added,
    'replacedManual', v_replaced,
    'replacedManualClosed', v_replaced_closed
  );
end;
$$;

revoke all on function public.etoro_apply_sync(uuid, jsonb, jsonb, jsonb, text, date)
  from public, anon, authenticated;
grant execute on function public.etoro_apply_sync(uuid, jsonb, jsonb, jsonb, text, date)
  to service_role;
