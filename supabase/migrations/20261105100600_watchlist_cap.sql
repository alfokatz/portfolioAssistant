-- Watchlist: tope también en lo que mira market-watch, y sin carreras al
-- insertar (spec 2026-11-05-diferenciacion-planes-v2 §3.3, revisión de seguridad).

-- Inserciones en paralelo del mismo usuario: se serializan por usuario antes
-- de contar, así no se pasa del tope.
create or replace function public._watchlist_check_limit(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_limit int;
  v_count int;
begin
  if auth.uid() is not null and auth.uid() <> p_user_id then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  perform pg_advisory_xact_lock(hashtext('watchlist:' || p_user_id::text));
  select coalesce(
    (select watchlist from public.plan_limits
      where tier = coalesce(public._effective_tier(p_user_id), 'free')),
    0
  ) into v_limit;
  select count(*) into v_count from public.watchlist_items where user_id = p_user_id;
  if v_count >= v_limit then
    raise exception 'watchlist_limit_reached'
      using errcode = 'P0001',
            detail = json_build_object('limit', v_limit)::text,
            hint = 'Mejorá tu plan para seguir más tickers.';
  end if;
end;
$$;

-- market-watch mira como mucho `plan_limits.watchlist` del plan ACTUAL por
-- usuario (los más viejos primero): quien bajó de plan no sigue gastando
-- cotizaciones de una lista que ya no le corresponde.
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
  with ranked as (
    select
      w.user_id,
      w.symbol,
      w.added_price,
      w.notify,
      row_number() over (partition by w.user_id order by w.created_at, w.id) as rn,
      coalesce((select pl.watchlist from public.plan_limits pl
                 where pl.tier = coalesce(public._effective_tier(w.user_id), 'free')), 0) as lim
    from public.watchlist_items w
  )
  select
    r.user_id,
    r.symbol,
    r.added_price,
    coalesce(np.big_move_sensitivity, 'normal')
  from ranked r
  left join public.notification_preferences np on np.user_id = r.user_id
  where r.rn <= r.lim
    and r.notify
    and exists (select 1 from public.push_devices d where d.user_id = r.user_id)
    and coalesce(np.enabled, true)
    and coalesce(np.big_moves, true)
    and not exists (
      select 1 from public.positions p
       where p.user_id = r.user_id and upper(p.ticker) = r.symbol and p.quantity > 0
    );
$$;

revoke all on function public._watchlist_check_limit(uuid) from public, anon;
grant execute on function public._watchlist_check_limit(uuid) to authenticated, service_role;
revoke all on function public.watchlist_watch_items() from public, anon, authenticated;
grant execute on function public.watchlist_watch_items() to service_role;
