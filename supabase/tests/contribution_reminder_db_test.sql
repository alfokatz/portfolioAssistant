-- Test de 20261024000300_contribution_reminder.sql: el día y el monto del
-- recordatorio de aporte, el tipo nuevo del outbox y que
-- `contribution_reminder_inputs` solo devuelva planes pagos con recordatorio.
--
-- Corre contra una base con las migraciones aplicadas (supabase start, o un
-- Postgres con los stubs de auth/vault/roles). Si termina, imprime
-- CONTRIBUTION_DB_TEST_OK.
--
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/contribution_reminder_db_test.sql
--
-- Todo corre dentro de una transacción que se deshace al final.

begin;

delete from public.allocation_plans;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000d1', 'cpremium@test.local'),
  ('00000000-0000-0000-0000-0000000000d2', 'cpremium2@test.local');

insert into public.user_subscriptions (user_id, tier, status) values
  ('00000000-0000-0000-0000-0000000000d1', 'premium', 'active'),
  ('00000000-0000-0000-0000-0000000000d2', 'premium', 'active')
on conflict (user_id) do update set tier = excluded.tier, status = excluded.status;

insert into public.positions (id, user_id, ticker, quantity, purchase_price, purchase_date) values
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000d1', 'VOO', 2, 400, now());

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000d1","role":"authenticated"}';

insert into public.allocation_plans (user_id, targets, contribution_day, contribution_amount)
values ('00000000-0000-0000-0000-0000000000d1', '{"VOO": 60, "BND": 40}', 1, 500);

do $$
begin
  begin
    update public.allocation_plans set contribution_day = 31
     where user_id = '00000000-0000-0000-0000-0000000000d1';
    raise exception 'aceptó el día 31';
  exception when check_violation then null;
  end;
  begin
    update public.allocation_plans set contribution_amount = 0
     where user_id = '00000000-0000-0000-0000-0000000000d1';
    raise exception 'aceptó un aporte de 0';
  exception when check_violation then null;
  end;
end $$;

set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000d2","role":"authenticated"}';
-- Sin recordatorio: no sale en los inputs.
insert into public.allocation_plans (user_id, targets)
values ('00000000-0000-0000-0000-0000000000d2', '{"VOO": 100}');

reset role;

do $$
declare
  r record;
  n int;
begin
  select count(*) into n from public.contribution_reminder_inputs(array[
    '00000000-0000-0000-0000-0000000000d1'::uuid,
    '00000000-0000-0000-0000-0000000000d2'::uuid]);
  if n <> 1 then
    raise exception 'tendría que devolver solo el plan con recordatorio, devolvió %', n;
  end if;
  select * into r from public.contribution_reminder_inputs(array[
    '00000000-0000-0000-0000-0000000000d1'::uuid]);
  if r.contribution_day <> 1 or r.contribution_amount <> 500 then
    raise exception 'día o monto mal: % %', r.contribution_day, r.contribution_amount;
  end if;
  if (r.holdings -> 0 ->> 'symbol') <> 'VOO' then
    raise exception 'no trae lo que tiene: %', r.holdings;
  end if;

  -- Si baja a Free, no sale.
  update public.user_subscriptions set tier = 'free'
   where user_id = '00000000-0000-0000-0000-0000000000d1';
  select count(*) into n from public.contribution_reminder_inputs(array[
    '00000000-0000-0000-0000-0000000000d1'::uuid]);
  if n <> 0 then
    raise exception 'un Free no tendría que tener recordatorio';
  end if;

  insert into public.notification_outbox (user_id, kind, dedupe_key)
    values ('00000000-0000-0000-0000-0000000000d1', 'contribution_reminder', 'contribution_reminder:2026-10');
end $$;

-- La app no puede leer los inputs de nadie.
set local role authenticated;
do $$
begin
  begin
    perform public.contribution_reminder_inputs(array['00000000-0000-0000-0000-0000000000d2'::uuid]);
    raise exception 'la app pudo leer contribution_reminder_inputs';
  exception when insufficient_privilege then null;
  end;
end $$;

select 'CONTRIBUTION_DB_TEST_OK';

rollback;
