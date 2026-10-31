-- Test de la migración 20261031000000_snaptrade_sync.sql.
--
-- Corre contra una base con las migraciones aplicadas (supabase start, o un
-- Postgres con los stubs de auth/vault/roles). Cada chequeo que falla corta
-- con una excepción; si termina, imprime SNAPTRADE_DB_TEST_OK.
--
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/snaptrade_sync_db_test.sql
--
-- Todo corre dentro de una transacción que se deshace al final.

begin;

delete from public.snaptrade_users;
delete from public.snaptrade_connections;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000f1', 'snaptrade@test.local'),
  ('00000000-0000-0000-0000-0000000000f2', 'other@test.local');

insert into public.snaptrade_connections (user_id) values ('00000000-0000-0000-0000-0000000000f1');

-- ── La edge function guarda el usuario de SnapTrade y aplica una sincronización ──

do $$
declare
  v_res jsonb;
  v_count int;
  v_date timestamptz;
begin
  if (select status from public.snaptrade_connections) <> 'pending' then raise exception 'starts pending'; end if;

  perform public.snaptrade_secret_save('00000000-0000-0000-0000-0000000000f1', '{"user_id":"u","user_secret":"s"}');
  if public.snaptrade_secret_read('00000000-0000-0000-0000-0000000000f1') <> '{"user_id":"u","user_secret":"s"}' then
    raise exception 'secret roundtrip';
  end if;
  perform public.snaptrade_secret_save('00000000-0000-0000-0000-0000000000f1', '{"user_id":"u2","user_secret":"s2"}');
  select count(*) into v_count from vault.secrets where name = 'snaptrade_user_00000000-0000-0000-0000-0000000000f1';
  if v_count <> 1 then raise exception 'expected one secret, got %', v_count; end if;

  if not public.snaptrade_try_lock('00000000-0000-0000-0000-0000000000f1', 60) then raise exception 'lock'; end if;
  if public.snaptrade_try_lock('00000000-0000-0000-0000-0000000000f1', 60) then raise exception 'double lock'; end if;
  perform public.snaptrade_unlock('00000000-0000-0000-0000-0000000000f1');

  -- Cupo diario de actualizaciones manuales.
  if not public.snaptrade_take_refresh('00000000-0000-0000-0000-0000000000f1', 2) then raise exception 'refresh 1'; end if;
  if not public.snaptrade_take_refresh('00000000-0000-0000-0000-0000000000f1', 2) then raise exception 'refresh 2'; end if;
  if public.snaptrade_take_refresh('00000000-0000-0000-0000-0000000000f1', 2) then raise exception 'refresh over limit'; end if;
  -- Al día siguiente vuelve a haber.
  update public.snaptrade_connections set refresh_day = current_date - 1;
  if not public.snaptrade_take_refresh('00000000-0000-0000-0000-0000000000f1', 2) then raise exception 'refresh next day'; end if;

  v_res := public.snaptrade_apply_sync(
    '00000000-0000-0000-0000-0000000000f1',
    '[{"id":"20000000-0000-0000-0000-000000000001","external_id":"acc:AAPL","ticker":"AAPL","quantity":10,"purchase_price":130,"purchase_date":"2026-10-01T00:00:00Z","broker_price":200},
      {"id":"20000000-0000-0000-0000-000000000002","external_id":"acc:VOO","ticker":"VOO","quantity":2,"purchase_price":500,"purchase_date":"2026-10-01T00:00:00Z","broker_price":500}]',
    '[{"id":"auth-1","name":"Interactive Brokers","slug":"IBKR","disabled":false,"imported":true}]',
    '{"imported":2}'
  );
  select count(*) into v_count from public.positions where source = 'snaptrade';
  if v_count <> 2 then raise exception 'expected 2 snaptrade rows, got %', v_count; end if;
  if (select status from public.snaptrade_connections) <> 'connected' then raise exception 'connected'; end if;
  if (select connected_at from public.snaptrade_connections) is null then raise exception 'connected_at'; end if;

  -- La foto siguiente ya no trae VOO: se borra; AAPL se actualiza y
  -- conserva la fecha de la primera vez.
  v_res := public.snaptrade_apply_sync(
    '00000000-0000-0000-0000-0000000000f1',
    '[{"id":"20000000-0000-0000-0000-000000000099","external_id":"acc:AAPL","ticker":"AAPL","quantity":12,"purchase_price":135,"purchase_date":"2026-10-31T00:00:00Z","broker_price":210}]',
    '[{"id":"auth-1","name":"Interactive Brokers","slug":"IBKR","disabled":false,"imported":true}]',
    '{"imported":1}'
  );
  if (v_res->>'removed')::int <> 1 then raise exception 'removed %', v_res; end if;
  select purchase_date into v_date from public.positions where source = 'snaptrade' and external_id = 'acc:AAPL';
  if v_date <> '2026-10-01T00:00:00Z'::timestamptz then raise exception 'purchase_date moved: %', v_date; end if;
  if (select quantity from public.positions where source = 'snaptrade' and external_id = 'acc:AAPL') <> 12 then
    raise exception 'AAPL not updated';
  end if;
  if (select (brokerages->0->>'name') from public.snaptrade_connections) <> 'Interactive Brokers' then
    raise exception 'brokerages';
  end if;

  -- Sin brókers vuelve a pending.
  perform public.snaptrade_apply_sync('00000000-0000-0000-0000-0000000000f1',
    '[{"id":"20000000-0000-0000-0000-000000000099","external_id":"acc:AAPL","ticker":"AAPL","quantity":12,"purchase_price":135,"purchase_date":"2026-10-31T00:00:00Z","broker_price":210}]',
    '[]', '{"imported":1}');
  if (select status from public.snaptrade_connections) <> 'pending' then raise exception 'pending without brokers'; end if;
end $$;

-- ── Lo que ve y puede hacer la app ──────────────────────────────────────────

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000f1","role":"authenticated"}';

do $$
begin
  begin
    update public.positions set quantity = 1 where source = 'snaptrade';
    raise exception 'should have failed: update';
  exception when insufficient_privilege then
    if sqlerrm <> 'broker_rows_are_read_only' then raise; end if;
  end;
  begin
    insert into public.positions (id, user_id, ticker, quantity, purchase_price, purchase_date, source)
    values (gen_random_uuid(), '00000000-0000-0000-0000-0000000000f1', 'X', 1, 1, now(), 'snaptrade');
    raise exception 'should have failed: insert';
  exception when insufficient_privilege then null;
  end;

  if (select count(*) from public.snaptrade_connections) <> 1 then raise exception 'reads connection'; end if;
  begin
    perform 1 from public.snaptrade_users;
    raise exception 'should have failed: users';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.snaptrade_secret_read('00000000-0000-0000-0000-0000000000f1');
    raise exception 'should have failed: secret rpc';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.snaptrade_take_refresh('00000000-0000-0000-0000-0000000000f1', 100);
    raise exception 'should have failed: refresh rpc';
  exception when insufficient_privilege then null;
  end;
  begin
    update public.snaptrade_connections set status = 'connected';
    raise exception 'should have failed: write connection';
  exception when insufficient_privilege then null;
  end;
end $$;

set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000f2","role":"authenticated"}';
do $$
begin
  if exists (select 1 from public.snaptrade_connections) then raise exception 'sees other connection'; end if;
end $$;

-- ── Desconectar ───────────────────────────────────────────────────────────

reset role;

do $$
declare
  v_res jsonb;
begin
  v_res := public.snaptrade_disconnect('00000000-0000-0000-0000-0000000000f1', true);
  if (v_res->>'open')::int <> 1 then raise exception 'disconnect %', v_res; end if;
  if exists (select 1 from public.positions where source = 'snaptrade') then raise exception 'snaptrade rows left'; end if;
  if (select source from public.positions where ticker = 'AAPL' and user_id = '00000000-0000-0000-0000-0000000000f1') <> 'manual' then
    raise exception 'not kept as manual';
  end if;
  if exists (select 1 from public.snaptrade_users) then raise exception 'user left'; end if;
  if exists (select 1 from vault.secrets where name like 'snaptrade_user_%') then raise exception 'secret left'; end if;
  if (select status from public.snaptrade_connections) <> 'disconnected' then raise exception 'status'; end if;
  if (select brokerages from public.snaptrade_connections) <> '[]'::jsonb then raise exception 'brokerages left'; end if;
end $$;

select 'SNAPTRADE_DB_TEST_OK' as result;

rollback;
