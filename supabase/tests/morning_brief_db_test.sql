-- Test de 20261024000000_morning_brief.sql: el tipo `morning_brief` entra
-- al outbox, la preferencia nueva está prendida por defecto (también sin
-- fila de preferencias) y el resumen cuenta para el tope diario.
--
-- Corre contra una base con las migraciones aplicadas (supabase start, o un
-- Postgres con los stubs de auth/vault/roles). Si termina, imprime
-- MORNING_BRIEF_DB_TEST_OK.
--
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/morning_brief_db_test.sql
--
-- Todo corre dentro de una transacción que se deshace al final.

begin;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000e1', 'mb1@test.local')
on conflict do nothing;

-- Sin fila de preferencias: los defaults traen el resumen prendido.
do $$
declare
  ctx record;
begin
  select * into ctx from public.push_dispatch_context(
    array['00000000-0000-0000-0000-0000000000e1'::uuid]);
  if (ctx.prefs ->> 'morning_brief')::boolean is distinct from true then
    raise exception 'sin fila, morning_brief tendría que estar prendido: %', ctx.prefs;
  end if;
end $$;

-- Con fila: la columna nueva, prendida por defecto, y se puede apagar.
insert into public.notification_preferences (user_id)
  values ('00000000-0000-0000-0000-0000000000e1');
do $$
begin
  if (select morning_brief from public.notification_preferences
       where user_id = '00000000-0000-0000-0000-0000000000e1') is distinct from true then
    raise exception 'morning_brief no arranca prendido';
  end if;
end $$;
update public.notification_preferences set morning_brief = false
  where user_id = '00000000-0000-0000-0000-0000000000e1';
do $$
declare
  ctx record;
begin
  select * into ctx from public.push_dispatch_context(
    array['00000000-0000-0000-0000-0000000000e1'::uuid]);
  if (ctx.prefs ->> 'morning_brief')::boolean is distinct from false then
    raise exception 'el contexto no refleja morning_brief apagado: %', ctx.prefs;
  end if;
end $$;

-- El outbox acepta el tipo y push_enqueue no lo duplica.
do $$
declare
  n int;
begin
  n := public.push_enqueue(jsonb_build_array(
    jsonb_build_object(
      'user_id', '00000000-0000-0000-0000-0000000000e1',
      'kind', 'morning_brief',
      'dedupe_key', 'morning_brief:2026-10:concentration:NVDA',
      'data', jsonb_build_object('count', 1)),
    jsonb_build_object(
      'user_id', '00000000-0000-0000-0000-0000000000e1',
      'kind', 'morning_brief',
      'dedupe_key', 'morning_brief:2026-10:concentration:NVDA',
      'data', jsonb_build_object('count', 1))));
  if n <> 1 then
    raise exception 'push_enqueue tendría que encolar 1, encoló %', n;
  end if;
end $$;

-- Cuenta para el tope diario de automáticas.
insert into public.notification_log (user_id, kind, device_count)
  values ('00000000-0000-0000-0000-0000000000e1', 'morning_brief', 1);
do $$
declare
  ctx record;
begin
  select * into ctx from public.push_dispatch_context(
    array['00000000-0000-0000-0000-0000000000e1'::uuid]);
  if ctx.automatic_last_24h <> 1 then
    raise exception 'el resumen no cuenta para el tope: %', ctx.automatic_last_24h;
  end if;
end $$;

-- Un tipo desconocido sigue rechazado.
do $$
begin
  begin
    insert into public.notification_outbox (user_id, kind, dedupe_key)
      values ('00000000-0000-0000-0000-0000000000e1', 'nope', 'x');
    raise exception 'aceptó un tipo desconocido';
  exception when check_violation then
    null;
  end;
end $$;

select 'MORNING_BRIEF_DB_TEST_OK';

rollback;
