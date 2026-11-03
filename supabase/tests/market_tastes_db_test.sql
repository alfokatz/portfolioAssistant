-- Test de 20261103130000_market_tastes.sql (Free prueba Premium).
--
-- Corre contra una base con las migraciones aplicadas (supabase start, o un
-- Postgres con los stubs de auth/vault/roles). Si termina, imprime
-- MARKET_TASTES_DB_TEST_OK.
--
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/market_tastes_db_test.sql
--
-- Todo corre dentro de una transacción que se deshace al final.

begin;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000d1', 'free@test.local'),
  ('00000000-0000-0000-0000-0000000000d2', 'premium@test.local'),
  ('00000000-0000-0000-0000-0000000000d3', 'gold@test.local'),
  ('00000000-0000-0000-0000-0000000000d4', 'goldvencido@test.local'),
  ('00000000-0000-0000-0000-0000000000d5', 'otro@test.local');
insert into public.user_subscriptions (user_id, tier, status) values
  ('00000000-0000-0000-0000-0000000000d1', 'free', 'active'),
  ('00000000-0000-0000-0000-0000000000d2', 'premium', 'active'),
  ('00000000-0000-0000-0000-0000000000d3', 'gold', 'active'),
  ('00000000-0000-0000-0000-0000000000d4', 'gold', 'expired'),
  ('00000000-0000-0000-0000-0000000000d5', 'free', 'active')
on conflict (user_id) do update set tier = excluded.tier, status = excluded.status;

create function pg_temp.as_user(u text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
end;
$$;

-- 6. Límites por plan.
do $$
begin
  if (select array_agg(market_tastes_per_month order by tier) from public.plan_limits) <> array[3, 0, 0] then
    raise exception 'plan_limits: %', (select array_agg(tier || '=' || market_tastes_per_month) from public.plan_limits);
  end if;
end $$;

set local role authenticated;

-- 1. Flag apagado.
do $$
declare r jsonb;
begin
  perform pg_temp.as_user('00000000-0000-0000-0000-0000000000d1');
  r := public.market_taste_status();
  if (r->>'enabled')::boolean or r->>'limit' <> '0' then raise exception 'status apagado: %', r; end if;
  r := public.consume_market_taste('turn-apagado-0001', array['NVDA']);
  if r->>'reason' <> 'disabled' then raise exception 'consume apagado: %', r; end if;
end $$;
reset role;
do $$
begin
  if exists (select 1 from public.market_tastes) then raise exception 'insertó con el flag apagado'; end if;
end $$;

update public.app_config set value = '{"percent":0,"users":["00000000-0000-0000-0000-0000000000d1","00000000-0000-0000-0000-0000000000d2","00000000-0000-0000-0000-0000000000d3","00000000-0000-0000-0000-0000000000d4","00000000-0000-0000-0000-0000000000d5"]}'
 where key = 'market_taste';

set local role authenticated;

-- 2. Free: 3 turnos, el 4.º agotado, repetir uno no gasta.
do $$
declare r jsonb;
begin
  perform pg_temp.as_user('00000000-0000-0000-0000-0000000000d1');
  r := public.market_taste_status();
  if r <> jsonb_build_object('enabled', true, 'limit', 3, 'used', 0, 'remaining', 3, 'month', public._current_usage_month()) then
    raise exception 'status inicial: %', r;
  end if;
  r := public.consume_market_taste('turn-aaaa-0001', array['nvda']);
  if r <> '{"ok":true,"remaining":2,"limit":3,"reused":false}'::jsonb then raise exception '1: %', r; end if;
  r := public.consume_market_taste('turn-aaaa-0002', array['AMD', 'brk.b']);
  if (r->>'remaining') <> '1' then raise exception '2: %', r; end if;
  r := public.consume_market_taste('turn-aaaa-0003', array['TSLA']);
  if (r->>'remaining') <> '0' then raise exception '3: %', r; end if;
  r := public.consume_market_taste('turn-aaaa-0004', array['META']);
  if r <> '{"ok":false,"reason":"exhausted","remaining":0,"limit":3}'::jsonb then raise exception '4: %', r; end if;
  r := public.consume_market_taste('turn-aaaa-0002', array['AMD']);
  if r <> '{"ok":true,"remaining":0,"limit":3,"reused":true}'::jsonb then raise exception 'reused: %', r; end if;
  if (select count(*) from public.market_tastes) <> 3 then raise exception 'filas visibles'; end if;
  if public.market_taste_status()->>'remaining' <> '0' then raise exception 'status final'; end if;
end $$;

-- 3. Premium, Gold; Gold vencido cuenta como Free.
do $$
declare r jsonb;
begin
  perform pg_temp.as_user('00000000-0000-0000-0000-0000000000d2');
  r := public.consume_market_taste('turn-bbbb-0001', array['NVDA']);
  if r->>'reason' <> 'not_eligible' then raise exception 'premium: %', r; end if;
  if (public.market_taste_status()->>'enabled')::boolean then raise exception 'status premium'; end if;
  perform pg_temp.as_user('00000000-0000-0000-0000-0000000000d3');
  r := public.consume_market_taste('turn-bbbb-0002', array['NVDA']);
  if r->>'reason' <> 'not_eligible' then raise exception 'gold: %', r; end if;
  perform pg_temp.as_user('00000000-0000-0000-0000-0000000000d4');
  r := public.consume_market_taste('turn-bbbb-0003', array['NVDA']);
  if (r->>'ok')::boolean is not true then raise exception 'gold vencido: %', r; end if;
end $$;

-- 5. Entradas inválidas; sin sesión; RLS.
do $$
declare r jsonb; bad text;
begin
  perform pg_temp.as_user('00000000-0000-0000-0000-0000000000d5');
  foreach bad in array array['corto', 'tiene espacios aqui', repeat('a', 65)] loop
    r := public.consume_market_taste(bad, array['NVDA']);
    if r->>'reason' <> 'invalid_turn_id' then raise exception 'turn %: %', bad, r; end if;
  end loop;
  if public.consume_market_taste(null, array['NVDA'])->>'reason' <> 'invalid_turn_id' then raise exception 'turn null'; end if;
  if public.consume_market_taste('turn-cccc-0001', array[]::text[])->>'reason' <> 'invalid_tickers' then raise exception 'vacío'; end if;
  if public.consume_market_taste('turn-cccc-0001', array['A','B','C','D','E','F','G'])->>'reason' <> 'invalid_tickers' then raise exception '7'; end if;
  if public.consume_market_taste('turn-cccc-0001', array['no valido!'])->>'reason' <> 'invalid_tickers' then raise exception 'chars'; end if;
  if public.consume_market_taste('turn-cccc-0001', array[repeat('A', 13)])->>'reason' <> 'invalid_tickers' then raise exception 'largo'; end if;
  if public.consume_market_taste('turn-cccc-0001', array[null]::text[])->>'reason' <> 'invalid_tickers' then raise exception 'null'; end if;
  if public.consume_market_taste('turn-cccc-0001', null)->>'reason' <> 'invalid_tickers' then raise exception 'tickers null'; end if;
  if (select count(*) from public.market_tastes) <> 0 then raise exception 'RLS: d5 ve filas ajenas'; end if;
end $$;

do $$
begin
  perform set_config('request.jwt.claims', '', true);
  begin
    perform public.consume_market_taste('turn-dddd-0001', array['NVDA']);
    raise exception 'sin sesión no tiró';
  exception when others then
    if sqlerrm <> 'not_authenticated' then raise; end if;
  end;
end $$;
reset role;

-- 4. Mes nuevo: una fila de otro mes no cuenta.
update public.market_tastes set month = '2000-01' where user_id = '00000000-0000-0000-0000-0000000000d1';
set local role authenticated;
do $$
begin
  perform pg_temp.as_user('00000000-0000-0000-0000-0000000000d1');
  if public.market_taste_status()->>'used' <> '0' then raise exception 'mes viejo cuenta'; end if;
  if (public.consume_market_taste('turn-eeee-0001', array['NVDA'])->>'ok')::boolean is not true then
    raise exception 'mes nuevo no deja consumir';
  end if;
end $$;
reset role;

-- La tabla no es escribible desde la app.
set local role authenticated;
do $$
begin
  begin
    insert into public.market_tastes (user_id, turn_id, month, tickers)
    values ('00000000-0000-0000-0000-0000000000d1', 'turn-ffff-0001', '2026-11', array['X']);
    raise exception 'insert directo permitido';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

select 'MARKET_TASTES_DB_TEST_OK' as result;
rollback;
