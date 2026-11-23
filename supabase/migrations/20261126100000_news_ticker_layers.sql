-- Noticias por ticker "en capas" de bajo costo (brief diario y feed).
-- Decisión: docs/business/research/2026-11-23-noticias-sin-presupuesto.md.
-- Idempotente y aditivo: no cambia nada de lo que ya existe.
--
-- 1. `ticker_news_map`: excepciones "símbolo local -> subyacente" para buscar
--    noticias de una empresa cuyo símbolo local (`XXX.BA`, `XXX.L`, `XXX.MX`,
--    `XXX.TO`...) no se resuelve solo. El caso general NO necesita filas: el
--    código quita el sufijo de bolsa y lo acepta si el símbolo base existe en
--    EE. UU. (`sec_ticker_cik`). La tabla solo corrige lo que la heurística no
--    acierta (símbolo distinto: YPFD.BA -> YPF) o marca `kind = 'local'` (sin
--    subyacente: no usar la heurística). Mecanismo para cualquier mercado; las
--    filas de abajo son solo ejemplos.
-- 2. `news_ticker_search_spend` + RPC `ticker_search_budget_reserve/settle`:
--    gasto mensual (UTC) de la búsqueda web por ticker (capa 4), con tope.
--    Reserva ANTES de buscar (atómica: dos pedidos no pasan el tope juntos) y
--    ajusta al costo real después.
-- 3. `app_config.daily_brief_costs`: claves de la capa 4 (solo se agregan las
--    que faltan; si el usuario ya cambió alguna, se respeta).
-- 4. `daily_brief_warm_symbols_active`: como `daily_brief_warm_symbols` pero
--    solo de usuarios que abrieron la app (`product_events.app_opened`) en los
--    últimos N días. La usa `news-warm`; la anterior queda como estaba.
--
-- RLS cerrada en las tablas nuevas: sin políticas, solo la service role.

-- ---------------------------------------------------------------------------
-- 1. Mapeo CEDEAR / acción local -> subyacente de EE. UU.
-- ---------------------------------------------------------------------------

create table if not exists public.ticker_news_map (
  -- Símbolo local con sufijo de bolsa, en mayúsculas.
  ticker text primary key check (ticker ~ '^[A-Z0-9]{1,10}\.[A-Z]{1,3}$'),
  -- Símbolo de EE. UU. (formato Yahoo/SEC: BRK-B). null = sin subyacente.
  underlying text check (underlying ~ '^[A-Z]{1,5}([.-][A-Z])?$'),
  kind text not null check (kind in ('alias', 'local')),
  updated_at timestamptz not null default now(),
  check ((kind = 'local') = (underlying is null))
);

alter table public.ticker_news_map enable row level security;
revoke all on public.ticker_news_map from public, anon, authenticated;
grant select, insert, update, delete on public.ticker_news_map to service_role;

-- Ejemplos (el resto lo resuelve la heurística).
insert into public.ticker_news_map (ticker, underlying, kind) values
  ('YPFD.BA', 'YPF', 'alias'),
  ('BRKB.BA', 'BRK-B', 'alias'),
  ('ALUA.BA', null, 'local')
on conflict (ticker) do nothing;

-- ---------------------------------------------------------------------------
-- 2. Gasto mensual de la búsqueda web por ticker (capa 4)
-- ---------------------------------------------------------------------------

create table if not exists public.news_ticker_search_spend (
  -- Primer día del mes UTC.
  month date primary key,
  spent_usd numeric(12, 6) not null default 0 check (spent_usd >= 0),
  searches int not null default 0 check (searches >= 0),
  updated_at timestamptz not null default now()
);

alter table public.news_ticker_search_spend enable row level security;
revoke all on public.news_ticker_search_spend from public, anon, authenticated;
grant select, insert, update, delete on public.news_ticker_search_spend to service_role;

-- Reserva [p_reserve_usd] del mes si con eso no se pasa de [p_cap_usd].
-- true = reservado (hay que llamar a settle al terminar); false = tope alcanzado.
-- Un `update ... where spent + reserva <= tope` es atómico: dos pedidos a la
-- vez no pueden pasarse del tope.
create or replace function public.ticker_search_budget_reserve(p_cap_usd numeric, p_reserve_usd numeric)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_month date := date_trunc('month', now() at time zone 'utc')::date;
  v_rows int;
begin
  if p_cap_usd is null or p_cap_usd <= 0 or p_reserve_usd is null or p_reserve_usd < 0 then
    return false;
  end if;
  insert into public.news_ticker_search_spend (month) values (v_month) on conflict (month) do nothing;
  update public.news_ticker_search_spend
     set spent_usd = spent_usd + p_reserve_usd, updated_at = now()
   where month = v_month and spent_usd + p_reserve_usd <= p_cap_usd;
  get diagnostics v_rows = row_count;
  return v_rows = 1;
end;
$$;

-- Cambia la reserva por el costo real (0 = se devuelve entera). `searches` cuenta
-- las búsquedas con costo real > 0.
create or replace function public.ticker_search_budget_settle(
  p_month date,
  p_reserved_usd numeric,
  p_actual_usd numeric
)
returns void
language sql
security definer
set search_path = public
as $$
  update public.news_ticker_search_spend
     set spent_usd = greatest(0, spent_usd - greatest(coalesce(p_reserved_usd, 0), 0) + greatest(coalesce(p_actual_usd, 0), 0)),
         searches = searches + case when coalesce(p_actual_usd, 0) > 0 then 1 else 0 end,
         updated_at = now()
   where month = date_trunc('month', p_month)::date;
$$;

-- Gasto del mes UTC en curso (para el log y los tests); 0 si no hay fila.
create or replace function public.ticker_search_spent_month()
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select spent_usd from public.news_ticker_search_spend
      where month = date_trunc('month', now() at time zone 'utc')::date),
    0
  );
$$;

revoke all on function public.ticker_search_budget_reserve(numeric, numeric) from public, anon, authenticated;
revoke all on function public.ticker_search_budget_settle(date, numeric, numeric) from public, anon, authenticated;
revoke all on function public.ticker_search_spent_month() from public, anon, authenticated;
grant execute on function
  public.ticker_search_budget_reserve(numeric, numeric),
  public.ticker_search_budget_settle(date, numeric, numeric),
  public.ticker_search_spent_month()
to service_role;

-- ---------------------------------------------------------------------------
-- 3. Configuración de la capa 4 en app_config.daily_brief_costs
-- ---------------------------------------------------------------------------

-- ticker_search_monthly_usd: tope mensual (UTC) en US$; 0 apaga la capa 4.
-- ticker_search_min_move_pct: |variación del día| mínima para buscar.
-- ticker_search_reserve_usd: lo que se reserva por búsqueda antes de hacerla.
-- ticker_search_max_per_request: búsquedas nuevas que puede disparar un pedido.
-- Las claves que ya existen (de una corrida anterior o cambiadas a mano) ganan.
insert into public.app_config (key, value)
values (
  'daily_brief_costs',
  '{"pulse_slots_per_day": 1, "topic_slots_per_day": 1, "max_digests_per_run": 24}'::jsonb
)
on conflict (key) do nothing;

update public.app_config
   set value = '{"ticker_search_monthly_usd": 20, "ticker_search_min_move_pct": 2.5, "ticker_search_reserve_usd": 0.05, "ticker_search_max_per_request": 3}'::jsonb
               || value,
       updated_at = now()
 where key = 'daily_brief_costs'
   and jsonb_typeof(value) = 'object'
   and not (value ?& array['ticker_search_monthly_usd', 'ticker_search_min_move_pct', 'ticker_search_reserve_usd', 'ticker_search_max_per_request']);

-- ---------------------------------------------------------------------------
-- 4. Símbolos a calentar: solo de usuarios activos
-- ---------------------------------------------------------------------------

-- Como `daily_brief_warm_symbols` (misma lógica: dispositivo más reciente en
-- alguna de [p_timezones], interruptor prendido), pero solo cuenta usuarios que
-- abrieron la app (`product_events.name = 'app_opened'`) en los últimos
-- [p_active_days] días. Sin user_id en el resultado.
create or replace function public.daily_brief_warm_symbols_active(
  p_timezones text[],
  p_limit int default 200,
  p_active_days int default 7
)
returns table (symbol text, holders int)
language sql
stable
security definer
set search_path = public
as $$
  with latest as (
    select distinct on (d.user_id) d.user_id, d.timezone
      from public.push_devices d
     order by d.user_id, d.last_seen_at desc
  )
  select upper(p.ticker) as symbol, count(distinct p.user_id)::int as holders
    from latest l
    join public.positions p on p.user_id = l.user_id and p.quantity > 0
   where l.timezone = any (p_timezones)
     and public._daily_brief_on(l.user_id)
     and exists (
       select 1 from public.product_events e
        where e.user_id = l.user_id
          and e.name = 'app_opened'
          and e.created_at >= now() - make_interval(days => least(greatest(coalesce(p_active_days, 7), 1), 90))
     )
   group by upper(p.ticker)
   order by holders desc, symbol
   limit least(greatest(coalesce(p_limit, 200), 1), 500);
$$;

revoke all on function public.daily_brief_warm_symbols_active(text[], int, int) from public, anon, authenticated;
grant execute on function public.daily_brief_warm_symbols_active(text[], int, int) to service_role;
