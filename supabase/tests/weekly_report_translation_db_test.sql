-- Test de 20261106100000_weekly_report_translation.sql (informe en el otro
-- idioma, solo cuando el usuario lo cambia en la semana).
--
-- Corre contra una base con las migraciones aplicadas (supabase start, o un
-- Postgres con los stubs de auth/vault/roles). Si termina, imprime
-- WEEKLY_REPORT_TRANSLATION_DB_TEST_OK.
--
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/weekly_report_translation_db_test.sql
--
-- Todo corre dentro de una transacción que se deshace al final.

begin;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000e1', 'gold@test.local'),
  ('00000000-0000-0000-0000-0000000000e2', 'otro@test.local');
insert into public.app_config (key, value) values ('weekly_report', '{"enabled": true}')
on conflict (key) do update set value = excluded.value;

create function pg_temp.as_user(u text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
end;
$$;

create function pg_temp.monday() returns date language sql as $$
  select date_trunc('week', (now() at time zone 'utc')::date - 4)::date;
$$;

-- Informe completo ya generado en español, y uno viejo sin `lang`.
insert into public.weekly_reports (user_id, week_start, status, payload, llm_rounds)
values
  ('00000000-0000-0000-0000-0000000000e1', pg_temp.monday(), 'ready',
   jsonb_build_object('v', 2, 'week', pg_temp.monday()::text, 'variant', 'full',
                      'lang', 'es', 'reading', 'Apple empujó tu cartera'), 2),
  ('00000000-0000-0000-0000-0000000000e2', pg_temp.monday(), 'ready',
   jsonb_build_object('v', 2, 'week', pg_temp.monday()::text, 'variant', 'full',
                      'reading', 'Sin idioma'), 2);

-- 1. Mismo idioma: ready con el payload, sin claim.
set local role authenticated;
do $$
declare r jsonb;
begin
  perform pg_temp.as_user('00000000-0000-0000-0000-0000000000e1');
  r := public.claim_weekly_report_translation(pg_temp.monday(), 'es');
  if r ->> 'state' <> 'ready' or r -> 'payload' ->> 'lang' <> 'es' then
    raise exception 'mismo idioma: %', r;
  end if;
  -- Idioma inválido.
  r := public.claim_weekly_report_translation(pg_temp.monday(), 'fr');
  if r <> '{"state":"unavailable"}'::jsonb then raise exception 'idioma inválido: %', r; end if;
  -- Sin claim, no se puede completar.
  r := public.complete_weekly_report_translation(pg_temp.monday(),
    jsonb_build_object('week', pg_temp.monday()::text, 'lang', 'en'));
  if r ->> 'ok' <> 'false' then raise exception 'complete sin claim: %', r; end if;
end $$;
reset role;

-- 2. Payload viejo sin `lang`: no se traduce.
set local role authenticated;
do $$
declare r jsonb;
begin
  perform pg_temp.as_user('00000000-0000-0000-0000-0000000000e2');
  r := public.claim_weekly_report_translation(pg_temp.monday(), 'en');
  if r <> '{"state":"unavailable"}'::jsonb then raise exception 'sin lang: %', r; end if;
end $$;
reset role;

-- 3. Otro idioma: claimed; un segundo pedido ve in_progress.
set local role authenticated;
do $$
declare r jsonb;
begin
  perform pg_temp.as_user('00000000-0000-0000-0000-0000000000e1');
  r := public.claim_weekly_report_translation(pg_temp.monday(), 'en');
  if r <> '{"state":"claimed"}'::jsonb then raise exception 'claim en: %', r; end if;
  r := public.claim_weekly_report_translation(pg_temp.monday(), 'en');
  if r <> '{"state":"in_progress"}'::jsonb then raise exception 'in_progress: %', r; end if;
end $$;
reset role;

-- 4. ai-chat acepta el claim de traducción y cuenta la ronda.
do $$
declare r jsonb;
begin
  r := public.ai_report_begin('00000000-0000-0000-0000-0000000000e1', 'turn-tr-1',
    pg_temp.monday(), 'gpt-6-luna', 8, 100);
  if r <> '{"ok":true}'::jsonb then raise exception 'begin con claim de traducción: %', r; end if;
  if (select llm_rounds from public.weekly_reports
      where user_id = '00000000-0000-0000-0000-0000000000e1') <> 3 then
    raise exception 'no contó la ronda';
  end if;
  -- El otro usuario no tiene claim: not_claimed.
  r := public.ai_report_begin('00000000-0000-0000-0000-0000000000e2', 'turn-tr-2',
    pg_temp.monday(), 'gpt-6-luna', 8, 100);
  if r ->> 'reason' <> 'not_claimed' then raise exception 'sin claim: %', r; end if;
end $$;

-- 5. Completar: el idioma tiene que ser el reclamado y la semana la misma.
set local role authenticated;
do $$
declare r jsonb;
begin
  perform pg_temp.as_user('00000000-0000-0000-0000-0000000000e1');
  r := public.complete_weekly_report_translation(pg_temp.monday(),
    jsonb_build_object('week', pg_temp.monday()::text, 'lang', 'es'));
  if r ->> 'ok' <> 'false' then raise exception 'idioma equivocado: %', r; end if;
  r := public.complete_weekly_report_translation(pg_temp.monday(),
    jsonb_build_object('week', '2020-01-06', 'lang', 'en'));
  if r ->> 'ok' <> 'false' then raise exception 'semana equivocada: %', r; end if;
  r := public.complete_weekly_report_translation(pg_temp.monday(),
    jsonb_build_object('week', pg_temp.monday()::text, 'lang', 'en',
                       'reading', 'Apple pushed your portfolio',
                       'alt', jsonb_build_object('x', 1)));
  if r <> '{"ok":true}'::jsonb then raise exception 'complete: %', r; end if;
end $$;
reset role;

do $$
declare p jsonb;
begin
  select payload into p from public.weekly_reports
  where user_id = '00000000-0000-0000-0000-0000000000e1';
  if p ->> 'lang' <> 'es'
     or p ->> 'reading' <> 'Apple empujó tu cartera'
     or p -> 'alt' ->> 'reading' <> 'Apple pushed your portfolio'
     or p -> 'alt' ? 'alt' then
    raise exception 'payload final: %', p;
  end if;
end $$;

-- 6. Ya están los dos idiomas: ready en los dos, y ai-chat ya no acepta
--    llamadas (el claim se cerró).
set local role authenticated;
do $$
declare r jsonb;
begin
  perform pg_temp.as_user('00000000-0000-0000-0000-0000000000e1');
  r := public.claim_weekly_report_translation(pg_temp.monday(), 'en');
  if r ->> 'state' <> 'ready' then raise exception 'en ya guardado: %', r; end if;
  r := public.claim_weekly_report_translation(pg_temp.monday(), 'es');
  if r ->> 'state' <> 'ready' then raise exception 'es ya guardado: %', r; end if;
end $$;
reset role;
do $$
declare r jsonb;
begin
  r := public.ai_report_begin('00000000-0000-0000-0000-0000000000e1', 'turn-tr-3',
    pg_temp.monday(), 'gpt-6-luna', 8, 100);
  if r ->> 'reason' <> 'not_claimed' then raise exception 'claim cerrado: %', r; end if;
end $$;

-- 7. anon no puede llamar las RPCs.
set local role anon;
do $$
begin
  begin
    perform public.claim_weekly_report_translation(pg_temp.monday(), 'en');
    raise exception 'anon pudo reclamar';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

select 'WEEKLY_REPORT_TRANSLATION_DB_TEST_OK';
rollback;
