-- Test de 20261024000200_porty_topics.sql: registrar los tickers de un
-- turno, actualizar los repetidos, el tope de 50 y que cada usuario vea y
-- borre solo los suyos.
--
-- Corre contra una base con las migraciones aplicadas (supabase start, o un
-- Postgres con los stubs de auth/vault/roles). Si termina, imprime
-- PORTY_TOPICS_DB_TEST_OK.
--
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/porty_topics_db_test.sql
--
-- Todo corre dentro de una transacción que se deshace al final.

begin;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000f1', 'tf1@test.local'),
  ('00000000-0000-0000-0000-0000000000f2', 'tf2@test.local');

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000f1","role":"authenticated"}';

do $$
declare
  n int;
begin
  n := public.porty_topics_touch(jsonb_build_array(
    jsonb_build_object('ticker', 'amzn', 'question', '¿Qué pasa con Amazon?', 'price_at', 182.5, 'held', false),
    jsonb_build_object('ticker', 'NVDA', 'question', '¿Por qué bajó?', 'held', true),
    jsonb_build_object('ticker', 'no vale!', 'question', 'x')));
  if n <> 2 then
    raise exception 'tendría que registrar 2 (el ticker raro no), registró %', n;
  end if;
  if (select price_at from public.porty_topics where ticker = 'AMZN') <> 182.5 then
    raise exception 'no guardó el precio de AMZN en mayúsculas';
  end if;
end $$;

-- Repetido: actualiza la pregunta y suma; sin precio nuevo, conserva el viejo.
do $$
begin
  perform public.porty_topics_touch(jsonb_build_array(
    jsonb_build_object('ticker', 'AMZN', 'question', '¿Y ahora?')));
  if (select times from public.porty_topics where ticker = 'AMZN') <> 2 then
    raise exception 'no sumó la segunda vez';
  end if;
  if (select question from public.porty_topics where ticker = 'AMZN') <> '¿Y ahora?' then
    raise exception 'no actualizó la pregunta';
  end if;
  if (select price_at from public.porty_topics where ticker = 'AMZN') <> 182.5 then
    raise exception 'perdió el precio anterior';
  end if;
end $$;

-- El otro usuario no ve ni borra lo del primero.
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000f2","role":"authenticated"}';
do $$
begin
  if (select count(*) from public.porty_topics) <> 0 then
    raise exception 'f2 ve temas ajenos';
  end if;
  delete from public.porty_topics where ticker = 'AMZN';
end $$;

-- No se escribe directo (solo por la función).
do $$
begin
  begin
    insert into public.porty_topics (user_id, ticker, question)
      values ('00000000-0000-0000-0000-0000000000f2', 'KO', 'x');
    raise exception 'pudo insertar directo';
  exception when insufficient_privilege then
    null;
  end;
end $$;

-- Tope de 50: entran 55 en varias tandas, quedan las 50 más recientes.
do $$
declare
  i int;
begin
  for i in 1..55 loop
    perform public.porty_topics_touch(jsonb_build_array(
      jsonb_build_object('ticker', 'T' || i, 'question', 'q')));
  end loop;
  if (select count(*) from public.porty_topics) <> 50 then
    raise exception 'tendría que quedar en 50, hay %', (select count(*) from public.porty_topics);
  end if;
  if exists (select 1 from public.porty_topics where ticker in ('T1', 'T5')) then
    raise exception 'no se fueron las más viejas';
  end if;
end $$;

set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000f1","role":"authenticated"}';
do $$
begin
  if (select count(*) from public.porty_topics) <> 2 then
    raise exception 'f1 perdió temas por lo de f2';
  end if;
  delete from public.porty_topics where ticker = 'NVDA';
  if (select count(*) from public.porty_topics) <> 1 then
    raise exception 'f1 no pudo borrar el suyo';
  end if;
end $$;

select 'PORTY_TOPICS_DB_TEST_OK';

rollback;
