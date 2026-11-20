-- Test de 20261011000000_push_notifications.sql y 20261011010000_price_alerts.sql
-- (y de las que siguen del plan de notificaciones push).
--
-- Corre contra una base con las migraciones aplicadas (supabase start, o un
-- Postgres con los stubs de auth/vault/roles). Cada chequeo que falla corta
-- con una excepción; si termina, imprime PUSH_DB_TEST_OK.
--
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/push_notifications_db_test.sql
--
-- Todo corre dentro de una transacción que se deshace al final.

begin;

delete from public.notification_outbox;
delete from public.notification_log;
delete from public.push_devices;
delete from public.price_alerts;

-- A: Free. B: Premium.
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'pa@test.local'),
  ('00000000-0000-0000-0000-0000000000b1', 'pb@test.local');
select public.upsert_subscription_from_provider(
  '00000000-0000-0000-0000-0000000000b1', 'premium', 'test', null, 'active');

-- ── Dispositivos ─────────────────────────────────────────────────────────
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}';

select public.register_push_device(
  'token-aaaaaaaaaaaaaaaaaaaaaaaa', 'ios', 'es', 'America/Argentina/Buenos_Aires', 12);
-- Zona inválida → UTC; idioma desconocido → es.
select public.register_push_device(
  'token-a2aaaaaaaaaaaaaaaaaaaaaa', 'android', 'fr', 'Marte/Olympus', 12);

do $$
begin
  if (select count(*) from public.push_devices) <> 2 then
    raise exception 'A no ve sus 2 dispositivos';
  end if;
  if (select timezone from public.push_devices where token = 'token-a2aaaaaaaaaaaaaaaaaaaaaa') <> 'UTC' then
    raise exception 'zona inválida no cayó a UTC';
  end if;
  if (select locale from public.push_devices where token = 'token-a2aaaaaaaaaaaaaaaaaaaaaa') <> 'es' then
    raise exception 'idioma desconocido no cayó a es';
  end if;
  -- Preferencias creadas con el primer dispositivo, con los defaults.
  if (select show_amounts from public.get_notification_preferences()) then
    raise exception 'show_amounts debería arrancar apagado';
  end if;
end $$;

-- La app no escribe la tabla directo.
do $$
begin
  insert into public.push_devices (user_id, token, platform)
  values ('00000000-0000-0000-0000-0000000000a1', 'token-directoaaaaaaaaaaaaaaa', 'ios');
  raise exception 'insert directo en push_devices debería fallar';
exception when insufficient_privilege then null;
end $$;

-- Preferencias: cada uno las suyas.
update public.notification_preferences set big_moves = false, quiet_start = '23:00';

-- B toma el token de A (otra cuenta en el mismo teléfono).
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000b1","role":"authenticated"}';
select public.register_push_device(
  'token-aaaaaaaaaaaaaaaaaaaaaaaa', 'ios', 'en', 'America/New_York', 13);
do $$
begin
  if (select count(*) from public.push_devices) <> 1 then
    raise exception 'B debería ver solo el token que tomó';
  end if;
  if (select count(*) from public.notification_preferences) <> 1 then
    raise exception 'B no debería ver las preferencias de A';
  end if;
end $$;

-- B no puede borrar el token de A.
select public.unregister_push_device('token-a2aaaaaaaaaaaaaaaaaaaaaa');

-- ── Alertas de precio ────────────────────────────────────────────────────
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}';

do $$
begin
  if (select count(*) from public.push_devices) <> 1 then
    raise exception 'A perdió un token que B no podía borrar';
  end if;
end $$;

-- Free: 1 alerta activa.
insert into public.price_alerts (user_id, symbol, condition, target)
values ('00000000-0000-0000-0000-0000000000a1', 'VOO', 'above', 750);

do $$
begin
  insert into public.price_alerts (user_id, symbol, condition, target)
  values ('00000000-0000-0000-0000-0000000000a1', 'AAPL', 'below', 200);
  raise exception 'Free no debería poder tener 2 alertas activas';
exception when raise_exception then
  if sqlerrm <> 'alert_limit_reached' then raise; end if;
end $$;

-- La app no puede escribir lo que registra el servidor.
update public.price_alerts set last_price = 1, triggered_price = 1;
do $$
begin
  if (select last_price from public.price_alerts) is not null
     or (select triggered_price from public.price_alerts) is not null then
    raise exception 'la app pudo escribir campos del servidor';
  end if;
end $$;

-- pct sin precio de referencia: no.
do $$
begin
  update public.price_alerts set condition = 'pct_up', target = 5;
  raise exception 'pct sin reference_price debería fallar';
exception when check_violation then null;
end $$;

-- B no ve las de A.
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000b1","role":"authenticated"}';
do $$
begin
  if (select count(*) from public.price_alerts) <> 0 then
    raise exception 'B ve alertas de A';
  end if;
end $$;

-- Premium: 3 alertas.
insert into public.price_alerts (user_id, symbol, condition, target, reference_price, created_at)
values
  ('00000000-0000-0000-0000-0000000000b1', 'NVDA', 'pct_down', 10, 180, now()),
  ('00000000-0000-0000-0000-0000000000b1', 'MSFT', 'above', 500, null, now()),
  ('00000000-0000-0000-0000-0000000000b1', 'TSLA', 'below', 200, null, now());

reset role;

-- ── market-watch registra un disparo ─────────────────────────────────────
select public.price_alerts_record(jsonb_build_array(
  jsonb_build_object('id', (select id from public.price_alerts where symbol = 'MSFT'),
                     'price', 501.5, 'fire', true, 'fired_on', '2026-10-12'),
  jsonb_build_object('id', (select id from public.price_alerts where symbol = 'TSLA'),
                     'price', 250, 'fire', false, 'rearm_ready', true)
));
-- Otra vez el mismo disparo: no duplica (ya no está activa).
select public.price_alerts_record(jsonb_build_array(
  jsonb_build_object('id', (select id from public.price_alerts where symbol = 'MSFT'),
                     'price', 502, 'fire', true, 'fired_on', '2026-10-12')
));

do $$
begin
  if (select status from public.price_alerts where symbol = 'MSFT') <> 'triggered' then
    raise exception 'la alerta once no quedó triggered';
  end if;
  if (select count(*) from public.notification_outbox where kind = 'price_alert') <> 1 then
    raise exception 'el disparo no llegó (o llegó dos veces) al outbox';
  end if;
  if (select (data ->> 'price')::numeric from public.notification_outbox where kind = 'price_alert') <> 501.5 then
    raise exception 'precio del disparo';
  end if;
  if (select last_price from public.price_alerts where symbol = 'TSLA') <> 250 then
    raise exception 'última lectura no registrada';
  end if;
end $$;

-- ── Cambio de plan ───────────────────────────────────────────────────────
-- B baja a Free: de sus 2 activas queda 1 (la más nueva), la otra se pausa.
update public.price_alerts set created_at = now() - interval '1 day' where symbol = 'NVDA';
select public.upsert_subscription_from_provider(
  '00000000-0000-0000-0000-0000000000b1', 'free', 'test', null, 'expired');
do $$
begin
  if (select status from public.price_alerts where symbol = 'NVDA') <> 'paused'
     or (select paused_reason from public.price_alerts where symbol = 'NVDA') <> 'plan' then
    raise exception 'al bajar de plan la más vieja debería quedar pausada por plan';
  end if;
  if (select status from public.price_alerts where symbol = 'TSLA') <> 'active' then
    raise exception 'al bajar de plan la más nueva debería seguir activa';
  end if;
end $$;

-- Vuelve a Premium: se reactiva sola.
select public.upsert_subscription_from_provider(
  '00000000-0000-0000-0000-0000000000b1', 'premium', 'test', null, 'active');
do $$
begin
  if (select status from public.price_alerts where symbol = 'NVDA') <> 'active' then
    raise exception 'al subir de plan la pausada por plan debería volver';
  end if;
end $$;

-- Rearmar desde la app: vuelve a activa y borra el disparo.
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000b1","role":"authenticated"}';
update public.price_alerts set status = 'active' where symbol = 'MSFT';
do $$
begin
  if (select triggered_at from public.price_alerts where symbol = 'MSFT') is not null then
    raise exception 'rearmar debería limpiar el disparo';
  end if;
end $$;
-- No puede marcarla cumplida a mano.
do $$
begin
  update public.price_alerts set status = 'triggered' where symbol = 'TSLA';
  raise exception 'la app no debería poder marcarla cumplida';
exception when invalid_parameter_value then null;
end $$;
reset role;

-- ── Despacho ─────────────────────────────────────────────────────────────
insert into public.notification_outbox (user_id, kind, dedupe_key, data, not_before)
values ('00000000-0000-0000-0000-0000000000a1', 'test', 'test:later', '{}', now() + interval '1 hour');

do $$
declare
  v_ids bigint[];
  v_log bigint;
  v_ctx record;
begin
  -- Solo lo que ya está listo (el de "later" no).
  select array_agg(id) into v_ids from public.push_claim_outbox(10);
  if array_length(v_ids, 1) <> 1 then
    raise exception 'claim debería tomar 1 fila, tomó %', array_length(v_ids, 1);
  end if;
  -- Tomada: una segunda corrida no la ve.
  if exists (select 1 from public.push_claim_outbox(10)) then
    raise exception 'una fila tomada no debería volver a tomarse';
  end if;

  v_log := public.push_begin_log(v_ids[1]);
  perform public.push_complete(v_ids[1], v_log, 1);
  if (select status from public.notification_outbox where id = v_ids[1]) <> 'sent' then
    raise exception 'no quedó sent';
  end if;
  if (select device_count from public.notification_log where id = v_log) <> 1 then
    raise exception 'log sin device_count';
  end if;

  select * into v_ctx from public.push_dispatch_context(array[
    '00000000-0000-0000-0000-0000000000a1'::uuid,
    '00000000-0000-0000-0000-0000000000b1'::uuid]) where user_id = '00000000-0000-0000-0000-0000000000b1';
  if v_ctx.tier <> 'premium' then
    raise exception 'contexto: tier %', v_ctx.tier;
  end if;
  if jsonb_array_length(v_ctx.devices) <> 1 or v_ctx.devices -> 0 ->> 'locale' <> 'en' then
    raise exception 'contexto: dispositivos %', v_ctx.devices;
  end if;
  -- La price_alert no cuenta para el tope de automáticas.
  if v_ctx.automatic_last_24h <> 0 then
    raise exception 'contexto: automáticas %', v_ctx.automatic_last_24h;
  end if;

  select * into v_ctx from public.push_dispatch_context(array[
    '00000000-0000-0000-0000-0000000000a1'::uuid]);
  if (v_ctx.prefs ->> 'big_moves')::boolean or v_ctx.prefs ->> 'quiet_start' <> '23:00:00' then
    raise exception 'contexto: preferencias de A %', v_ctx.prefs;
  end if;
end $$;

-- Apertura: solo la propia (el log es de B: la alerta de MSFT).
select set_config('test.log_id', max(id)::text, true) from public.notification_log;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}';
select public.mark_notification_opened(current_setting('test.log_id')::bigint);
reset role;
do $$
begin
  if (select opened_at from public.notification_log order by id desc limit 1) is not null then
    raise exception 'A marcó como abierta una notificación de B';
  end if;
end $$;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000b1","role":"authenticated"}';
select public.mark_notification_opened(current_setting('test.log_id')::bigint);
reset role;
do $$
begin
  if (select opened_at from public.notification_log order by id desc limit 1) is null then
    raise exception 'apertura no registrada';
  end if;
end $$;

-- Diferida y sin entregar.
do $$
declare
  v_id bigint;
  v_log bigint;
begin
  update public.notification_outbox set not_before = now() where dedupe_key = 'test:later';
  select id into v_id from public.push_claim_outbox(10) limit 1;
  perform public.push_finish_outbox(v_id, 'pending', 'quiet_hours', now() + interval '8 hours');
  if (select not_before from public.notification_outbox where id = v_id) < now() + interval '7 hours' then
    raise exception 'la diferida no se corrió';
  end if;
  update public.notification_outbox set not_before = now() where id = v_id;
  perform public.push_claim_outbox(10);
  v_log := public.push_begin_log(v_id);
  perform public.push_complete(v_id, v_log, 0);
  if (select status from public.notification_outbox where id = v_id) <> 'pending'
     or exists (select 1 from public.notification_log where id = v_log) then
    raise exception 'sin entregar debería volver a la cola sin log';
  end if;
end $$;

-- ── Movimientos fuertes (20261011020000_market_moves.sql) ─────────────────
delete from public.notification_outbox;

-- A tiene posiciones y dispositivo; B apagó todo lo de movimientos.
insert into public.positions (id, user_id, ticker, quantity, purchase_price, purchase_date) values
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000a1', 'nvda', 2, 100, now()),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000a1', 'NVDA', 3, 120, now()),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000a1', 'AMD', 1, 90, now()),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000b1', 'TSLA', 1, 200, now());
update public.notification_preferences set big_moves = false, portfolio_moves = false
 where user_id = '00000000-0000-0000-0000-0000000000b1';
update public.notification_preferences set big_moves = true
 where user_id = '00000000-0000-0000-0000-0000000000a1';

do $$
begin
  if (select count(*) from public.market_watch_holdings()) <> 2 then
    raise exception 'holdings: % filas', (select count(*) from public.market_watch_holdings());
  end if;
  if (select quantity from public.market_watch_holdings() where symbol = 'NVDA') <> 5 then
    raise exception 'holdings: NVDA no se sumó (o el ticker no se normalizó)';
  end if;
end $$;

do $$
declare
  v int;
begin
  -- Un solo ticker: un big_move.
  v := public.market_enqueue_moves('2026-10-12', jsonb_build_array(jsonb_build_object(
    'user_id', '00000000-0000-0000-0000-0000000000a1',
    'moves', jsonb_build_array(jsonb_build_object('symbol', 'NVDA', 'change_pct', -6.1, 'weight_pct', 40, 'direction', 'down', 'level', 1)),
    'portfolio', null)));
  if v <> 1 then raise exception 'un ticker: % pendientes', v; end if;

  -- La corrida siguiente con lo mismo: nada nuevo.
  v := public.market_enqueue_moves('2026-10-12', jsonb_build_array(jsonb_build_object(
    'user_id', '00000000-0000-0000-0000-0000000000a1',
    'moves', jsonb_build_array(jsonb_build_object('symbol', 'NVDA', 'change_pct', -6.4, 'weight_pct', 40, 'direction', 'down', 'level', 1)),
    'portfolio', null)));
  if v <> 0 then raise exception 'repetido: % pendientes', v; end if;

  -- Duplica el umbral: avisa una vez más.
  v := public.market_enqueue_moves('2026-10-12', jsonb_build_array(jsonb_build_object(
    'user_id', '00000000-0000-0000-0000-0000000000a1',
    'moves', jsonb_build_array(jsonb_build_object('symbol', 'NVDA', 'change_pct', -10.2, 'weight_pct', 38, 'direction', 'down', 'level', 2)),
    'portfolio', null)));
  if v <> 1 then raise exception 'escalada: % pendientes', v; end if;

  -- Dos tickers nuevos juntos: un resumen.
  v := public.market_enqueue_moves('2026-10-12', jsonb_build_array(jsonb_build_object(
    'user_id', '00000000-0000-0000-0000-0000000000a1',
    'moves', jsonb_build_array(
      jsonb_build_object('symbol', 'AMD', 'change_pct', 6, 'weight_pct', 10, 'direction', 'up', 'level', 1),
      jsonb_build_object('symbol', 'TSM', 'change_pct', 7, 'weight_pct', 8, 'direction', 'up', 'level', 2)),
    'portfolio', null)));
  if v <> 1 then raise exception 'resumen: % pendientes', v; end if;
  if (select count(*) from public.notification_outbox where kind = 'big_move_digest' and status = 'pending') <> 1 then
    raise exception 'resumen: no se encoló';
  end if;
  if (select count(*) from public.notification_outbox where skip_reason = 'in_digest') <> 2 then
    raise exception 'resumen: los individuales no quedaron marcados';
  end if;

  -- Otro día, un ticker y la cartera: una sola (la de la cartera).
  v := public.market_enqueue_moves('2026-10-13', jsonb_build_array(jsonb_build_object(
    'user_id', '00000000-0000-0000-0000-0000000000a1',
    'moves', jsonb_build_array(jsonb_build_object('symbol', 'NVDA', 'change_pct', -7, 'weight_pct', 40, 'direction', 'down', 'level', 1)),
    'portfolio', jsonb_build_object('change_pct', -3.4, 'change_value', -120.5, 'direction', 'down',
                                    'benchmark_change_pct', -1.2,
                                    'moves', jsonb_build_array(jsonb_build_object('symbol', 'NVDA', 'change_pct', -7))))));
  if v <> 1 then raise exception 'cartera: % pendientes', v; end if;
  if (select skip_reason from public.notification_outbox
       where dedupe_key = 'big_move:NVDA:2026-10-13:down:1') <> 'in_portfolio_move' then
    raise exception 'cartera: el big_move no quedó adentro del de la cartera';
  end if;
end $$;

-- ── eToro y daily-jobs (20261011030000_push_producers.sql) ───────────────
delete from public.notification_outbox;
insert into public.etoro_connections (user_id, status, connected_at)
values ('00000000-0000-0000-0000-0000000000a1', 'connected', now());

do $$
begin
  update public.etoro_connections set status = 'reconnect_required'
   where user_id = '00000000-0000-0000-0000-0000000000a1';
  if (select count(*) from public.notification_outbox
       where kind = 'etoro_reconnect' and status = 'pending'
         and not_before > now() + interval '5 hours') <> 1 then
    raise exception 'eToro: el aviso no quedó para dentro de 6 horas';
  end if;
  -- Reconecta antes: se cancela.
  update public.etoro_connections set status = 'connected'
   where user_id = '00000000-0000-0000-0000-0000000000a1';
  if (select status from public.notification_outbox where kind = 'etoro_reconnect') <> 'skipped' then
    raise exception 'eToro: reconectó y el aviso sigue pendiente';
  end if;
end $$;

do $$
declare
  v_hour int := extract(hour from now() at time zone 'America/New_York')::int;
  v record;
begin
  -- B usa Nueva York (último dispositivo que abrió la app).
  select * into v from public.push_users_at_local_hour(v_hour)
   where user_id = '00000000-0000-0000-0000-0000000000b1';
  if v.user_id is null or v.timezone <> 'America/New_York' then
    raise exception 'daily-jobs: B no aparece a su hora local';
  end if;
  if v.tier <> 'premium' or v.symbols <> array['TSLA'] then
    raise exception 'daily-jobs: plan o tickers de B: % %', v.tier, v.symbols;
  end if;
  if exists (select 1 from public.push_users_at_local_hour((v_hour + 12) % 24)
              where user_id = '00000000-0000-0000-0000-0000000000b1') then
    raise exception 'daily-jobs: B aparece a otra hora';
  end if;

  if public.push_enqueue(jsonb_build_array(
       jsonb_build_object('user_id', '00000000-0000-0000-0000-0000000000b1', 'kind', 'weekly_report',
                          'dedupe_key', 'weekly_report:2026-10-05', 'data', jsonb_build_object('week_start', '2026-10-05')),
       jsonb_build_object('user_id', '00000000-0000-0000-0000-0000000000b1', 'kind', 'weekly_report',
                          'dedupe_key', 'weekly_report:2026-10-05'))) <> 1 then
    raise exception 'push_enqueue: debería entrar 1 (la otra es repetida)';
  end if;
end $$;

select 'PUSH_DB_TEST_OK';

rollback;
