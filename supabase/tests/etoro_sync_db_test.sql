-- Test de las migraciones 20261009000000_etoro_sync.sql y 20261010000000_etoro_holdings.sql.
--
-- Corre contra una base con la migración aplicada (supabase start, o un
-- Postgres con los stubs de auth/vault/roles). Cada chequeo que falla corta
-- con una excepción; si termina, imprime ETORO_DB_TEST_OK.
--
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/etoro_sync_db_test.sql
--
-- Todo corre dentro de una transacción que se deshace al final.

begin;

-- Base limpia dentro de la transacción: los conteos de abajo son globales y
-- una base local reusada trae filas de otras corridas (tests de integración).
delete from public.positions;
delete from public.closed_positions;
delete from public.etoro_tokens;
delete from public.etoro_oauth_states;
delete from public.etoro_connections;
delete from vault.secrets;

-- Dos usuarios.
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'a@test.local'),
  ('00000000-0000-0000-0000-00000000000b', 'b@test.local');

insert into public.etoro_connections (user_id, status, connected_at)
values ('00000000-0000-0000-0000-00000000000a', 'connected', now());

-- ── La edge function aplica una sincronización ────────────────────────────
set local role service_role;

select public.etoro_apply_sync(
  '00000000-0000-0000-0000-00000000000a',
  '[{"id":"10000000-0000-0000-0000-000000000001","external_id":"111","ticker":"AAPL","quantity":1.5,"purchase_price":180,"purchase_date":"2025-03-10T14:31:00Z","broker_price":231.5},
    {"id":"10000000-0000-0000-0000-000000000002","external_id":"222","ticker":"VOO","quantity":0.25,"purchase_price":500,"purchase_date":"2026-01-05T15:00:00Z"}]',
  '[{"id":"20000000-0000-0000-0000-000000000001","external_id":"900","ticker":"UNH","quantity":2,"avg_purchase_price":300,"close_price":320,"close_date":"2026-06-24T15:00:00Z","realized_pnl":38.5}]',
  '{"imported":2}', 'USD', '2026-10-09'
);

do $$
begin
  if (select count(*) from public.positions where source = 'etoro') <> 2 then
    raise exception 'apply_sync: esperaba 2 posiciones etoro';
  end if;
  if (select broker_price from public.positions where external_id = '111') is distinct from 231.5 then
    raise exception 'apply_sync: broker_price no guardado';
  end if;
  if (select broker_price from public.positions where external_id = '222') is not null then
    raise exception 'apply_sync: broker_price debía quedar null si no vino';
  end if;
  if (select realized_pnl from public.closed_positions where external_id = '900') <> 38.5 then
    raise exception 'apply_sync: realized_pnl no guardado';
  end if;
  if (select last_sync_status from public.etoro_connections where user_id = '00000000-0000-0000-0000-00000000000a') <> 'ok' then
    raise exception 'apply_sync: conexión no marcada ok';
  end if;
end $$;

-- Segunda sincronización: AAPL cambió de cantidad, VOO se cerró en eToro,
-- la cerrada 900 vuelve a venir (no se duplica).
select public.etoro_apply_sync(
  '00000000-0000-0000-0000-00000000000a',
  '[{"id":"10000000-0000-0000-0000-000000000001","external_id":"111","ticker":"AAPL","quantity":1,"purchase_price":180,"purchase_date":"2025-03-10T14:31:00Z","broker_price":240}]',
  '[{"id":"20000000-0000-0000-0000-000000000001","external_id":"900","ticker":"UNH","quantity":2,"avg_purchase_price":300,"close_price":320,"close_date":"2026-06-24T15:00:00Z","realized_pnl":38.5}]',
  '{"imported":1}', null, null
);

do $$
begin
  if (select count(*) from public.positions where source = 'etoro') <> 1 then
    raise exception 'resync: la cerrada en eToro debía borrarse';
  end if;
  if (select quantity from public.positions where external_id = '111') <> 1 then
    raise exception 'resync: cantidad no actualizada';
  end if;
  if (select id from public.positions where external_id = '111') <> '10000000-0000-0000-0000-000000000001' then
    raise exception 'resync: el id de la fila cambió';
  end if;
  if (select count(*) from public.closed_positions where source = 'etoro') <> 1 then
    raise exception 'resync: cerrada duplicada';
  end if;
  if (select account_currency from public.etoro_connections where user_id = '00000000-0000-0000-0000-00000000000a') <> 'USD' then
    raise exception 'resync: account_currency null pisó el valor';
  end if;
end $$;

-- Tokens en Vault.
select public.etoro_tokens_save('00000000-0000-0000-0000-00000000000a', '{"access_token":"a1"}');
select public.etoro_tokens_save('00000000-0000-0000-0000-00000000000a', '{"access_token":"a2"}');
do $$
begin
  if public.etoro_tokens_read('00000000-0000-0000-0000-00000000000a') <> '{"access_token":"a2"}' then
    raise exception 'tokens: no se actualizó el secreto';
  end if;
  if (select count(*) from public.etoro_tokens) <> 1 then
    raise exception 'tokens: debía haber un solo puntero';
  end if;
end $$;

-- Lease: el segundo pedido no entra hasta que se libera.
do $$
begin
  if not public.etoro_try_lock('00000000-0000-0000-0000-00000000000a', 60) then
    raise exception 'lock: el primero debía tomarlo';
  end if;
  if public.etoro_try_lock('00000000-0000-0000-0000-00000000000a', 60) then
    raise exception 'lock: el segundo no debía tomarlo';
  end if;
  perform public.etoro_unlock('00000000-0000-0000-0000-00000000000a');
  if not public.etoro_try_lock('00000000-0000-0000-0000-00000000000a', 60) then
    raise exception 'lock: liberado, debía poder tomarse';
  end if;
  perform public.etoro_unlock('00000000-0000-0000-0000-00000000000a');
end $$;

reset role;

-- ── La app (usuario A) ────────────────────────────────────────────────────
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000a","role":"authenticated"}';

-- Ve sus posiciones importadas y su conexión.
do $$
begin
  if (select count(*) from public.positions where source = 'etoro') <> 1 then
    raise exception 'app: no ve sus posiciones etoro';
  end if;
  if (select count(*) from public.etoro_connections) <> 1 then
    raise exception 'app: no ve su conexión';
  end if;
end $$;

-- Las manuales siguen funcionando igual.
insert into public.positions (id, user_id, ticker, quantity, purchase_price, purchase_date)
values ('30000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', 'AAPL', 3, 150, now());
update public.positions set quantity = 4 where id = '30000000-0000-0000-0000-000000000001';

do $$
begin
  if (select source from public.positions where id = '30000000-0000-0000-0000-000000000001') <> 'manual' then
    raise exception 'app: una posición nueva debía ser manual';
  end if;
end $$;

-- Borrar "todas las de AAPL" desde la app no puede tocar la de eToro.
do $$
begin
  begin
    delete from public.positions where ticker = 'AAPL';
    raise exception 'app: borrar una fila etoro debía fallar';
  exception when insufficient_privilege then
    null;
  end;
  begin
    update public.positions set quantity = 99 where external_id = '111';
    raise exception 'app: editar una fila etoro debía fallar';
  exception when insufficient_privilege then
    null;
  end;
  begin
    insert into public.positions (id, user_id, ticker, quantity, purchase_price, purchase_date, source)
    values (gen_random_uuid(), '00000000-0000-0000-0000-00000000000a', 'X', 1, 1, now(), 'etoro');
    raise exception 'app: insertar una fila etoro debía fallar';
  exception when insufficient_privilege then
    null;
  end;
  begin
    update public.positions set source = 'etoro' where id = '30000000-0000-0000-0000-000000000001';
    raise exception 'app: convertir una manual en etoro debía fallar';
  exception when insufficient_privilege then
    null;
  end;
  begin
    delete from public.closed_positions where external_id = '900';
    raise exception 'app: borrar una cerrada etoro debía fallar';
  exception when insufficient_privilege then
    null;
  end;
end $$;

-- Borrar solo las manuales de un ticker (lo que hace la app) sí funciona.
delete from public.positions where ticker = 'AAPL' and source = 'manual';

-- Ni tokens ni funciones internas.
do $$
begin
  begin
    perform public.etoro_tokens_read('00000000-0000-0000-0000-00000000000a');
    raise exception 'app: no debía poder leer tokens';
  exception when insufficient_privilege then
    null;
  end;
  begin
    perform public.etoro_apply_sync('00000000-0000-0000-0000-00000000000a', '[]', '[]', '{}', null, null);
    raise exception 'app: no debía poder aplicar un sync';
  exception when insufficient_privilege then
    null;
  end;
  begin
    perform 1 from public.etoro_tokens;
    raise exception 'app: no debía poder leer etoro_tokens';
  exception when insufficient_privilege then
    null;
  end;
end $$;

reset role;

-- ── Usuario B no ve nada de A ─────────────────────────────────────────────
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000b","role":"authenticated"}';
do $$
begin
  if (select count(*) from public.etoro_connections) <> 0 then
    raise exception 'B ve la conexión de A';
  end if;
  if (select count(*) from public.positions) <> 0 then
    raise exception 'B ve posiciones de A';
  end if;
end $$;
reset role;

-- ── Desconectar conservando como manuales ─────────────────────────────────
set local role service_role;
select public.etoro_disconnect('00000000-0000-0000-0000-00000000000a', true);
do $$
begin
  if (select count(*) from public.positions where source = 'etoro') <> 0 then
    raise exception 'disconnect(keep): quedaron filas etoro';
  end if;
  if (select count(*) from public.positions where user_id = '00000000-0000-0000-0000-00000000000a') <> 1 then
    raise exception 'disconnect(keep): se perdió la posición';
  end if;
  if exists (select 1 from public.positions where user_id = '00000000-0000-0000-0000-00000000000a' and broker_price is not null) then
    raise exception 'disconnect(keep): la manual conservó el precio de eToro';
  end if;
  if (select count(*) from public.closed_positions where source = 'manual' and realized_pnl = 38.5) <> 1 then
    raise exception 'disconnect(keep): la cerrada debía quedar como manual con su P&L';
  end if;
  if public.etoro_tokens_read('00000000-0000-0000-0000-00000000000a') is not null then
    raise exception 'disconnect: quedaron tokens';
  end if;
  if (select status from public.etoro_connections where user_id = '00000000-0000-0000-0000-00000000000a') <> 'disconnected' then
    raise exception 'disconnect: estado incorrecto';
  end if;
end $$;
reset role;

-- El secreto se borró de Vault (chequeo como dueño: la service role no
-- tiene acceso directo al schema vault).
do $$
begin
  if (select count(*) from vault.secrets) <> 0 then
    raise exception 'disconnect: quedó el secreto en Vault';
  end if;
end $$;

-- Ya manuales, la app las puede editar.
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000a","role":"authenticated"}';
update public.positions set quantity = 2 where user_id = '00000000-0000-0000-0000-00000000000a';
reset role;

-- ── Desconectar borrando ──────────────────────────────────────────────────
set local role service_role;
update public.etoro_connections set status = 'connected' where user_id = '00000000-0000-0000-0000-00000000000a';
select public.etoro_apply_sync(
  '00000000-0000-0000-0000-00000000000a',
  '[{"id":"10000000-0000-0000-0000-000000000009","external_id":"333","ticker":"MSFT","quantity":1,"purchase_price":400,"purchase_date":"2026-01-01T00:00:00Z"}]',
  '[]', '{}', null, null
);
select public.etoro_disconnect('00000000-0000-0000-0000-00000000000a', false);
do $$
begin
  if exists (select 1 from public.positions where ticker = 'MSFT') then
    raise exception 'disconnect(delete): la posición etoro debía borrarse';
  end if;
  if (select count(*) from public.positions where user_id = '00000000-0000-0000-0000-00000000000a') <> 1 then
    raise exception 'disconnect(delete): no debía tocar las manuales';
  end if;
end $$;
reset role;

select 'ETORO_DB_TEST_OK' as result;

rollback;
