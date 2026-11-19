-- Test de la migración 20261117120000_goal_currency.sql (moneda de cada
-- meta).
--
-- Corre contra una base con las migraciones aplicadas (supabase start, o un
-- Postgres con los stubs de auth/vault/roles). Cada chequeo que falla corta
-- con una excepción; si termina, imprime GOAL_CURRENCY_DB_TEST_OK.
--
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/goal_currency_db_test.sql
--
-- Todo corre dentro de una transacción que se deshace al final.

begin;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000d1', 'goals-a@test.local'),
  ('00000000-0000-0000-0000-0000000000d2', 'goals-b@test.local');

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000d1","role":"authenticated"}';

-- Sin moneda (la app vieja, o una meta en dólares): queda en USD.
insert into public.user_goals (id, user_id, label, target_amount, target_date, plan)
values ('00000000-0000-0000-0000-00000000aa01',
        '00000000-0000-0000-0000-0000000000d1', 'Viaje', 18000, '2028-02-12', '{}');

-- En pesos uruguayos.
insert into public.user_goals (id, user_id, label, target_amount, target_date, plan, currency)
values ('00000000-0000-0000-0000-00000000aa02',
        '00000000-0000-0000-0000-0000000000d1', 'Auto', 1000000, '2028-06-01', '{}', 'UYU');

do $$
begin
  if (select currency from public.user_goals
       where id = '00000000-0000-0000-0000-00000000aa01') <> 'USD' then
    raise exception 'default currency should be USD';
  end if;
  if (select currency from public.user_goals
       where id = '00000000-0000-0000-0000-00000000aa02') <> 'UYU' then
    raise exception 'currency should be UYU';
  end if;

  -- Cambiar la moneda de una meta propia.
  update public.user_goals set currency = 'BRL'
   where id = '00000000-0000-0000-0000-00000000aa01';
  if (select currency from public.user_goals
       where id = '00000000-0000-0000-0000-00000000aa01') <> 'BRL' then
    raise exception 'owner should be able to change the currency';
  end if;

  -- Una moneda que la app no ofrece (o mal escrita) no entra.
  begin
    update public.user_goals set currency = 'usd'
     where id = '00000000-0000-0000-0000-00000000aa01';
    raise exception 'should have failed: lowercase code';
  exception when check_violation then null;
  end;
  begin
    update public.user_goals set currency = 'XYZ'
     where id = '00000000-0000-0000-0000-00000000aa01';
    raise exception 'should have failed: unknown code';
  exception when check_violation then null;
  end;
end $$;

-- Otro usuario no ve ni cambia la moneda de mis metas (RLS de siempre).
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000d2","role":"authenticated"}';

do $$
declare
  n int;
begin
  update public.user_goals set currency = 'ARS'
   where id = '00000000-0000-0000-0000-00000000aa02';
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'another user changed my goal currency'; end if;
end $$;

reset role;

do $$
begin
  if (select currency from public.user_goals
       where id = '00000000-0000-0000-0000-00000000aa02') <> 'UYU' then
    raise exception 'currency changed by another user';
  end if;
end $$;

select 'GOAL_CURRENCY_DB_TEST_OK';

rollback;
