-- Lista de seguimiento (F4 de
-- docs/superpowers/plans/2026-10-16-porty-siguiente-nivel.md).
--
-- - `watchlist_items`: tickers que el usuario sigue sin tenerlos. Guarda el
--   precio al agregarlo para mostrar "desde que la agregaste".
-- - Tope por plan en `plan_limits.watchlist` (Free 0: precios de lo que no
--   tiene son de Premium; Premium 30; Gold 100). Lo controla un trigger:
--   la app recibe `watchlist_limit_reached` y muestra el paywall.
-- - `market-watch` lee lo que hay que mirar con `watchlist_watch_items` y
--   encola `watchlist_move` cuando algo se mueve fuerte.

alter table public.plan_limits
  add column if not exists watchlist int not null default 0 check (watchlist >= 0);

update public.plan_limits set watchlist = case tier
  when 'free' then 0
  when 'premium' then 30
  when 'gold' then 100
end
where watchlist = 0;

create table if not exists public.watchlist_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  symbol text not null check (symbol ~ '^[A-Z0-9.\-^=]{1,15}$'),
  -- Precio cuando lo agregó (para "desde que la agregaste"). Null si no se
  -- consiguió cotización en ese momento.
  added_price numeric check (added_price is null or added_price > 0),
  -- Avisar si se mueve fuerte en el día.
  notify boolean not null default true,
  created_at timestamptz not null default now(),
  unique (user_id, symbol)
);

create index if not exists watchlist_items_user_idx on public.watchlist_items (user_id, created_at desc);

alter table public.watchlist_items enable row level security;

drop policy if exists "watchlist_items own" on public.watchlist_items;
create policy "watchlist_items own" on public.watchlist_items
  for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

revoke all on public.watchlist_items from public, anon, authenticated;
grant select, insert, update, delete on public.watchlist_items to authenticated;
grant select, insert, update, delete on public.watchlist_items to service_role;

-- Corta con `watchlist_limit_reached` si [p_user_id] ya tiene el tope de su
-- plan. Security definer para leer el plan, pero solo para uno mismo.
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

-- Desde la app: el símbolo en mayúsculas, el tope al agregar, y al editar
-- solo se cambia `notify`. Sin security definer: `current_user` tiene que
-- ser el rol del pedido.
create or replace function public._watchlist_guard()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.symbol := upper(trim(new.symbol));
  if current_user in ('anon', 'authenticated') then
    if tg_op = 'INSERT' then
      new.created_at := now();
      perform public._watchlist_check_limit(new.user_id);
    else
      new.user_id := old.user_id;
      new.symbol := old.symbol;
      new.added_price := old.added_price;
      new.created_at := old.created_at;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists watchlist_guard on public.watchlist_items;
create trigger watchlist_guard
  before insert or update on public.watchlist_items
  for each row execute function public._watchlist_guard();

-- Lo que `market-watch` mira: los tickers de las listas con avisos
-- prendidos, de Premium o Gold con al menos un dispositivo y movimientos
-- fuertes prendidos. Lo que además tiene en cartera no va: ya lo cubre el
-- aviso de la cartera.
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
    and coalesce(public._effective_tier(w.user_id), 'free') in ('premium', 'gold')
    and not exists (
      select 1 from public.positions p
       where p.user_id = w.user_id and upper(p.ticker) = w.symbol and p.quantity > 0
    );
$$;

revoke all on function public._watchlist_check_limit(uuid) from public, anon;
grant execute on function public._watchlist_check_limit(uuid) to authenticated, service_role;
revoke all on function public._watchlist_guard() from public, anon, authenticated;
revoke all on function public.watchlist_watch_items() from public, anon, authenticated;
grant execute on function public.watchlist_watch_items() to service_role;
