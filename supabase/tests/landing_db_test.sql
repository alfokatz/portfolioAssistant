-- Test de la landing sin lista de espera
-- (20261113000100_landing_store_clicks.sql; repo porty-web).
--
-- Corre contra una base con las migraciones aplicadas (supabase start, o un
-- Postgres con los roles anon/authenticated/service_role). Cada chequeo que
-- falla corta con una excepción; si termina, imprime LANDING_DB_TEST_OK.
--
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/landing_db_test.sql
--
-- Todo corre dentro de una transacción que se deshace al final.

begin;

-- ── La lista de espera ya no existe ───────────────────────────────────────
do $$
begin
  if to_regclass('public.waitlist') is not null then
    raise exception 'waitlist sigue existiendo';
  end if;
  if exists (select 1 from pg_proc where proname in ('landing_signup', '_landing_ref_code')
             and pronamespace = 'public'::regnamespace) then
    raise exception 'quedaron funciones de la lista de espera';
  end if;
end $$;

delete from public.landing_events;
delete from public.landing_rate_limits;

-- ── El cliente anónimo y el logueado no ven ni tocan nada ─────────────────
set local role anon;

do $$
begin
  begin
    insert into public.landing_events (anon_id, event) values ('anon-0001', 'page_view');
    raise exception 'RLS: anon pudo escribir landing_events';
  exception when insufficient_privilege then null;
  end;
  begin
    perform 1 from public.landing_stats;
    raise exception 'RLS: anon pudo leer landing_stats';
  exception when insufficient_privilege then null;
  end;
  begin
    perform 1 from public.landing_sources;
    raise exception 'RLS: anon pudo leer landing_sources';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.landing_rate_hit('h', 'event', 1);
    raise exception 'RLS: anon pudo llamar landing_rate_hit';
  exception when insufficient_privilege then null;
  end;
end $$;

reset role;
set local role authenticated;

do $$
begin
  begin
    perform 1 from public.landing_events;
    raise exception 'RLS: authenticated pudo leer landing_events';
  exception when insufficient_privilege then null;
  end;
end $$;

reset role;

-- ── Como la edge function ─────────────────────────────────────────────────
set local role service_role;

-- Reglas de la tabla.
do $$
begin
  begin
    insert into public.landing_events (anon_id, event) values ('anon-x-0001', 'store_click');
    raise exception 'store_click sin store fue aceptado';
  exception when check_violation then null;
  end;
  begin
    insert into public.landing_events (anon_id, event, store) values ('anon-x-0001', 'page_view', 'ios');
    raise exception 'page_view con store fue aceptado';
  exception when check_violation then null;
  end;
  begin
    insert into public.landing_events (anon_id, event) values ('anon-x-0001', 'signup');
    raise exception 'el evento signup sigue aceptado';
  exception when check_violation then null;
  end;
  begin
    insert into public.landing_events (anon_id, event, country) values ('anon-x-0001', 'page_view', 'ar');
    raise exception 'país en minúsculas fue aceptado';
  exception when check_violation then null;
  end;
end $$;

-- ── Rate limit ────────────────────────────────────────────────────────────
do $$
begin
  if not public.landing_rate_hit('hash-1', 'event', 2) then raise exception 'rate: 1º rechazado'; end if;
  if not public.landing_rate_hit('hash-1', 'event', 2) then raise exception 'rate: 2º rechazado'; end if;
  if public.landing_rate_hit('hash-1', 'event', 2) then raise exception 'rate: 3º aceptado'; end if;
  if not public.landing_rate_hit('hash-2', 'event', 2) then raise exception 'rate: otra IP rechazada'; end if;
end $$;

-- ── Métricas ──────────────────────────────────────────────────────────────
-- Variante A: 4 visitantes (uno vuelve), 2 tocan una tienda (uno dos veces).
-- Variante B: 2 visitantes, 1 toca Android. Sin variante: 1 visitante.
insert into public.landing_events (anon_id, variant, event, path, utm_source, utm_campaign) values
  ('anon-ana0-0001', 'a', 'page_view', '/', 'tiktok', 'lanzamiento'),
  ('anon-ana0-0001', 'a', 'page_view', '/precios', 'tiktok', 'lanzamiento'),
  ('anon-beto-0001', 'a', 'page_view', '/', 'tiktok', 'lanzamiento'),
  ('anon-caro-0001', 'a', 'page_view', '/', null, null),
  ('anon-dani-0001', 'a', 'page_view', '/', 'meta', 'retargeting'),
  ('anon-eli0-0001', 'b', 'page_view', '/', 'meta', 'retargeting'),
  ('anon-fer0-0001', 'b', 'page_view', '/', null, null),
  ('anon-gus0-0001', null, 'page_view', '/', null, null);
insert into public.landing_events (anon_id, variant, event, store, path, utm_source, utm_campaign) values
  ('anon-ana0-0001', 'a', 'store_click', 'ios', '/', 'tiktok', 'lanzamiento'),
  ('anon-ana0-0001', 'a', 'store_click', 'ios', '/precios', 'tiktok', 'lanzamiento'),
  ('anon-dani-0001', 'a', 'store_click', 'android', '/', 'meta', 'retargeting'),
  ('anon-eli0-0001', 'b', 'store_click', 'android', '/', 'meta', 'retargeting');
insert into public.landing_events (anon_id, variant, event, plan, path) values
  ('anon-ana0-0001', 'a', 'pricing_view', null, '/precios'),
  ('anon-ana0-0001', 'a', 'plan_click', 'gold', '/precios');

do $$
declare
  s record;
begin
  select * into s from public.landing_stats where day is null and variant = 'a';
  if s.unique_visitors <> 4 or s.store_clickers <> 2 or s.store_ctr <> 0.5
     or s.clicks_ios <> 2 or s.clicks_android <> 1 then
    raise exception 'stats A acumulado: %', row_to_json(s);
  end if;
  if s.pricing_visitors <> 1 or s.clicks_gold <> 1 or s.clicks_premium <> 0 then
    raise exception 'stats A planes: %', row_to_json(s);
  end if;

  select * into s from public.landing_stats where day is null and variant = 'b';
  if s.unique_visitors <> 2 or s.store_clickers <> 1 or s.store_ctr <> 0.5 or s.clicks_android <> 1 then
    raise exception 'stats B acumulado: %', row_to_json(s);
  end if;

  select * into s from public.landing_stats where day is null and variant = '-';
  if s.unique_visitors <> 1 or s.store_clickers <> 0 or s.store_ctr <> 0 then
    raise exception 'stats sin variante: %', row_to_json(s);
  end if;

  select * into s from public.landing_stats
  where day = (now() at time zone 'America/Argentina/Buenos_Aires')::date and variant = 'a';
  if s.unique_visitors <> 4 then raise exception 'stats A por día: %', row_to_json(s); end if;

  select * into s from public.landing_sources where utm_source = 'tiktok' and utm_campaign = 'lanzamiento';
  if s.unique_visitors <> 2 or s.store_clickers <> 1 or s.store_ctr <> 0.5 then
    raise exception 'sources tiktok: %', row_to_json(s);
  end if;

  select * into s from public.landing_sources where utm_source = 'meta';
  if s.unique_visitors <> 2 or s.store_clickers <> 2 or s.store_ctr <> 1 then
    raise exception 'sources meta: %', row_to_json(s);
  end if;

  select * into s from public.landing_sources where utm_source = '(directo)';
  if s.unique_visitors <> 3 or s.store_clickers <> 0 then
    raise exception 'sources directo: %', row_to_json(s);
  end if;
end $$;

reset role;

select 'LANDING_DB_TEST_OK';

rollback;
