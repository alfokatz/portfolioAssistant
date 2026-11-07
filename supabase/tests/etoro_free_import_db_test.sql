-- Test de 20261026000100_etoro_free_import.sql: cerrar una importación
-- gratis deja lo importado como manual (sin precio de eToro), borra los
-- tokens y la deja marcada como usada, conservando el resultado. La app no
-- puede llamarla.
--
-- Corre contra una base con las migraciones aplicadas (supabase start, o un
-- Postgres con los stubs de auth/vault/roles). Si termina, imprime
-- ETORO_FREE_IMPORT_DB_TEST_OK.
--
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/etoro_free_import_db_test.sql
--
-- Todo corre dentro de una transacción que se deshace al final.

begin;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000d1', 'fi1@test.local');

insert into public.etoro_connections (user_id, status, connected_at)
values ('00000000-0000-0000-0000-0000000000d1', 'connected', now());

set local role service_role;

select public.etoro_apply_sync(
  '00000000-0000-0000-0000-0000000000d1',
  '[{"id":"30000000-0000-0000-0000-000000000001","external_id":"311","ticker":"AAPL","quantity":1,"purchase_price":180,"purchase_date":"2025-03-10T14:31:00Z","broker_price":231.5}]',
  '[{"id":"40000000-0000-0000-0000-000000000001","external_id":"390","ticker":"UNH","quantity":2,"avg_purchase_price":300,"close_price":320,"close_date":"2026-06-24T15:00:00Z","realized_pnl":38.5}]',
  '{"imported":1}', 'USD', '2026-10-09'
);
select public.etoro_tokens_save('00000000-0000-0000-0000-0000000000d1', 'tokens-cifrados');

do $$
declare
  r jsonb;
  c record;
begin
  r := public.etoro_finish_free_import('00000000-0000-0000-0000-0000000000d1');
  if (r->>'open')::int <> 1 or (r->>'closed')::int <> 1 then
    raise exception 'conteos: %', r;
  end if;
  if exists (select 1 from public.positions
              where user_id = '00000000-0000-0000-0000-0000000000d1'
                and (source <> 'manual' or external_id is not null or broker_price is not null)) then
    raise exception 'las posiciones debían quedar manuales y sin precio de eToro';
  end if;
  if exists (select 1 from public.closed_positions
              where user_id = '00000000-0000-0000-0000-0000000000d1' and source <> 'manual') then
    raise exception 'las cerradas debían quedar manuales';
  end if;
  if public.etoro_tokens_read('00000000-0000-0000-0000-0000000000d1') is not null then
    raise exception 'quedaron tokens';
  end if;
  select * into c from public.etoro_connections
   where user_id = '00000000-0000-0000-0000-0000000000d1';
  if c.status <> 'disconnected' or c.free_import_at is null then
    raise exception 'conexión: % %', c.status, c.free_import_at;
  end if;
  if (c.last_result->>'imported')::int <> 1 then
    raise exception 'debía conservar el resultado';
  end if;
end;
$$;

-- La app no la puede llamar.
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000d1","role":"authenticated"}';
do $$
begin
  perform public.etoro_finish_free_import('00000000-0000-0000-0000-0000000000d1');
  raise exception 'debía fallar: authenticated';
exception when insufficient_privilege then null;
end;
$$;

-- Pero sí lee su conexión, con la marca.
do $$
begin
  if (select free_import_at from public.etoro_connections) is null then
    raise exception 'la app debía ver free_import_at';
  end if;
end;
$$;

select 'ETORO_FREE_IMPORT_DB_TEST_OK';

rollback;
