-- Test de 20261120000000_etoro_reconnect_replaces_kept.sql: reconectar eToro
-- después de conservar lo importado como manual (desconectar conservando o
-- importación gratis) reemplaza esas copias en vez de chocar con
-- positions_pkey. Las manuales cargadas a mano no se tocan.
--
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/etoro_reconnect_db_test.sql
--
-- Todo corre dentro de una transacción que se deshace al final.

begin;

delete from public.positions;
delete from public.closed_positions;
delete from public.etoro_tokens;
delete from public.etoro_oauth_states;
delete from public.etoro_connections;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'a@test.local'),
  ('00000000-0000-0000-0000-00000000000b', 'b@test.local');

insert into public.etoro_connections (user_id, status, connected_at)
values ('00000000-0000-0000-0000-00000000000a', 'connected', now());

-- Una manual cargada a mano (id cualquiera) y otra de otro usuario.
insert into public.positions (id, user_id, ticker, quantity, purchase_price, purchase_date)
values
  ('30000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', 'KO', 3, 60, '2025-01-01T00:00:00Z'),
  ('30000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000b', 'KO', 1, 60, '2025-01-01T00:00:00Z');

set local role service_role;

-- Primera conexión: AAPL y VOO abiertas, UNH cerrada.
select public.etoro_apply_sync(
  '00000000-0000-0000-0000-00000000000a',
  '[{"id":"10000000-0000-0000-0000-000000000001","external_id":"111","ticker":"AAPL","quantity":1.5,"purchase_price":180,"purchase_date":"2025-03-10T14:31:00Z"},
    {"id":"10000000-0000-0000-0000-000000000002","external_id":"222","ticker":"VOO","quantity":0.25,"purchase_price":500,"purchase_date":"2026-01-05T15:00:00Z"}]',
  '[{"id":"20000000-0000-0000-0000-000000000001","open_id":"10000000-0000-0000-0000-000000000009","external_id":"900","ticker":"UNH","quantity":2,"avg_purchase_price":300,"close_price":320,"close_date":"2026-06-24T15:00:00Z","realized_pnl":38.5}]',
  '{"imported":2}', 'USD', '2026-11-15'
);

-- Desconecta conservando: todo pasa a manual con el mismo id.
select public.etoro_disconnect('00000000-0000-0000-0000-00000000000a', true);

do $$
begin
  if (select count(*) from public.positions where user_id = '00000000-0000-0000-0000-00000000000a' and source = 'manual') <> 3 then
    raise exception 'preparación: esperaba 3 abiertas manuales (2 de eToro + KO)';
  end if;
end $$;

-- Reconecta. Mientras estuvo desconectado, VOO se cerró en eToro (llega
-- como cerrada con su open_id) y AAPL subió de cantidad. Antes fallaba con
-- duplicate key value violates unique constraint "positions_pkey".
update public.etoro_connections set status = 'connected' where user_id = '00000000-0000-0000-0000-00000000000a';
select public.etoro_apply_sync(
  '00000000-0000-0000-0000-00000000000a',
  '[{"id":"10000000-0000-0000-0000-000000000001","external_id":"111","ticker":"AAPL","quantity":2,"purchase_price":180,"purchase_date":"2025-03-10T14:31:00Z"}]',
  '[{"id":"20000000-0000-0000-0000-000000000001","open_id":"10000000-0000-0000-0000-000000000009","external_id":"900","ticker":"UNH","quantity":2,"avg_purchase_price":300,"close_price":320,"close_date":"2026-06-24T15:00:00Z","realized_pnl":38.5},
    {"id":"20000000-0000-0000-0000-000000000002","open_id":"10000000-0000-0000-0000-000000000002","external_id":"222","ticker":"VOO","quantity":0.25,"avg_purchase_price":500,"close_price":520,"close_date":"2026-11-18T15:00:00Z","realized_pnl":5}]',
  '{"imported":1}', 'USD', '2026-11-20'
);

do $$
declare
  a constant uuid := '00000000-0000-0000-0000-00000000000a';
begin
  -- AAPL: una sola fila, la de eToro, con la cantidad nueva.
  if (select count(*) from public.positions where user_id = a and ticker = 'AAPL') <> 1 then
    raise exception 'reconectar: AAPL quedó duplicada';
  end if;
  if not exists (select 1 from public.positions where user_id = a and ticker = 'AAPL' and source = 'etoro' and quantity = 2) then
    raise exception 'reconectar: AAPL debía ser la de eToro con cantidad 2';
  end if;
  -- VOO se cerró: no queda abierta (ni la copia manual).
  if exists (select 1 from public.positions where user_id = a and ticker = 'VOO') then
    raise exception 'reconectar: VOO cerrada quedó como abierta manual';
  end if;
  -- KO cargada a mano sigue intacta.
  if (select quantity from public.positions where id = '30000000-0000-0000-0000-000000000001') <> 3 then
    raise exception 'reconectar: se tocó una manual cargada a mano';
  end if;
  -- Cerradas: UNH y VOO, una vez cada una y de eToro.
  if (select count(*) from public.closed_positions where user_id = a) <> 2 then
    raise exception 'reconectar: esperaba 2 cerradas, hay %', (select count(*) from public.closed_positions where user_id = a);
  end if;
  if exists (select 1 from public.closed_positions where user_id = a and source = 'manual') then
    raise exception 'reconectar: quedó la copia manual de una cerrada';
  end if;
  -- El otro usuario no se tocó.
  if (select count(*) from public.positions where user_id = '00000000-0000-0000-0000-00000000000b') <> 1 then
    raise exception 'reconectar: se tocaron posiciones de otro usuario';
  end if;
end $$;

-- Sin open_id (edge function anterior): sigue andando y no borra de más.
select public.etoro_apply_sync(
  '00000000-0000-0000-0000-00000000000a',
  '[{"id":"10000000-0000-0000-0000-000000000001","external_id":"111","ticker":"AAPL","quantity":2,"purchase_price":180,"purchase_date":"2025-03-10T14:31:00Z"}]',
  '[{"id":"20000000-0000-0000-0000-000000000001","external_id":"900","ticker":"UNH","quantity":2,"avg_purchase_price":300,"close_price":320,"close_date":"2026-06-24T15:00:00Z","realized_pnl":38.5}]',
  '{"imported":1}', 'USD', '2026-11-20'
);

do $$
begin
  if (select quantity from public.positions where id = '30000000-0000-0000-0000-000000000001') <> 3 then
    raise exception 'sin open_id: se tocó la manual cargada a mano';
  end if;
end $$;

reset role;

select 'ETORO_RECONNECT_DB_TEST_OK' as result;

rollback;
