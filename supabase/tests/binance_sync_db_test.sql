-- Test de la migración 20261016000400_binance_sync.sql.
--
-- Corre contra una base con las migraciones aplicadas (supabase start, o un
-- Postgres con los stubs de auth/vault/roles). Cada chequeo que falla corta
-- con una excepción; si termina, imprime BINANCE_DB_TEST_OK.
--
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/binance_sync_db_test.sql
--
-- Todo corre dentro de una transacción que se deshace al final.

begin;

delete from public.binance_keys;
delete from public.binance_connections;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000e1', 'binance@test.local'),
  ('00000000-0000-0000-0000-0000000000e2', 'other@test.local');

insert into public.binance_connections (user_id, status, api_key_hint, connected_at)
values ('00000000-0000-0000-0000-0000000000e1', 'connected', 'ab12', now());

-- ── La edge function guarda la clave y aplica una sincronización ──────────

do $$
declare
  v_res jsonb;
  v_count int;
begin
  perform public.binance_keys_save('00000000-0000-0000-0000-0000000000e1', '{"api_key":"k","api_secret":"s"}');
  if public.binance_keys_read('00000000-0000-0000-0000-0000000000e1') <> '{"api_key":"k","api_secret":"s"}' then
    raise exception 'keys roundtrip';
  end if;
  -- Guardar de nuevo actualiza el mismo secreto.
  perform public.binance_keys_save('00000000-0000-0000-0000-0000000000e1', '{"api_key":"k2","api_secret":"s2"}');
  select count(*) into v_count from vault.secrets where name = 'binance_keys_00000000-0000-0000-0000-0000000000e1';
  if v_count <> 1 then raise exception 'expected one secret, got %', v_count; end if;

  if not public.binance_try_lock('00000000-0000-0000-0000-0000000000e1', 60) then raise exception 'lock'; end if;
  if public.binance_try_lock('00000000-0000-0000-0000-0000000000e1', 60) then raise exception 'double lock'; end if;
  perform public.binance_unlock('00000000-0000-0000-0000-0000000000e1');

  v_res := public.binance_apply_sync(
    '00000000-0000-0000-0000-0000000000e1',
    '[{"id":"10000000-0000-0000-0000-000000000001","external_id":"BTC","ticker":"BTC-USD","quantity":0.5,"purchase_price":40000,"purchase_date":"2024-01-01T00:00:00Z","broker_price":60000},
      {"id":"10000000-0000-0000-0000-000000000002","external_id":"ETH","ticker":"ETH-USD","quantity":2,"purchase_price":2000,"purchase_date":"2024-02-01T00:00:00Z","broker_price":3000}]',
    '{"imported":2}'
  );
  select count(*) into v_count from public.positions where source = 'binance';
  if v_count <> 2 then raise exception 'expected 2 binance rows, got %', v_count; end if;

  -- La foto siguiente ya no trae ETH: se borra; BTC se actualiza.
  v_res := public.binance_apply_sync(
    '00000000-0000-0000-0000-0000000000e1',
    '[{"id":"10000000-0000-0000-0000-000000000099","external_id":"BTC","ticker":"BTC-USD","quantity":0.75,"purchase_price":45000,"purchase_date":"2024-01-01T00:00:00Z","broker_price":61000}]',
    '{"imported":1}'
  );
  if (v_res->>'removed')::int <> 1 then raise exception 'removed %', v_res; end if;
  if (select quantity from public.positions where source = 'binance' and external_id = 'BTC') <> 0.75 then
    raise exception 'BTC not updated';
  end if;
  if (select last_result->>'imported' from public.binance_connections
       where user_id = '00000000-0000-0000-0000-0000000000e1') <> '1' then
    raise exception 'last_result';
  end if;
end $$;

-- ── Desde la app: solo lectura, y solo lo suyo ────────────────────────────

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000e1","role":"authenticated"}';

do $$
begin
  begin
    update public.positions set quantity = 1 where source = 'binance';
    raise exception 'should have failed: update';
  exception when insufficient_privilege then
    if sqlerrm <> 'broker_rows_are_read_only' then raise; end if;
  end;
  begin
    delete from public.positions where source = 'binance';
    raise exception 'should have failed: delete';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.positions (id, user_id, ticker, quantity, purchase_price, purchase_date, source)
    values (gen_random_uuid(), '00000000-0000-0000-0000-0000000000e1', 'X', 1, 1, now(), 'binance');
    raise exception 'should have failed: insert';
  exception when insufficient_privilege then null;
  end;
  -- Las manuales siguen como siempre.
  insert into public.positions (id, user_id, ticker, quantity, purchase_price, purchase_date)
  values (gen_random_uuid(), '00000000-0000-0000-0000-0000000000e1', 'AAPL', 1, 100, now());

  if (select count(*) from public.binance_connections) <> 1 then raise exception 'reads connection'; end if;
  begin
    perform 1 from public.binance_keys;
    raise exception 'should have failed: keys';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.binance_keys_read('00000000-0000-0000-0000-0000000000e1');
    raise exception 'should have failed: keys rpc';
  exception when insufficient_privilege then null;
  end;
  begin
    update public.binance_connections set status = 'connected';
    raise exception 'should have failed: write connection';
  exception when insufficient_privilege then null;
  end;
end $$;

set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000e2","role":"authenticated"}';
do $$
begin
  if exists (select 1 from public.binance_connections) then raise exception 'sees other connection'; end if;
end $$;

-- ── Desconectar ───────────────────────────────────────────────────────────

reset role;

do $$
declare
  v_res jsonb;
begin
  v_res := public.binance_disconnect('00000000-0000-0000-0000-0000000000e1', true);
  if (v_res->>'open')::int <> 1 then raise exception 'disconnect %', v_res; end if;
  if exists (select 1 from public.positions where source = 'binance') then raise exception 'binance rows left'; end if;
  if (select source from public.positions where ticker = 'BTC-USD') <> 'manual' then raise exception 'not kept as manual'; end if;
  if exists (select 1 from public.binance_keys) then raise exception 'keys left'; end if;
  if exists (select 1 from vault.secrets where name like 'binance_keys_%') then raise exception 'secret left'; end if;
  if (select status from public.binance_connections) <> 'disconnected' then raise exception 'status'; end if;
end $$;

select 'BINANCE_DB_TEST_OK' as result;

rollback;
