-- Test de 20261103110000_rollout_flag_sql.sql y
-- 20261103120000_weekly_report_courtesy.sql (hábito del sábado).
--
-- Corre contra una base con las migraciones aplicadas (supabase start, o un
-- Postgres con los stubs de auth/vault/roles). Si termina, imprime
-- WEEKLY_REPORT_COURTESY_DB_TEST_OK.
--
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/weekly_report_courtesy_db_test.sql
--
-- Todo corre dentro de una transacción que se deshace al final.

begin;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000d1', 'free@test.local'),
  ('00000000-0000-0000-0000-0000000000d2', 'gold@test.local'),
  ('00000000-0000-0000-0000-0000000000a1', 'viejo@test.local');
insert into public.user_subscriptions (user_id, tier, status) values
  ('00000000-0000-0000-0000-0000000000d1', 'free', 'active'),
  ('00000000-0000-0000-0000-0000000000d2', 'gold', 'active'),
  ('00000000-0000-0000-0000-0000000000a1', 'premium', 'active')
on conflict (user_id) do update set tier = excluded.tier, status = excluded.status;

insert into public.app_config (key, value) values ('weekly_report', '{"enabled": true}')
on conflict (key) do update set value = excluded.value;

create function pg_temp.as_user(u text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
end;
$$;

-- Lunes de la semana válida más reciente. La ventana de claim es chica (una
-- o dos semanas), así que los regalos anteriores se siembran directo: n = 0 es
-- la semana a reclamar, n > 0 las anteriores.
create function pg_temp.monday(n int) returns date language sql as $$
  select (date_trunc('week', (now() at time zone 'utc')::date - 4)::date - 7 * n);
$$;
create function pg_temp.seed_gifts(u text, k int) returns void language plpgsql as $$
declare i int;
begin
  for i in 1..k loop
    insert into public.weekly_reports (user_id, week_start, status, courtesy)
    values (u::uuid, pg_temp.monday(i), 'ready', true);
  end loop;
end;
$$;

-- 1. Bucket: vectores de la app.
do $$
begin
  if public._rollout_bucket('00000000-0000-0000-0000-0000000000d1') <> 70
     or public._rollout_bucket('00000000-0000-0000-0000-0000000000d2') <> 51
     or public._rollout_bucket('00000000-0000-0000-0000-0000000000a1') <> 3
     or public._rollout_bucket('00000000-0000-0000-0000-0000000000a2') <> 22 then
    raise exception 'bucket no coincide con la app';
  end if;
  if public._rollout_on('no_existe', '00000000-0000-0000-0000-0000000000d1')
     or public._rollout_on('weekly_report', null) then
    raise exception '_rollout_on debe fallar cerrado';
  end if;
end $$;

set local role authenticated;

-- 2. Interruptor apagado: sin regalos → 1 de 1; con uno usado → numbers_only.
set local role authenticated;
do $$
declare r jsonb;
begin
  perform pg_temp.as_user('00000000-0000-0000-0000-0000000000d1');
  r := public.claim_weekly_report(pg_temp.monday(0));
  if r <> '{"state":"claimed","courtesy":true,"attempt":1,"courtesy_number":1,"courtesy_total":1}'::jsonb then
    raise exception 'apagado A: %', r;
  end if;
end $$;
reset role;
delete from public.weekly_reports;
select pg_temp.seed_gifts('00000000-0000-0000-0000-0000000000d1', 1);
set local role authenticated;
do $$
declare r jsonb;
begin
  perform pg_temp.as_user('00000000-0000-0000-0000-0000000000d1');
  r := public.claim_weekly_report(pg_temp.monday(0));
  if r <> '{"state":"numbers_only"}'::jsonb then raise exception 'apagado B: %', r; end if;
end $$;
reset role;

-- 3. Prendido para d1 con reports 3. Ya tenía 1 regalo → este es el 2.º de 3;
--    con 2 usados → el 3.º; con 3 → numbers_only.
update public.app_config set value = jsonb_build_object('percent', 0, 'users', jsonb_build_array('00000000-0000-0000-0000-0000000000d1'), 'reports', 3)
 where key = 'weekly_report_courtesy';
set local role authenticated;
do $$
declare r jsonb;
begin
  perform pg_temp.as_user('00000000-0000-0000-0000-0000000000d1');
  r := public.claim_weekly_report(pg_temp.monday(0));
  if r <> '{"state":"claimed","courtesy":true,"attempt":1,"courtesy_number":2,"courtesy_total":3}'::jsonb then
    raise exception 'regalo 2: %', r;
  end if;
end $$;
reset role;
delete from public.weekly_reports;
select pg_temp.seed_gifts('00000000-0000-0000-0000-0000000000d1', 2);
set local role authenticated;
do $$
declare r jsonb;
begin
  perform pg_temp.as_user('00000000-0000-0000-0000-0000000000d1');
  r := public.claim_weekly_report(pg_temp.monday(0));
  if r <> '{"state":"claimed","courtesy":true,"attempt":1,"courtesy_number":3,"courtesy_total":3}'::jsonb then
    raise exception 'regalo 3: %', r;
  end if;
end $$;
reset role;
-- Re-claim (intento 2) de este mismo regalo: sigue siendo el 3 de 3.
update public.weekly_reports set status = 'generating', claimed_at = now() - interval '5 minutes'
 where user_id = '00000000-0000-0000-0000-0000000000d1' and week_start = pg_temp.monday(0);
set local role authenticated;
do $$
declare r jsonb;
begin
  perform pg_temp.as_user('00000000-0000-0000-0000-0000000000d1');
  r := public.claim_weekly_report(pg_temp.monday(0));
  if r <> '{"state":"claimed","courtesy":true,"attempt":2,"courtesy_number":3,"courtesy_total":3}'::jsonb then
    raise exception 're-claim: %', r;
  end if;
end $$;
reset role;
delete from public.weekly_reports;
select pg_temp.seed_gifts('00000000-0000-0000-0000-0000000000d1', 3);
set local role authenticated;
do $$
declare r jsonb;
begin
  perform pg_temp.as_user('00000000-0000-0000-0000-0000000000d1');
  r := public.claim_weekly_report(pg_temp.monday(0));
  if r <> '{"state":"numbers_only"}'::jsonb then raise exception 'semana D: %', r; end if;
  -- Un usuario fuera de la lista y con percent 0 sigue con 1 regalo.
  perform pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
  r := public.claim_weekly_report(pg_temp.monday(0));
  if r->>'courtesy_total' <> '1' then raise exception 'a1: %', r; end if;
end $$;
reset role;

-- 4. Acotado de reports (flag prendido por users).
do $$
declare
  u uuid := '00000000-0000-0000-0000-0000000000d1';
  c record;
begin
  for c in select * from (values
    ('{"percent":0,"users":["00000000-0000-0000-0000-0000000000d1"]}'::jsonb, 3),
    ('{"percent":0,"users":["00000000-0000-0000-0000-0000000000d1"],"reports":"x"}', 3),
    ('{"percent":0,"users":["00000000-0000-0000-0000-0000000000d1"],"reports":0}', 1),
    ('{"percent":0,"users":["00000000-0000-0000-0000-0000000000d1"],"reports":50}', 8),
    ('{"percent":0,"users":["00000000-0000-0000-0000-0000000000d1"],"reports":4}', 4),
    ('{"percent":0,"users":[],"reports":6}', 1),
    ('{"percent":100,"users":[],"reports":6}', 6)
  ) as t(v, expected) loop
    update public.app_config set value = c.v where key = 'weekly_report_courtesy';
    if public._weekly_courtesy_limit(u) <> c.expected then
      raise exception 'limit % → % (esperado %)', c.v, public._weekly_courtesy_limit(u), c.expected;
    end if;
  end loop;
end $$;

-- 5. Gold: sin campos nuevos; disabled le gana a todo.
delete from public.weekly_reports;
update public.app_config set value = '{"percent":100,"users":[],"reports":3}' where key = 'weekly_report_courtesy';
set local role authenticated;
do $$
declare r jsonb;
begin
  perform pg_temp.as_user('00000000-0000-0000-0000-0000000000d2');
  r := public.claim_weekly_report(pg_temp.monday(0));
  if r <> '{"state":"claimed","courtesy":false,"attempt":1}'::jsonb then raise exception 'gold: %', r; end if;
end $$;
reset role;
update public.app_config set value = '{"enabled": false}' where key = 'weekly_report';
set local role authenticated;
do $$
begin
  perform pg_temp.as_user('00000000-0000-0000-0000-0000000000d1');
  if public.claim_weekly_report(pg_temp.monday(0)) <> '{"state":"disabled"}'::jsonb then
    raise exception 'disabled no gana';
  end if;
end $$;
reset role;

select 'WEEKLY_REPORT_COURTESY_DB_TEST_OK' as result;
rollback;
