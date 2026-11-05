-- Test de 20261026000000_product_events.sql: cada usuario inserta solo sus
-- eventos, no los puede leer, los nombres raros y las props enormes se
-- rechazan, y `product_funnel` da los minutos hasta cada paso.
--
-- Corre contra una base con las migraciones aplicadas (supabase start, o un
-- Postgres con los stubs de auth/vault/roles). Si termina, imprime
-- PRODUCT_EVENTS_DB_TEST_OK.
--
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/product_events_db_test.sql
--
-- Todo corre dentro de una transacción que se deshace al final.

begin;

insert into auth.users (id, email, created_at) values
  ('00000000-0000-0000-0000-0000000000e1', 'pe1@test.local', now() - interval '10 minutes'),
  ('00000000-0000-0000-0000-0000000000e2', 'pe2@test.local', now());

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000e1","role":"authenticated"}';

insert into public.product_events (name, props) values
  ('onboarding_started', '{}'),
  ('portfolio_loaded', '{"method":"file","count":7}');

do $$
begin
  -- Eventos de otro usuario: la policy lo impide.
  begin
    insert into public.product_events (user_id, name)
    values ('00000000-0000-0000-0000-0000000000e2', 'portfolio_loaded');
    raise exception 'debía fallar: user_id ajeno';
  exception when insufficient_privilege then null;
  end;

  -- La app no lee eventos (ni los suyos).
  begin
    perform 1 from public.product_events;
    raise exception 'debía fallar: select';
  exception when insufficient_privilege then null;
  end;

  -- Ni el embudo.
  begin
    perform 1 from public.product_funnel;
    raise exception 'debía fallar: select del embudo';
  exception when insufficient_privilege then null;
  end;

  begin
    insert into public.product_events (name) values ('Nombre Raro!');
    raise exception 'debía fallar: nombre';
  exception when check_violation then null;
  end;

  begin
    insert into public.product_events (name, props)
    values ('diagnosis_seen', jsonb_build_object('x', repeat('a', 4000)));
    raise exception 'debía fallar: props enormes';
  exception when check_violation then null;
  end;
end;
$$;

reset role;

do $$
declare
  f record;
begin
  select * into f from public.product_funnel
   where user_id = '00000000-0000-0000-0000-0000000000e1';
  if f.load_method is distinct from 'file' then
    raise exception 'load_method: %', f.load_method;
  end if;
  if f.min_to_portfolio is null or f.min_to_portfolio < 9 or f.min_to_portfolio > 11 then
    raise exception 'min_to_portfolio: %', f.min_to_portfolio;
  end if;
  if f.min_to_diagnosis is not null then
    raise exception 'min_to_diagnosis debía ser null';
  end if;

  select * into f from public.product_funnel
   where user_id = '00000000-0000-0000-0000-0000000000e2';
  if f.min_to_portfolio is not null then
    raise exception 'el usuario 2 no cargó nada';
  end if;
end;
$$;

select 'PRODUCT_EVENTS_DB_TEST_OK';

rollback;
