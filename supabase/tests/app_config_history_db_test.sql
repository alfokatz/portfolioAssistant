-- Test de 20261105100000_app_config_history.sql y 20261105100100_conversion_flags_on.sql
-- (historial de app_config e interruptores de conversión al 100 %).
--
-- Corre contra una base con las migraciones aplicadas (supabase start). Si
-- termina, imprime APP_CONFIG_HISTORY_DB_TEST_OK.
--
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/app_config_history_db_test.sql
--
-- Correlo desde la raíz del repo: usa \i con la ruta de la migración.
--
-- Todo corre dentro de una transacción que se deshace al final.

begin;

-- 1. Insert, update y delete de una fila de prueba dejan 3 filas, sin `users`.
insert into public.app_config (key, value)
values ('test_hist_flag', '{"percent":0,"users":["00000000-0000-0000-0000-0000000000a1","00000000-0000-0000-0000-0000000000a2"]}');
update public.app_config set value = jsonb_set(value, '{percent}', '50') where key = 'test_hist_flag';
-- Solo cambia updated_at o la lista (misma cantidad): no hace falta otra fila.
update public.app_config set updated_at = now() + interval '1 second' where key = 'test_hist_flag';
update public.app_config
   set value = jsonb_set(value, '{users}', '["00000000-0000-0000-0000-0000000000b1","00000000-0000-0000-0000-0000000000b2"]')
 where key = 'test_hist_flag';
delete from public.app_config where key = 'test_hist_flag';

do $$
declare
  v_ops text;
begin
  select string_agg(op, ',' order by id) into v_ops from public.app_config_history where key = 'test_hist_flag';
  if v_ops is distinct from 'insert,update,delete' then
    raise exception 'historial de la fila de prueba: %', v_ops;
  end if;
  if exists (select 1 from public.app_config_history where key = 'test_hist_flag' and value ? 'users') then
    raise exception 'el historial guardó la clave users';
  end if;
  if exists (select 1 from public.app_config_history where value::text ~* '[0-9a-f]{8}-[0-9a-f]{4}-') then
    raise exception 'el historial guardó un uuid';
  end if;
  if (select users_count from public.app_config_history where key = 'test_hist_flag' and op = 'insert') <> 2 then
    raise exception 'users_count del insert';
  end if;
  if (select (value->>'percent')::int from public.app_config_history where key = 'test_hist_flag' and op = 'update') <> 50 then
    raise exception 'el update no guardó el percent nuevo';
  end if;
  if (select value->>'percent' from public.app_config_history where key = 'test_hist_flag' and op = 'delete') <> '50' then
    raise exception 'el delete no guardó el último valor';
  end if;
end $$;

-- 2. La foto inicial existe para lo que ya había (en un stack nuevo, todo
--    app_config tuvo su snapshot o su insert).
do $$
begin
  if not exists (select 1 from public.app_config_history where key = 'min_supported_build') then
    raise exception 'min_supported_build no está en el historial';
  end if;
end $$;

-- 3. Solo la service role lo lee.
set local role authenticated;
do $$
begin
  perform 1 from public.app_config_history;
  raise exception 'authenticated pudo leer app_config_history';
exception when insufficient_privilege then null;
end $$;
reset role;

-- 4. conversion_flags_on: percent 100, `users` conservado, reports 3; dos
--    corridas dan lo mismo y la segunda no suma historia.
update public.app_config set value = '{"percent":10,"users":["00000000-0000-0000-0000-0000000000c1"],"reports":1}'
 where key = 'weekly_report_courtesy';
update public.app_config set value = '{"percent":0,"users":["00000000-0000-0000-0000-0000000000c1"]}'
 where key = 'market_taste';
delete from public.app_config where key = 'quota_nudge';

create temp table _hist_before on commit drop as select count(*)::int n from public.app_config_history;

-- Corre la migración dos veces (desde la raíz del repo).
\i supabase/migrations/20261105100100_conversion_flags_on.sql
create temp table _hist_after_first on commit drop as select count(*)::int n from public.app_config_history;
\i supabase/migrations/20261105100100_conversion_flags_on.sql

do $$
begin
  if (select count(*) from public.app_config_history) <> (select n from _hist_after_first) then
    raise exception 'la segunda corrida agregó historia';
  end if;
end $$;

do $$
declare
  k text;
begin
  foreach k in array array['market_taste','quota_nudge','diagnosis_bridge','broker_screenshot_exit','weekly_report_courtesy'] loop
    if (select (value->>'percent')::int from public.app_config where key = k) <> 100 then
      raise exception '% no quedó al 100 %%', k;
    end if;
  end loop;
  if (select value->'users' from public.app_config where key = 'market_taste')
     <> '["00000000-0000-0000-0000-0000000000c1"]'::jsonb then
    raise exception 'market_taste perdió users: %', (select value from public.app_config where key = 'market_taste');
  end if;
  if (select value->'users' from public.app_config where key = 'weekly_report_courtesy')
     <> '["00000000-0000-0000-0000-0000000000c1"]'::jsonb then
    raise exception 'weekly_report_courtesy perdió users';
  end if;
  if (select (value->>'reports')::int from public.app_config where key = 'weekly_report_courtesy') <> 3 then
    raise exception 'reports no quedó en 3';
  end if;
  if (select value->'users' from public.app_config where key = 'quota_nudge') <> '[]'::jsonb then
    raise exception 'quota_nudge insertado sin users vacío';
  end if;
  -- Los cambios de los flags quedaron en el historial.
  if not exists (
    select 1 from public.app_config_history
     where key = 'weekly_report_courtesy' and (value->>'percent')::int = 100 and (value->>'reports')::int = 3
  ) then
    raise exception 'el historial no tiene el weekly_report_courtesy al 100';
  end if;
end $$;

select 'APP_CONFIG_HISTORY_DB_TEST_OK' as result;

rollback;
