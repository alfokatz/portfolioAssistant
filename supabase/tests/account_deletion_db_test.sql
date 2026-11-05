-- Test de "no queda nada" del borrado de cuenta
-- (20261102130000_account_deletion.sql; spec 2026-11-02-borrado-de-cuenta.md §4.1).
--
-- A tiene una fila en cada tabla con datos de usuario, secretos reales en
-- Vault, su uuid en flags de app_config y su mail en waitlist. B es el
-- control. C (mail sin confirmar) y D (OAuth sin confirmar) prueban la regla
-- de compliance §6.1 sobre waitlist.
--
-- La guardia de catálogo corta si aparece una tabla de `public` con
-- `user_id` (o una FK a auth.users) que no está en el inventario de abajo:
-- una tabla nueva tiene que decidir cómo se borra antes de pasar este test.
--
-- Corre contra una base con las migraciones aplicadas (supabase start, o un
-- Postgres con los stubs de auth/vault/roles). Si termina, imprime
-- ACCOUNT_DELETION_DB_TEST_OK.
--
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/account_deletion_db_test.sql
--
-- Todo corre dentro de una transacción que se deshace al final.

begin;

-- Inventario: tablas de public con user_id. `cascade` = FK a auth.users con
-- on delete cascade; `trigger` = sin FK, la limpia _account_purge_before_delete.
create temp table inventory (table_name text primary key, how text not null) on commit drop;
insert into inventory values
  ('ai_turn_usage', 'cascade'), ('ai_usage_monthly', 'cascade'), ('allocation_plans', 'cascade'),
  ('api_rate_limits', 'cascade'), ('binance_connections', 'cascade'), ('binance_keys', 'cascade'),
  ('closed_positions', 'cascade'), ('etoro_connections', 'cascade'), ('etoro_oauth_states', 'cascade'),
  ('etoro_tokens', 'cascade'), ('investor_profiles', 'cascade'), ('market_tastes', 'cascade'), ('news_context_usage', 'cascade'),
  ('notification_log', 'cascade'), ('notification_outbox', 'cascade'), ('notification_preferences', 'cascade'),
  ('porty_topics', 'cascade'), ('positions', 'cascade'), ('price_alerts', 'cascade'),
  ('product_events', 'cascade'), ('push_devices', 'cascade'), ('snaptrade_connections', 'cascade'),
  ('snaptrade_users', 'cascade'), ('subscription_events', 'cascade'), ('user_goals', 'cascade'),
  ('user_memories', 'cascade'), ('user_subscriptions', 'cascade'), ('watchlist_items', 'cascade'),
  ('web_search_usage', 'cascade'), ('weekly_free_analysis', 'cascade'), ('weekly_reports', 'cascade'),
  ('subscription_sync_log', 'trigger');

-- ── Guardia de catálogo ──────────────────────────────────────────────────────

do $$
declare
  v_missing text;
  v_bad text;
begin
  select string_agg(c.table_name, ', ') into v_missing
  from information_schema.columns c
  join information_schema.tables t
    on t.table_schema = c.table_schema and t.table_name = c.table_name and t.table_type = 'BASE TABLE'
  where c.table_schema = 'public' and c.column_name = 'user_id'
    and c.table_name not in (select table_name from inventory);
  if v_missing is not null then
    raise exception 'tablas con user_id fuera del inventario del borrado: % (decidir cascade o trigger)', v_missing;
  end if;

  select string_agg(conrelid::regclass::text, ', ') into v_missing
  from pg_constraint
  where contype = 'f' and confrelid = 'auth.users'::regclass
    and connamespace = 'public'::regnamespace
    and conrelid::regclass::text not in (select 'public.' || table_name from inventory where how = 'cascade')
    and conrelid::regclass::text not in (select table_name from inventory where how = 'cascade');
  if v_missing is not null then
    raise exception 'FK a auth.users fuera del inventario: %', v_missing;
  end if;

  -- Solo las tablas de Porty (public): los esquemas de Supabase (auth,
  -- storage…) traen sus propias FK, que cambian entre versiones del servicio
  -- (p. ej. auth.scim_users, de SSO/SCIM, que Porty no usa).
  select string_agg(conrelid::regclass::text || ' (' || conname || ')', ', ') into v_bad
  from pg_constraint
  where contype = 'f' and confrelid = 'auth.users'::regclass and confdeltype <> 'c'
    and connamespace = 'public'::regnamespace;
  if v_bad is not null then
    raise exception 'FK a auth.users sin on delete cascade: %', v_bad;
  end if;

  -- Toda tabla marcada cascade tiene su FK (si no, el borrado la dejaría).
  select string_agg(i.table_name, ', ') into v_missing
  from inventory i
  where i.how = 'cascade'
    and not exists (
      select 1 from pg_constraint c
      where c.contype = 'f' and c.confrelid = 'auth.users'::regclass
        and c.conrelid = ('public.' || i.table_name)::regclass and c.confdeltype = 'c'
    );
  if v_missing is not null then
    raise exception 'tablas del inventario sin FK cascade: %', v_missing;
  end if;
end $$;

-- ── Usuarios ────────────────────────────────────────────────────────────────

insert into auth.users (id, email, email_confirmed_at, raw_app_meta_data) values
  ('00000000-0000-0000-0000-0000000de1a1', 'borrar@test.local', now(), '{"provider":"email"}'),
  ('00000000-0000-0000-0000-0000000de1b2', 'control@test.local', now(), '{"provider":"email"}'),
  ('00000000-0000-0000-0000-0000000de1c3', 'sinconfirmar@test.local', null, '{"provider":"email"}'),
  ('00000000-0000-0000-0000-0000000de1d4', 'oauth@test.local', null, '{"provider":"google"}');

update public.user_subscriptions set tier = 'premium' where user_id = '00000000-0000-0000-0000-0000000de1a1';
update public.user_subscriptions set tier = 'gold' where user_id = '00000000-0000-0000-0000-0000000de1b2';

-- Una fila en cada tabla del inventario para [u].
create function pg_temp.seed(u uuid, tag text) returns void language plpgsql as $$
begin
  insert into public.ai_turn_usage (turn_id, user_id, tier, model) values ('turn-' || tag || '-0001', u, 'premium', 'm');
  insert into public.ai_usage_monthly (user_id, month) values (u, to_char(now(), 'YYYY-MM'))
    on conflict do nothing;
  insert into public.allocation_plans (user_id) values (u);
  insert into public.api_rate_limits (user_id, bucket, window_start) values (u, 'test', date_trunc('minute', now()));
  insert into public.binance_connections (user_id) values (u);
  perform public.binance_keys_save(u, '{"api_key":"k-' || tag || '","api_secret":"s"}');
  insert into public.etoro_connections (user_id) values (u);
  insert into public.etoro_oauth_states (state, user_id, code_verifier, nonce) values ('state-' || tag, u, 'v', 'n');
  perform public.etoro_tokens_save(u, '{"accessToken":"a-' || tag || '","refreshToken":"r","expiresAt":0,"scope":[]}');
  insert into public.snaptrade_connections (user_id) values (u);
  perform public.snaptrade_secret_save(u, '{"user_id":"st-' || tag || '","user_secret":"s"}');
  insert into public.investor_profiles (user_id, risk_tolerance, horizon, objective) values (u, 'moderate', 'long', 'growth');
  insert into public.market_tastes (user_id, turn_id, month, tickers) values (u, 'taste-' || tag || '-0001', to_char(now(), 'YYYY-MM'), array['NVDA']);
  insert into public.news_context_usage (user_id, day) values (u, current_date);
  insert into public.notification_log (user_id, kind) values (u, 'test');
  insert into public.notification_outbox (user_id, kind, dedupe_key) values (u, 'test', 'k-' || tag);
  insert into public.notification_preferences (user_id) values (u);
  insert into public.porty_topics (user_id, ticker, question) values (u, 'AAPL', 'q');
  insert into public.positions (id, user_id, ticker, quantity, purchase_price, purchase_date)
    values (gen_random_uuid(), u, 'AAPL', 1, 100, now());
  -- Importada de eToro: el trigger de solo lectura no tiene que frenar el cascade.
  insert into public.positions (id, user_id, ticker, quantity, purchase_price, purchase_date, source, external_id)
    values (gen_random_uuid(), u, 'TSLA', 1, 100, now(), 'etoro', 'etoro-' || tag);
  insert into public.closed_positions (id, user_id, ticker, quantity, avg_purchase_price, close_price, close_date)
    values (gen_random_uuid(), u, 'MSFT', 1, 100, 110, now());
  insert into public.price_alerts (user_id, symbol, condition, target) values (u, 'AAPL', 'above', 300);
  insert into public.product_events (user_id, name) values (u, 'paywall_viewed');
  insert into public.push_devices (user_id, token, platform) values (u, 'push-token-' || tag || '-0123456789', 'ios');
  insert into public.subscription_events (event_id, user_id, event_type) values ('ev-' || tag, u, 'INITIAL_PURCHASE');
  insert into public.subscription_sync_log (user_id, outcome) values (u::text, 'synced:premium');
  insert into public.user_goals (user_id, label, target_amount, target_date, plan)
    values (u, 'Casa', 1000, current_date + 365, '{}'::jsonb);
  insert into public.user_memories (user_id, content) values (u, 'Ahorra para una casa');
  insert into public.watchlist_items (user_id, symbol) values (u, 'NVDA');
  insert into public.web_search_usage (user_id, day) values (u, current_date);
  insert into public.weekly_free_analysis (user_id, week_start) values (u, date_trunc('week', now())::date);
  insert into public.weekly_reports (user_id, week_start, status) values (u, date_trunc('week', now())::date, 'ready');
end;
$$;

select pg_temp.seed('00000000-0000-0000-0000-0000000de1a1', 'a');
select pg_temp.seed('00000000-0000-0000-0000-0000000de1b2', 'b');

-- Un log viejo con el uuid en mayúsculas (user_id es text).
insert into public.subscription_sync_log (user_id, outcome)
values (upper('00000000-0000-0000-0000-0000000de1a1'), 'ignored');

-- Secreto huérfano de SnapTrade (falla vieja a mitad de un save): el puntero
-- apunta a otro secreto sin nombre y el nombrado quedó suelto.
do $$
declare
  v_new uuid;
begin
  v_new := vault.create_secret('{"user_id":"st-a2","user_secret":"s"}', null, 'snaptrade sin nombre');
  update public.snaptrade_users set vault_secret_id = v_new where user_id = '00000000-0000-0000-0000-0000000de1a1';
end $$;

-- Flags de rollout con los uuids (uno en mayúsculas).
insert into public.app_config (key, value) values
  ('test_rollout_a', jsonb_build_object('percent', 0, 'users',
     jsonb_build_array('00000000-0000-0000-0000-0000000de1a1', '00000000-0000-0000-0000-0000000de1b2'))),
  ('test_rollout_b', jsonb_build_object('enabled', false, 'allow_users',
     jsonb_build_array(upper('00000000-0000-0000-0000-0000000de1a1')))),
  ('test_rollout_c', '{"users": "no es un array"}'::jsonb)
on conflict (key) do update set value = excluded.value;

-- Waitlist de la landing.
insert into public.waitlist (email, variant, ref_code, consent) values
  ('borrar@test.local', 'a', 'AAAAA2', true),
  ('control@test.local', 'a', 'BBBBB2', true),
  ('sinconfirmar@test.local', 'a', 'CCCCC2', true),
  ('oauth@test.local', 'a', 'DDDDD2', true);

-- Foto antes del borrado.
create temp table secret_ids on commit drop as
  select s.id from vault.secrets s
  where s.id in (select vault_secret_id from public.binance_keys where user_id = '00000000-0000-0000-0000-0000000de1a1'
                 union all select vault_secret_id from public.etoro_tokens where user_id = '00000000-0000-0000-0000-0000000de1a1'
                 union all select vault_secret_id from public.snaptrade_users where user_id = '00000000-0000-0000-0000-0000000de1a1')
     or s.name like '%00000000-0000-0000-0000-0000000de1a1';
create temp table counts_before (table_name text, who text, n int) on commit drop;
create temp table deletions_before on commit drop as
  select coalesce((select deletions from public.account_deletions_daily
                    where day = (now() at time zone 'utc')::date and tier = 'premium'), 0) as n;

do $$
declare
  v_table text;
  v_n int;
begin
  if (select count(*) from secret_ids) <> 4 then
    raise exception 'esperaba 4 secretos de A (3 + huérfano), hay %', (select count(*) from secret_ids);
  end if;
  for v_table in select table_name from inventory loop
    execute format('select count(*) from public.%I where user_id::text = $1', v_table)
      into v_n using '00000000-0000-0000-0000-0000000de1a1';
    if v_n = 0 then raise exception 'el seed de A no cubre %', v_table; end if;
    execute format('select count(*) from public.%I where lower(user_id::text) = $1', v_table)
      into v_n using '00000000-0000-0000-0000-0000000de1b2';
    insert into counts_before values (v_table, 'b', v_n);
  end loop;
end $$;

-- ── Borrado ─────────────────────────────────────────────────────────────────

delete from auth.users where id = '00000000-0000-0000-0000-0000000de1a1';
delete from auth.users where id = '00000000-0000-0000-0000-0000000de1c3';
delete from auth.users where id = '00000000-0000-0000-0000-0000000de1d4';

-- ── No queda nada de A ──────────────────────────────────────────────────────

do $$
declare
  v_table text;
  v_n int;
  v_a text := '00000000-0000-0000-0000-0000000de1a1';
begin
  -- Toda tabla de public con user_id (no solo el inventario).
  for v_table in
    select c.table_name
    from information_schema.columns c
    join information_schema.tables t
      on t.table_schema = c.table_schema and t.table_name = c.table_name and t.table_type = 'BASE TABLE'
    where c.table_schema = 'public' and c.column_name = 'user_id'
  loop
    execute format('select count(*) from public.%I where lower(user_id::text) = $1', v_table) into v_n using v_a;
    if v_n <> 0 then raise exception 'quedaron % filas de A en %', v_n, v_table; end if;
  end loop;

  if exists (select 1 from vault.secrets where id in (select id from secret_ids) or name like '%' || v_a) then
    raise exception 'quedaron secretos de A en Vault';
  end if;

  if exists (select 1 from public.app_config where lower(value::text) like '%' || v_a || '%') then
    raise exception 'A sigue en app_config';
  end if;
  if (select value->'users' from public.app_config where key = 'test_rollout_a')
     <> jsonb_build_array('00000000-0000-0000-0000-0000000de1b2') then
    raise exception 'el flag perdió a B: %', (select value from public.app_config where key = 'test_rollout_a');
  end if;
  if (select value->'allow_users' from public.app_config where key = 'test_rollout_b') <> '[]'::jsonb then
    raise exception 'allow_users en mayúsculas no se limpió';
  end if;
  if (select value->>'users' from public.app_config where key = 'test_rollout_c') <> 'no es un array' then
    raise exception 'tocó un users que no es array';
  end if;

  -- Waitlist: A (confirmado) y D (OAuth) se borran; C (sin confirmar) y B quedan.
  if exists (select 1 from public.waitlist where email in ('borrar@test.local', 'oauth@test.local')) then
    raise exception 'waitlist: no borró el mail confirmado u OAuth';
  end if;
  if (select count(*) from public.waitlist where email in ('sinconfirmar@test.local', 'control@test.local')) <> 2 then
    raise exception 'waitlist: borró un mail sin confirmar o el de B';
  end if;

  if (select deletions from public.account_deletions_daily
       where day = (now() at time zone 'utc')::date and tier = 'premium') <> (select n from deletions_before) + 1 then
    raise exception 'el contador premium no sumó 1';
  end if;
  if (select coalesce(sum(deletions), 0) from public.account_deletions_daily
       where day = (now() at time zone 'utc')::date and tier = 'free') < 2 then
    raise exception 'C y D (free) no sumaron';
  end if;
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'account_deletions_daily' and column_name = 'user_id') then
    raise exception 'el contador no puede tener user_id';
  end if;
end $$;

-- ── B sigue intacto ─────────────────────────────────────────────────────────

do $$
declare
  r record;
  v_n int;
begin
  for r in select * from counts_before where who = 'b' loop
    execute format('select count(*) from public.%I where lower(user_id::text) = $1', r.table_name)
      into v_n using '00000000-0000-0000-0000-0000000de1b2';
    if v_n <> r.n then raise exception 'B perdió filas en %: % → %', r.table_name, r.n, v_n; end if;
  end loop;
  if public.binance_keys_read('00000000-0000-0000-0000-0000000de1b2') is null
     or public.etoro_tokens_read('00000000-0000-0000-0000-0000000de1b2') is null
     or public.snaptrade_secret_read('00000000-0000-0000-0000-0000000de1b2') is null then
    raise exception 'B perdió secretos de Vault';
  end if;
end $$;

-- ── Permisos ────────────────────────────────────────────────────────────────

do $$
begin
  if has_table_privilege('authenticated', 'public.account_deletions_daily', 'select')
     or has_table_privilege('anon', 'public.account_deletions_daily', 'select') then
    raise exception 'account_deletions_daily legible por la app';
  end if;
  if has_function_privilege('authenticated', 'public._account_purge_before_delete()', 'execute') then
    raise exception 'la función del trigger es ejecutable por authenticated';
  end if;
  if not (select relrowsecurity from pg_class where oid = 'public.account_deletions_daily'::regclass) then
    raise exception 'account_deletions_daily sin RLS';
  end if;
end $$;

select 'ACCOUNT_DELETION_DB_TEST_OK' as result;

rollback;
