-- Movimientos fuertes de la cartera (F4 del plan
-- docs/superpowers/plans/2026-10-10-notificaciones-push.md, §4.3).
--
-- market-watch calcula los candidatos (moves.ts) y los encola con
-- `market_enqueue_moves`, que aplica las reglas de "agrupar, no repetir":
-- - Cada ticker avisa una vez por día y dirección (`level` 1) y, si después
--   duplica el umbral, una vez más (`level` 2). La marca es la clave de
--   duplicados del outbox.
-- - 2 o más tickers nuevos en la misma corrida → un solo resumen
--   (`big_move_digest`).
-- - Si en la misma corrida se mueve la cartera entera, va una sola
--   notificación (`portfolio_move`, con los que más la movieron).

-- Posiciones abiertas, sumadas por ticker, de quien quiere estos avisos y
-- tiene al menos un dispositivo (sin dispositivo no hay a quién avisar).
create or replace function public.market_watch_holdings()
returns table (
  user_id uuid,
  symbol text,
  quantity numeric,
  sensitivity text,
  big_moves boolean,
  portfolio_moves boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select
    p.user_id,
    upper(p.ticker),
    sum(p.quantity),
    coalesce(np.big_move_sensitivity, 'normal'),
    coalesce(np.big_moves, true),
    coalesce(np.portfolio_moves, true)
  from public.positions p
  left join public.notification_preferences np on np.user_id = p.user_id
  where exists (select 1 from public.push_devices d where d.user_id = p.user_id)
    and coalesce(np.enabled, true)
    and (coalesce(np.big_moves, true) or coalesce(np.portfolio_moves, true))
  group by p.user_id, upper(p.ticker), np.big_move_sensitivity, np.big_moves, np.portfolio_moves
  having sum(p.quantity) > 0;
$$;

-- p_items: [{user_id, moves: [{symbol, change_pct, weight_pct, direction,
-- level}], portfolio: {change_pct, change_value, direction,
-- benchmark_change_pct, moves} | null}]
-- Devuelve cuántas notificaciones quedaron pendientes.
create or replace function public.market_enqueue_moves(p_market_date date, p_items jsonb)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item jsonb;
  v_move jsonb;
  v_user uuid;
  v_base text;
  v_l1 bigint;
  v_l2 bigint;
  v_new_ids bigint[];
  v_new_moves jsonb;
  v_portfolio_id bigint;
  v_digest_id bigint;
  v_pending int := 0;
begin
  for v_item in select * from jsonb_array_elements(p_items) loop
    v_user := (v_item ->> 'user_id')::uuid;
    v_new_ids := '{}';
    v_new_moves := '[]'::jsonb;

    for v_move in select * from jsonb_array_elements(coalesce(v_item -> 'moves', '[]'::jsonb)) loop
      v_base := 'big_move:' || (v_move ->> 'symbol') || ':' || p_market_date || ':' || (v_move ->> 'direction');
      v_l1 := null;
      v_l2 := null;

      insert into public.notification_outbox (user_id, kind, dedupe_key, data)
      values (v_user, 'big_move', v_base || ':1', v_move)
      on conflict (user_id, dedupe_key) do nothing
      returning id into v_l1;

      if (v_move ->> 'level')::int >= 2 then
        insert into public.notification_outbox (user_id, kind, dedupe_key, data, status, skip_reason, processed_at)
        values (
          v_user, 'big_move', v_base || ':2', v_move,
          -- Si el nivel 1 es nuevo, con ese aviso alcanza: este solo marca.
          case when v_l1 is null then 'pending' else 'skipped' end,
          case when v_l1 is null then null else 'superseded' end,
          case when v_l1 is null then null else now() end
        )
        on conflict (user_id, dedupe_key) do nothing
        returning id into v_l2;
        if v_l1 is not null then
          v_l2 := null;
        end if;
      end if;

      if coalesce(v_l1, v_l2) is not null then
        v_new_ids := v_new_ids || coalesce(v_l1, v_l2);
        v_new_moves := v_new_moves || jsonb_build_array(jsonb_build_object(
          'symbol', v_move ->> 'symbol',
          'change_pct', (v_move ->> 'change_pct')::numeric));
      end if;
    end loop;

    v_portfolio_id := null;
    if jsonb_typeof(v_item -> 'portfolio') = 'object' then
      insert into public.notification_outbox (user_id, kind, dedupe_key, data)
      values (
        v_user, 'portfolio_move',
        'portfolio_move:' || p_market_date || ':' || (v_item -> 'portfolio' ->> 'direction'),
        v_item -> 'portfolio'
      )
      on conflict (user_id, dedupe_key) do nothing
      returning id into v_portfolio_id;
    end if;

    if v_portfolio_id is not null then
      -- Una sola: la de la cartera ya nombra lo que más la movió.
      update public.notification_outbox
         set status = 'skipped', skip_reason = 'in_portfolio_move', processed_at = now()
       where id = any (v_new_ids);
      v_pending := v_pending + 1;
    elsif coalesce(array_length(v_new_ids, 1), 0) >= 2 then
      update public.notification_outbox
         set status = 'skipped', skip_reason = 'in_digest', processed_at = now()
       where id = any (v_new_ids);
      insert into public.notification_outbox (user_id, kind, dedupe_key, data)
      values (
        v_user, 'big_move_digest',
        'big_move_digest:' || p_market_date || ':' ||
          (select string_agg(m ->> 'symbol', ',' order by m ->> 'symbol')
             from jsonb_array_elements(v_new_moves) m),
        jsonb_build_object('moves', v_new_moves)
      )
      on conflict (user_id, dedupe_key) do nothing
      returning id into v_digest_id;
      if v_digest_id is not null then
        v_pending := v_pending + 1;
      end if;
    else
      v_pending := v_pending + coalesce(array_length(v_new_ids, 1), 0);
    end if;
  end loop;
  return v_pending;
end;
$$;

revoke all on function public.market_watch_holdings() from public, anon, authenticated;
revoke all on function public.market_enqueue_moves(date, jsonb) from public, anon, authenticated;
grant execute on function public.market_watch_holdings() to service_role;
grant execute on function public.market_enqueue_moves(date, jsonb) to service_role;
