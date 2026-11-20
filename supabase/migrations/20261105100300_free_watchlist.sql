-- Free sigue hasta 3 tickers (spec 2026-11-05-diferenciacion-planes-v2 §3.3).
-- Solo sube el 0 de Free: si alguien ya lo cambió a mano, se respeta.
update public.plan_limits set watchlist = 3
 where tier = 'free' and watchlist = 0;

-- Los avisos de "se movió fuerte" de la lista también llegan a Free (el costo
-- es despreciable). Igual que 20261016000200_watchlist.sql, sin el filtro de
-- plan `in ('premium', 'gold')`: el tope de la lista ya lo pone plan_limits.
create or replace function public.watchlist_watch_items()
returns table (
  user_id uuid,
  symbol text,
  added_price numeric,
  sensitivity text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    w.user_id,
    w.symbol,
    w.added_price,
    coalesce(np.big_move_sensitivity, 'normal')
  from public.watchlist_items w
  left join public.notification_preferences np on np.user_id = w.user_id
  where w.notify
    and exists (select 1 from public.push_devices d where d.user_id = w.user_id)
    and coalesce(np.enabled, true)
    and coalesce(np.big_moves, true)
    and not exists (
      select 1 from public.positions p
       where p.user_id = w.user_id and upper(p.ticker) = w.symbol and p.quantity > 0
    );
$$;

revoke all on function public.watchlist_watch_items() from public, anon, authenticated;
grant execute on function public.watchlist_watch_items() to service_role;
