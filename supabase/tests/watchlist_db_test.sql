-- Test de las migraciones 20261016000100_push_new_kinds.sql y
-- 20261016000200_watchlist.sql (lista de seguimiento).
--
-- Corre contra una base con las migraciones aplicadas (supabase start, o un
-- Postgres con los stubs de auth/vault/roles). Cada chequeo que falla corta
-- con una excepción; si termina, imprime WATCHLIST_DB_TEST_OK.
--
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/watchlist_db_test.sql
--
-- Todo corre dentro de una transacción que se deshace al final.

begin;

delete from public.watchlist_items;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000d1', 'premium@test.local'),
  ('00000000-0000-0000-0000-0000000000d2', 'free@test.local');

insert into public.user_subscriptions (user_id, tier, status) values
  ('00000000-0000-0000-0000-0000000000d1', 'premium', 'active'),
  ('00000000-0000-0000-0000-0000000000d2', 'free', 'active')
on conflict (user_id) do update set tier = excluded.tier, status = excluded.status;

insert into public.push_devices (user_id, token, platform, locale, timezone)
values ('00000000-0000-0000-0000-0000000000d1', 'token-d1-xxxxxxxxxxxxxxxxxxxx', 'ios', 'es', 'America/Montevideo');

insert into public.positions (id, user_id, ticker, quantity, purchase_price, purchase_date)
values (gen_random_uuid(), '00000000-0000-0000-0000-0000000000d1', 'nvda', 1, 100, now());

-- ── Desde la app ──────────────────────────────────────────────────────────

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000d1","role":"authenticated"}';

insert into public.watchlist_items (user_id, symbol, added_price)
values ('00000000-0000-0000-0000-0000000000d1', 'amzn', 180),
       ('00000000-0000-0000-0000-0000000000d1', 'NVDA', 120);

do $$
declare
  v_row public.watchlist_items;
begin
  select * into v_row from public.watchlist_items where symbol = 'AMZN';
  if v_row.id is null then raise exception 'symbol not uppercased'; end if;

  -- Solo `notify` se edita.
  update public.watchlist_items set notify = false, added_price = 1, symbol = 'TSLA'
   where id = v_row.id;
  select * into v_row from public.watchlist_items where id = v_row.id;
  if v_row.notify or v_row.added_price <> 180 or v_row.symbol <> 'AMZN' then
    raise exception 'guard let through %', row_to_json(v_row);
  end if;
  update public.watchlist_items set notify = true where id = v_row.id;

  -- Repetido: no.
  begin
    insert into public.watchlist_items (user_id, symbol)
    values ('00000000-0000-0000-0000-0000000000d1', 'AMZN');
    raise exception 'should have failed: duplicate';
  exception when unique_violation then null;
  end;
end $$;

-- Tope de Premium (30).
do $$
begin
  for i in 1..28 loop
    insert into public.watchlist_items (user_id, symbol)
    values ('00000000-0000-0000-0000-0000000000d1', 'T' || i);
  end loop;
  begin
    insert into public.watchlist_items (user_id, symbol)
    values ('00000000-0000-0000-0000-0000000000d1', 'ONEMORE');
    raise exception 'should have failed: limit';
  exception when others then
    if sqlerrm <> 'watchlist_limit_reached' then raise; end if;
  end;
  delete from public.watchlist_items where symbol like 'T%';
end $$;

-- Free: tope 0.
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000d2","role":"authenticated"}';

do $$
begin
  if exists (select 1 from public.watchlist_items) then
    raise exception 'free sees other lists';
  end if;
  begin
    insert into public.watchlist_items (user_id, symbol)
    values ('00000000-0000-0000-0000-0000000000d2', 'AMZN');
    raise exception 'should have failed: free';
  exception when others then
    if sqlerrm <> 'watchlist_limit_reached' then raise; end if;
  end;
  begin
    perform public.watchlist_watch_items();
    raise exception 'should have failed: rpc';
  exception when insufficient_privilege then null;
  end;
end $$;

-- ── market-watch (service role) ───────────────────────────────────────────

reset role;

do $$
declare
  v_symbols text;
begin
  select string_agg(symbol, ',' order by symbol) into v_symbols from public.watchlist_watch_items();
  -- NVDA está en la lista pero también en la cartera: lo cubre la cartera.
  if v_symbols is distinct from 'AMZN' then raise exception 'watch items: %', v_symbols; end if;

  -- Con los movimientos apagados, no.
  insert into public.notification_preferences (user_id, big_moves)
  values ('00000000-0000-0000-0000-0000000000d1', false);
  if exists (select 1 from public.watchlist_watch_items()) then
    raise exception 'big_moves off still watched';
  end if;
  update public.notification_preferences set big_moves = true
   where user_id = '00000000-0000-0000-0000-0000000000d1';

  -- El outbox acepta los tipos nuevos.
  insert into public.notification_outbox (user_id, kind, dedupe_key)
  values ('00000000-0000-0000-0000-0000000000d1', 'watchlist_move', 'watchlist_move:AMZN:2026-10-16:down'),
         ('00000000-0000-0000-0000-0000000000d1', 'allocation_drift', 'allocation_drift:2026-10-19');

  -- Y cuentan para el tope diario.
  insert into public.notification_log (user_id, kind, sent_at)
  values ('00000000-0000-0000-0000-0000000000d1', 'watchlist_move', now());
  if (select automatic_last_24h from public.push_dispatch_context(
        array['00000000-0000-0000-0000-0000000000d1'::uuid])) <> 1 then
    raise exception 'watchlist_move not counted as automatic';
  end if;
end $$;

select 'WATCHLIST_DB_TEST_OK' as result;

rollback;
