-- Test de la migración 20261016000000_allocation_plans.sql (plan de
-- cartera).
--
-- Corre contra una base con las migraciones aplicadas (supabase start, o un
-- Postgres con los stubs de auth/vault/roles). Cada chequeo que falla corta
-- con una excepción; si termina, imprime ALLOCATION_DB_TEST_OK.
--
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/allocation_plans_db_test.sql
--
-- Todo corre dentro de una transacción que se deshace al final.

begin;

delete from public.allocation_plans;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000c1', 'premium@test.local'),
  ('00000000-0000-0000-0000-0000000000c2', 'free@test.local');

insert into public.user_subscriptions (user_id, tier, status) values
  ('00000000-0000-0000-0000-0000000000c1', 'premium', 'active'),
  ('00000000-0000-0000-0000-0000000000c2', 'free', 'active')
on conflict (user_id) do update set tier = excluded.tier, status = excluded.status;

insert into public.positions (id, user_id, ticker, quantity, purchase_price, purchase_date) values
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000c1', 'voo', 2, 400, now()),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000c1', 'VOO', 1, 430, now()),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000c1', 'BND', 10, 70, now());

insert into public.market_quotes (symbol, price) values ('VOO', 500);

-- ── Desde la app (Premium) ────────────────────────────────────────────────

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000c1","role":"authenticated"}';

insert into public.allocation_plans (user_id, targets)
values ('00000000-0000-0000-0000-0000000000c1', '{"VOO": 60, "BND": 40}');

do $$
begin
  -- No suman 100.
  begin
    update public.allocation_plans set targets = '{"VOO": 60, "BND": 30}'
     where user_id = '00000000-0000-0000-0000-0000000000c1';
    raise exception 'should have failed: sum';
  exception when others then
    if sqlerrm <> 'allocation_targets_must_sum_100' then raise; end if;
  end;
  -- Símbolo inválido.
  begin
    update public.allocation_plans set targets = '{"voo; drop": 100}'
     where user_id = '00000000-0000-0000-0000-0000000000c1';
    raise exception 'should have failed: symbol';
  exception when others then
    if sqlerrm <> 'allocation_invalid_targets' then raise; end if;
  end;
  -- Valor no numérico o fuera de rango.
  begin
    update public.allocation_plans set targets = '{"VOO": "100"}'
     where user_id = '00000000-0000-0000-0000-0000000000c1';
    raise exception 'should have failed: type';
  exception when others then
    if sqlerrm <> 'allocation_invalid_targets' then raise; end if;
  end;
  -- Umbral fuera de rango.
  begin
    update public.allocation_plans set drift_threshold = 0
     where user_id = '00000000-0000-0000-0000-0000000000c1';
    raise exception 'should have failed: threshold';
  exception when check_violation then null;
  end;
  -- ±0,5 de redondeo está bien; vacío también (sin plan).
  update public.allocation_plans set targets = '{"VOO": 60.3, "BND": 39.9}'
   where user_id = '00000000-0000-0000-0000-0000000000c1';
  update public.allocation_plans set targets = '{}'
   where user_id = '00000000-0000-0000-0000-0000000000c1';
  update public.allocation_plans set targets = '{"VOO": 60, "BND": 40}', drift_threshold = 5
   where user_id = '00000000-0000-0000-0000-0000000000c1';
end $$;

-- No ve ni toca el plan de otro.
do $$
begin
  if exists (select 1 from public.allocation_plans where user_id <> '00000000-0000-0000-0000-0000000000c1') then
    raise exception 'sees other plans';
  end if;
end $$;

-- ── Free no puede guardar un plan ─────────────────────────────────────────

set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000c2","role":"authenticated"}';

do $$
begin
  begin
    insert into public.allocation_plans (user_id, targets)
    values ('00000000-0000-0000-0000-0000000000c2', '{"VOO": 100}');
    raise exception 'should have failed: free';
  exception when others then
    if sqlerrm <> 'allocation_plan_requires_premium' then raise; end if;
  end;
  begin
    insert into public.allocation_plans (user_id, targets)
    values ('00000000-0000-0000-0000-0000000000c1', '{"VOO": 100}');
    raise exception 'should have failed: other user';
  exception when insufficient_privilege or unique_violation then null;
  end;
end $$;

-- La app no puede leer los insumos del aviso.
do $$
begin
  begin
    perform public.allocation_drift_inputs(array['00000000-0000-0000-0000-0000000000c1'::uuid]);
    raise exception 'should have failed: rpc';
  exception when insufficient_privilege then null;
  end;
end $$;

-- ── daily-jobs (service role) ─────────────────────────────────────────────

reset role;

do $$
declare
  v_holdings jsonb;
  v_voo jsonb;
  v_bnd jsonb;
  v_count int;
begin
  select holdings into v_holdings from public.allocation_drift_inputs(
    array['00000000-0000-0000-0000-0000000000c1'::uuid, '00000000-0000-0000-0000-0000000000c2'::uuid]);
  select count(*) into v_count from public.allocation_drift_inputs(
    array['00000000-0000-0000-0000-0000000000c1'::uuid, '00000000-0000-0000-0000-0000000000c2'::uuid]);
  if v_count <> 1 then raise exception 'expected 1 plan, got %', v_count; end if;
  select e into v_voo from jsonb_array_elements(v_holdings) e where e->>'symbol' = 'VOO';
  select e into v_bnd from jsonb_array_elements(v_holdings) e where e->>'symbol' = 'BND';
  -- VOO sumado (2 + 1) con el precio del servidor; BND con el de compra.
  if (v_voo->>'quantity')::numeric <> 3 or (v_voo->>'price')::numeric <> 500 then
    raise exception 'bad VOO %', v_voo;
  end if;
  if (v_bnd->>'price')::numeric <> 70 then raise exception 'bad BND %', v_bnd; end if;

  -- Con los avisos apagados, o si baja a Free, no aparece.
  update public.allocation_plans set notify = false where user_id = '00000000-0000-0000-0000-0000000000c1';
  select count(*) into v_count from public.allocation_drift_inputs(array['00000000-0000-0000-0000-0000000000c1'::uuid]);
  if v_count <> 0 then raise exception 'notify off still listed'; end if;
  update public.allocation_plans set notify = true where user_id = '00000000-0000-0000-0000-0000000000c1';
  update public.user_subscriptions set tier = 'free' where user_id = '00000000-0000-0000-0000-0000000000c1';
  select count(*) into v_count from public.allocation_drift_inputs(array['00000000-0000-0000-0000-0000000000c1'::uuid]);
  if v_count <> 0 then raise exception 'free still listed'; end if;
end $$;

-- ── Pesos para el aviso de resultados (20261016000300) ────────────────────

do $$
declare
  v_voo numeric;
  v_bnd numeric;
begin
  -- VOO: 3 × 500 = 1500; BND: 10 × 70 = 700. Total 2200.
  select weight_pct into v_voo from public.push_holding_weights(
    array['00000000-0000-0000-0000-0000000000c1'::uuid]) where symbol = 'VOO';
  select weight_pct into v_bnd from public.push_holding_weights(
    array['00000000-0000-0000-0000-0000000000c1'::uuid]) where symbol = 'BND';
  if v_voo <> 68.2 or v_bnd <> 31.8 then
    raise exception 'weights: VOO % BND %', v_voo, v_bnd;
  end if;
end $$;

select 'ALLOCATION_DB_TEST_OK' as result;

rollback;
