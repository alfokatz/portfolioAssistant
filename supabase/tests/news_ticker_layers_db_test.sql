-- Test de 20261126100000_news_ticker_layers.sql: mapa símbolo local ->
-- subyacente (RLS cerrada), config de la capa 4, gasto mensual atómico y
-- símbolos a calentar solo de usuarios activos.
--
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/news_ticker_layers_db_test.sql
--
-- Imprime NEWS_TICKER_LAYERS_DB_TEST_OK. Todo dentro de una transacción que se deshace.

begin;

create function pg_temp.check_true(label text, ok boolean) returns void language plpgsql as $$
begin
  if ok is not true then raise exception '%', label; end if;
end;
$$;

-- ── 1. Mapa: ejemplos, constraints y RLS cerrada ────────────────────────────

do $$
begin
  perform pg_temp.check_true('YPFD.BA -> YPF',
    (select underlying = 'YPF' and kind = 'alias' from public.ticker_news_map where ticker = 'YPFD.BA'));
  perform pg_temp.check_true('local sin subyacente',
    (select underlying is null and kind = 'local' from public.ticker_news_map where ticker = 'ALUA.BA'));
  perform pg_temp.check_true('la tabla casi vacía (mecanismo general, sin lista de acciones)',
    (select count(*) <= 10 from public.ticker_news_map));
  perform pg_temp.check_true('RLS activada',
    (select relrowsecurity from pg_class where oid = 'public.ticker_news_map'::regclass));
  perform pg_temp.check_true('sin políticas',
    not exists (select 1 from pg_policies where tablename in ('ticker_news_map', 'news_ticker_search_spend')));
  perform pg_temp.check_true('anon/authenticated sin acceso',
    not has_table_privilege('anon', 'public.ticker_news_map', 'select')
    and not has_table_privilege('authenticated', 'public.ticker_news_map', 'select')
    and not has_table_privilege('authenticated', 'public.news_ticker_search_spend', 'select'));
end $$;

do $$
declare ok boolean := false;
begin
  -- kind local con subyacente, y alias sin subyacente: ambos inválidos.
  begin
    insert into public.ticker_news_map (ticker, underlying, kind) values ('XX.L', 'XX', 'local');
  exception when check_violation then ok := true; end;
  perform pg_temp.check_true('local con subyacente rechazado', ok);
  ok := false;
  begin
    insert into public.ticker_news_map (ticker, underlying, kind) values ('XX.L', null, 'alias');
  exception when check_violation then ok := true; end;
  perform pg_temp.check_true('alias sin subyacente rechazado', ok);
  ok := false;
  begin
    insert into public.ticker_news_map (ticker, underlying, kind) values ('NOSUFFIX', 'X', 'alias');
  exception when check_violation then ok := true; end;
  perform pg_temp.check_true('ticker sin sufijo de bolsa rechazado', ok);
  -- Cualquier mercado vale.
  insert into public.ticker_news_map (ticker, underlying, kind) values ('SHEL.L', 'SHEL', 'alias'), ('XYZ.TO', 'XYZ', 'alias');
end $$;

-- ── 2. Config: defaults agregados, lo cambiado se respeta ───────────────────

do $$
begin
  perform pg_temp.check_true('tope mensual por defecto 20',
    (select (value ->> 'ticker_search_monthly_usd')::numeric = 20 from public.app_config where key = 'daily_brief_costs'));
  perform pg_temp.check_true('umbral de movimiento 2,5',
    (select (value ->> 'ticker_search_min_move_pct')::numeric = 2.5 from public.app_config where key = 'daily_brief_costs'));
  perform pg_temp.check_true('las claves de los digests siguen',
    (select value ? 'pulse_slots_per_day' and value ? 'max_digests_per_run' from public.app_config where key = 'daily_brief_costs'));
end $$;

-- ── 3. Gasto mensual: reserva atómica con tope, ajuste al costo real ────────

do $$
declare
  v_month date := date_trunc('month', now() at time zone 'utc')::date;
begin
  delete from public.news_ticker_search_spend;
  perform pg_temp.check_true('reserva 1 (0.05 de 0.12)', public.ticker_search_budget_reserve(0.12, 0.05));
  perform pg_temp.check_true('reserva 2 (0.10 de 0.12)', public.ticker_search_budget_reserve(0.12, 0.05));
  perform pg_temp.check_true('reserva 3 pasa el tope: rechazada', not public.ticker_search_budget_reserve(0.12, 0.05));
  perform pg_temp.check_true('el rechazo no suma', public.ticker_search_spent_month() = 0.10);
  -- Ajuste: la 1ª costó 0.012 (devuelve 0.038); la 2ª falló sin costo (devuelve 0.05).
  perform public.ticker_search_budget_settle(v_month, 0.05, 0.012);
  perform public.ticker_search_budget_settle(v_month, 0.05, 0);
  perform pg_temp.check_true('gasto real 0.012', public.ticker_search_spent_month() = 0.012);
  perform pg_temp.check_true('solo cuenta la búsqueda con costo',
    (select searches = 1 from public.news_ticker_search_spend where month = v_month));
  -- Con lugar otra vez.
  perform pg_temp.check_true('vuelve a haber lugar', public.ticker_search_budget_reserve(0.12, 0.05));
  -- Tope 0 o inválido: apagado.
  perform pg_temp.check_true('tope 0 = apagado', not public.ticker_search_budget_reserve(0, 0.05));
  perform pg_temp.check_true('tope null = apagado', not public.ticker_search_budget_reserve(null, 0.05));
  -- Nunca negativo.
  perform public.ticker_search_budget_settle(v_month, 99, 0);
  perform pg_temp.check_true('gasto nunca negativo', public.ticker_search_spent_month() = 0);
  -- Otro mes: contador aparte.
  insert into public.news_ticker_search_spend (month, spent_usd) values ('2020-01-01', 19.99);
  perform pg_temp.check_true('el mes pasado no cuenta', public.ticker_search_spent_month() = 0);
  perform pg_temp.check_true('permisos: solo service_role',
    has_function_privilege('service_role', 'public.ticker_search_budget_reserve(numeric, numeric)', 'execute')
    and not has_function_privilege('authenticated', 'public.ticker_search_budget_reserve(numeric, numeric)', 'execute')
    and not has_function_privilege('anon', 'public.ticker_search_budget_settle(date, numeric, numeric)', 'execute'));
end $$;

-- ── 4. Símbolos a calentar: solo usuarios activos ───────────────────────────
-- b1 abrió la app hace 2 días, b2 hace 10, b3 nunca. Los tres, en Buenos Aires.

insert into auth.users (id, email, created_at) values
  ('00000000-0000-0000-0000-0000000d0b01', 'b1@test.local', now()),
  ('00000000-0000-0000-0000-0000000d0b02', 'b2@test.local', now()),
  ('00000000-0000-0000-0000-0000000d0b03', 'b3@test.local', now());

insert into public.positions (id, user_id, ticker, quantity, purchase_price, purchase_date) values
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000d0b01', 'AAPL', 1, 100, now()),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000d0b02', 'MSFT', 1, 100, now()),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000d0b03', 'NVDA', 1, 100, now());

insert into public.push_devices (user_id, token, platform, locale, timezone) values
  ('00000000-0000-0000-0000-0000000d0b01', 'tok-b1-0000000000000000', 'ios', 'es', 'America/Argentina/Buenos_Aires'),
  ('00000000-0000-0000-0000-0000000d0b02', 'tok-b2-0000000000000000', 'ios', 'es', 'America/Argentina/Buenos_Aires'),
  ('00000000-0000-0000-0000-0000000d0b03', 'tok-b3-0000000000000000', 'ios', 'es', 'America/Argentina/Buenos_Aires');

insert into public.product_events (user_id, name, created_at) values
  ('00000000-0000-0000-0000-0000000d0b01', 'app_opened', now() - interval '2 days'),
  ('00000000-0000-0000-0000-0000000d0b02', 'app_opened', now() - interval '10 days'),
  -- Otro evento reciente no cuenta como "abrió la app".
  ('00000000-0000-0000-0000-0000000d0b03', 'diagnosis_seen', now() - interval '1 hour');

-- Prende el interruptor del brief para los tres (y lo deja como estaba al rollback).
update public.app_config
   set value = value || '{"percent": 0, "users": ["00000000-0000-0000-0000-0000000d0b01", "00000000-0000-0000-0000-0000000d0b02", "00000000-0000-0000-0000-0000000d0b03"]}'::jsonb
 where key = 'daily_brief';

do $$
declare syms text[];
begin
  select array_agg(symbol order by symbol) into syms
    from public.daily_brief_warm_symbols_active(array['America/Argentina/Buenos_Aires'], 200, 7);
  perform pg_temp.check_true('solo los activos de 7 días (AAPL): ' || coalesce(syms::text, 'null'), syms = array['AAPL']);
  select array_agg(symbol order by symbol) into syms
    from public.daily_brief_warm_symbols_active(array['America/Argentina/Buenos_Aires'], 200, 30);
  perform pg_temp.check_true('con 30 días suma a b2 (AAPL, MSFT)', syms = array['AAPL', 'MSFT']);
  perform pg_temp.check_true('la función vieja no cambió (los 3)',
    (select count(*) = 3 from public.daily_brief_warm_symbols(array['America/Argentina/Buenos_Aires'], 200)));
  perform pg_temp.check_true('permisos: solo service_role',
    has_function_privilege('service_role', 'public.daily_brief_warm_symbols_active(text[], int, int)', 'execute')
    and not has_function_privilege('authenticated', 'public.daily_brief_warm_symbols_active(text[], int, int)', 'execute'));
end $$;

rollback;
select 'NEWS_TICKER_LAYERS_DB_TEST_OK' as result;
