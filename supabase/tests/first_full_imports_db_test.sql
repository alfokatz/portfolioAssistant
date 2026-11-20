-- Test de 20261105100200_free_first_import.sql y 20261105100300_free_watchlist.sql
-- (Free: primera importación entera y watchlist de 3).
--
-- Corre contra una base con las migraciones aplicadas (supabase start). Si
-- termina, imprime FIRST_FULL_IMPORTS_DB_TEST_OK.
--
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/first_full_imports_db_test.sql
--
-- Todo corre dentro de una transacción que se deshace al final.

begin;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000f1', 'free1@test.local'),
  ('00000000-0000-0000-0000-0000000000f2', 'free2@test.local'),
  ('00000000-0000-0000-0000-0000000000f3', 'premium@test.local');
insert into public.user_subscriptions (user_id, tier, status) values
  ('00000000-0000-0000-0000-0000000000f1', 'free', 'active'),
  ('00000000-0000-0000-0000-0000000000f2', 'free', 'active'),
  ('00000000-0000-0000-0000-0000000000f3', 'premium', 'active')
on conflict (user_id) do update set tier = excluded.tier, status = excluded.status;

create function pg_temp.as_user(u text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
end;
$$;

-- Sin sesión no hay cupo.
set local role anon;
do $$
begin
  perform set_config('request.jwt.claims', '', true);
  begin
    perform public.first_import_status();
    raise exception 'anon pudo llamar first_import_status';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

set local role authenticated;

-- 1. Status: disponible.
do $$
declare r jsonb;
begin
  perform pg_temp.as_user('00000000-0000-0000-0000-0000000000f1');
  r := public.first_import_status();
  if r <> '{"available": true}'::jsonb then raise exception 'status inicial: %', r; end if;
end $$;

-- 2. Argumentos inválidos: no gastan el cupo.
do $$
declare r jsonb;
begin
  perform pg_temp.as_user('00000000-0000-0000-0000-0000000000f1');
  foreach r in array array[
    public.claim_first_import('corto', 'file', 18),
    public.claim_first_import('import-id-0001', 'excel', 18),
    public.claim_first_import('import-id-0001', 'file', 0),
    public.claim_first_import('import-id-0001', 'file', null),
    public.claim_first_import(null, 'file', 18),
    public.claim_first_import('con espacios!!', 'file', 18)
  ] loop
    if r <> '{"ok": false, "reason": "invalid_args"}'::jsonb then raise exception 'invalid_args: %', r; end if;
  end loop;
  if (public.first_import_status()->>'available')::boolean is not true then
    raise exception 'una llamada inválida gastó el cupo';
  end if;
end $$;

-- 3. Primer claim, reintento con el mismo import_id y otro import_id.
do $$
declare r jsonb;
begin
  perform pg_temp.as_user('00000000-0000-0000-0000-0000000000f1');
  r := public.claim_first_import('import-id-0001', 'screenshot', 18);
  if r <> '{"ok": true, "reused": false}'::jsonb then raise exception 'primer claim: %', r; end if;
  r := public.claim_first_import('import-id-0001', 'screenshot', 18);
  if r <> '{"ok": true, "reused": true}'::jsonb then raise exception 'reintento: %', r; end if;
  r := public.claim_first_import('import-id-0002', 'file', 12);
  if r <> '{"ok": false, "reason": "already_used"}'::jsonb then raise exception 'segundo import: %', r; end if;
  r := public.first_import_status();
  if (r->>'available')::boolean or r->>'used_at' is null then raise exception 'status usado: %', r; end if;
end $$;

-- 4. Otro usuario no ve el cupo del primero y tiene el suyo.
do $$
declare r jsonb;
begin
  perform pg_temp.as_user('00000000-0000-0000-0000-0000000000f2');
  if (public.first_import_status()->>'available')::boolean is not true then
    raise exception 'f2 ve el cupo de f1';
  end if;
  if exists (select 1 from public.first_full_imports) then raise exception 'f2 ve filas de f1'; end if;
  r := public.claim_first_import('import-id-0003', 'note', 5);
  if r <> '{"ok": true, "reused": false}'::jsonb then raise exception 'claim de f2: %', r; end if;
  -- El reintento de f2 con el import_id de f1 no se confunde con el de f1.
  r := public.claim_first_import('import-id-0001', 'note', 5);
  if r <> '{"ok": false, "reason": "already_used"}'::jsonb then raise exception 'cruce de import_id: %', r; end if;
end $$;

-- 5. Desde la app no se escribe directo en la tabla.
do $$
begin
  perform pg_temp.as_user('00000000-0000-0000-0000-0000000000f1');
  begin
    delete from public.first_full_imports;
    raise exception 'authenticated pudo borrar el cupo';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.first_full_imports (user_id, import_id, origin, positions)
    values ('00000000-0000-0000-0000-0000000000f3', 'import-id-0009', 'file', 3);
    raise exception 'authenticated pudo insertar el cupo';
  exception when insufficient_privilege then null;
  end;
end $$;

-- 6. Watchlist de Free: 3 entran y el 4.º da watchlist_limit_reached.
do $$
begin
  perform pg_temp.as_user('00000000-0000-0000-0000-0000000000f1');
  insert into public.watchlist_items (user_id, symbol) values
    ('00000000-0000-0000-0000-0000000000f1', 'AMZN'),
    ('00000000-0000-0000-0000-0000000000f1', 'TSLA'),
    ('00000000-0000-0000-0000-0000000000f1', 'MELI');
  begin
    insert into public.watchlist_items (user_id, symbol)
    values ('00000000-0000-0000-0000-0000000000f1', 'NVDA');
    raise exception 'el 4.º de Free no falló';
  exception when others then
    if sqlerrm <> 'watchlist_limit_reached' then raise; end if;
  end;
end $$;

reset role;

do $$
begin
  if (select watchlist from public.plan_limits where tier = 'free') <> 3 then
    raise exception 'plan_limits free watchlist: %', (select watchlist from public.plan_limits where tier = 'free');
  end if;
  if (select watchlist from public.plan_limits where tier = 'premium') <> 30 then raise exception 'premium watchlist'; end if;
  if (select watchlist from public.plan_limits where tier = 'gold') <> 100 then raise exception 'gold watchlist'; end if;
end $$;

-- 7. market-watch ve la lista de Free con avisos (con dispositivo y sin la
--    acción en cartera).
insert into public.push_devices (user_id, token, platform, locale, timezone)
values ('00000000-0000-0000-0000-0000000000f1', 'token-f1-xxxxxxxxxxxxxxxxxxxx', 'ios', 'es', 'America/Montevideo');
insert into public.positions (id, user_id, ticker, quantity, purchase_price, purchase_date)
values (gen_random_uuid(), '00000000-0000-0000-0000-0000000000f1', 'meli', 1, 100, now());
do $$
declare v_symbols text;
begin
  select string_agg(symbol, ',' order by symbol) into v_symbols
    from public.watchlist_watch_items() where user_id = '00000000-0000-0000-0000-0000000000f1';
  if v_symbols is distinct from 'AMZN,TSLA' then raise exception 'watch items de Free: %', v_symbols; end if;
end $$;

-- 7b. Tope por plan en lo que mira market-watch: quien bajó de plan solo
--     conserva los más viejos hasta el tope de su plan actual.
update public.user_subscriptions set tier = 'free' where user_id = '00000000-0000-0000-0000-0000000000f3';
insert into public.push_devices (user_id, token, platform, locale, timezone)
values ('00000000-0000-0000-0000-0000000000f3', 'token-f3-xxxxxxxxxxxxxxxxxxxx', 'ios', 'es', 'America/Montevideo');
insert into public.watchlist_items (user_id, symbol, created_at) values
  ('00000000-0000-0000-0000-0000000000f3', 'A1', now() - interval '5 days'),
  ('00000000-0000-0000-0000-0000000000f3', 'A2', now() - interval '4 days'),
  ('00000000-0000-0000-0000-0000000000f3', 'A3', now() - interval '3 days'),
  ('00000000-0000-0000-0000-0000000000f3', 'A4', now() - interval '2 days'),
  ('00000000-0000-0000-0000-0000000000f3', 'A5', now() - interval '1 days');
do $$
declare v_symbols text;
begin
  select string_agg(symbol, ',' order by symbol) into v_symbols
    from public.watchlist_watch_items() where user_id = '00000000-0000-0000-0000-0000000000f3';
  if v_symbols is distinct from 'A1,A2,A3' then raise exception 'tope de watch items de Free: %', v_symbols; end if;
end $$;

-- 8. Borrar la cuenta se lleva el cupo (FK con cascade).
delete from auth.users where id = '00000000-0000-0000-0000-0000000000f1';
do $$
begin
  if exists (select 1 from public.first_full_imports where user_id = '00000000-0000-0000-0000-0000000000f1') then
    raise exception 'el cupo sobrevivió al borrado de la cuenta';
  end if;
  if not exists (select 1 from public.first_full_imports where user_id = '00000000-0000-0000-0000-0000000000f2') then
    raise exception 'se borró el cupo de otro usuario';
  end if;
end $$;

select 'FIRST_FULL_IMPORTS_DB_TEST_OK' as result;

rollback;
