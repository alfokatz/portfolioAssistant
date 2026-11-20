-- Test de 20261122100000_daily_brief_phase2.sql (brief diario, fase 2 de
-- backend): costo fijo configurable, región de una zona, zonas y plan de
-- calentamiento (sin user_id), purga y permisos.
--
-- Corre contra una base con las migraciones aplicadas (supabase start). Si
-- termina, imprime DAILY_BRIEF_PHASE2_DB_TEST_OK.
--
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/daily_brief_phase2_db_test.sql
--
-- Todo corre dentro de una transacción que se deshace al final.
--
-- Usuarios (todos con posiciones y dispositivo):
--   a1 es, Buenos Aires: NVDA, MELI.BA        a2 en, Buenos Aires: AAPL, BTC-USD
--   a3 es, Tokio: 7203.T                      a4 en, Nueva York: AAPL (interruptor apagado)

begin;

insert into auth.users (id, email, created_at) values
  ('00000000-0000-0000-0000-0000000c0a01', 'a1@test.local', now()),
  ('00000000-0000-0000-0000-0000000c0a02', 'a2@test.local', now()),
  ('00000000-0000-0000-0000-0000000c0a03', 'a3@test.local', now()),
  ('00000000-0000-0000-0000-0000000c0a04', 'a4@test.local', now());

insert into public.positions (id, user_id, ticker, quantity, purchase_price, purchase_date) values
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000c0a01', 'NVDA', 10, 100, now()),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000c0a01', 'MELI.BA', 5, 100, now()),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000c0a02', 'AAPL', 3, 100, now()),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000c0a02', 'BTC-USD', 1, 100, now()),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000c0a03', '7203.T', 1, 100, now()),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000c0a04', 'AAPL', 1, 100, now());

insert into public.push_devices (user_id, token, platform, locale, timezone) values
  ('00000000-0000-0000-0000-0000000c0a01', 'tok-a1-0000000000000000', 'ios', 'es', 'America/Argentina/Buenos_Aires'),
  ('00000000-0000-0000-0000-0000000c0a02', 'tok-a2-0000000000000000', 'ios', 'en', 'America/Argentina/Buenos_Aires'),
  ('00000000-0000-0000-0000-0000000c0a03', 'tok-a3-0000000000000000', 'ios', 'es', 'Asia/Tokyo'),
  ('00000000-0000-0000-0000-0000000c0a04', 'tok-a4-0000000000000000', 'ios', 'en', 'America/New_York');

create function pg_temp.check_true(label text, ok boolean) returns void language plpgsql as $$
begin
  if ok is not true then raise exception '%', label; end if;
end;
$$;

-- ── 1. Costo fijo: por defecto la opción más barata ─────────────────────────

do $$
begin
  perform pg_temp.check_true('costos por defecto: 1 franja por día',
    (select value = '{"pulse_slots_per_day": 1, "topic_slots_per_day": 1, "max_digests_per_run": 24}'::jsonb
       from public.app_config where key = 'daily_brief_costs'));
end $$;

-- Idempotente: otra pasada no pisa lo que el usuario ya cambió.
update public.app_config set value = '{"pulse_slots_per_day": 4, "topic_slots_per_day": 2, "max_digests_per_run": 10}'::jsonb
 where key = 'daily_brief_costs';
insert into public.app_config (key, value)
values ('daily_brief_costs', '{"pulse_slots_per_day": 1, "topic_slots_per_day": 1, "max_digests_per_run": 24}'::jsonb)
on conflict (key) do nothing;
do $$
begin
  perform pg_temp.check_true('on conflict do nothing respeta el cambio',
    (select (value ->> 'pulse_slots_per_day')::int = 4 from public.app_config where key = 'daily_brief_costs'));
end $$;

-- ── 2. Región de una zona ───────────────────────────────────────────────────

do $$
begin
  perform pg_temp.check_true('región latam',
    public._daily_brief_tz_region('America/Argentina/Buenos_Aires') = 'latam'
    and public._daily_brief_tz_region('America/Sao_Paulo') = 'latam'
    and public._daily_brief_tz_region('America/Mexico_City') = 'latam');
  perform pg_temp.check_true('región us',
    public._daily_brief_tz_region('America/New_York') = 'us'
    and public._daily_brief_tz_region('America/Los_Angeles') = 'us'
    and public._daily_brief_tz_region('UTC') = 'us');
  perform pg_temp.check_true('región eu',
    public._daily_brief_tz_region('Europe/Madrid') = 'eu' and public._daily_brief_tz_region('Africa/Cairo') = 'eu');
  perform pg_temp.check_true('región asia',
    public._daily_brief_tz_region('Asia/Tokyo') = 'asia' and public._daily_brief_tz_region('Australia/Sydney') = 'asia');
end $$;

-- ── 3. Zonas con un horario local ───────────────────────────────────────────

do $$
declare
  v_min int := extract(hour from now() at time zone 'Asia/Tokyo')::int * 60
             + extract(minute from now() at time zone 'Asia/Tokyo')::int;
begin
  -- Ventana que incluye "ahora" en Tokio: está, y con la fecha local de Tokio.
  perform pg_temp.check_true('zona de Tokio en su ventana', exists (
    select 1 from public.daily_brief_warm_zones(greatest(v_min - 1, 0), least(v_min + 2, 1440)) z
     where z.timezone = 'Asia/Tokyo' and z.local_date = (now() at time zone 'Asia/Tokyo')::date));
  -- Una ventana que no la incluye: no está (y una zona sin dispositivos nunca).
  perform pg_temp.check_true('zona de Tokio fuera de su ventana', not exists (
    select 1 from public.daily_brief_warm_zones((v_min + 60) % 1380, (v_min + 60) % 1380 + 10) z
     where z.timezone = 'Asia/Tokyo'));
  perform pg_temp.check_true('sin dispositivos no hay zona', not exists (
    select 1 from public.daily_brief_warm_zones(0, 1440) z where z.timezone = 'Pacific/Auckland'));
end $$;

-- ── 4. Plan de calentamiento (sin user_id) ──────────────────────────────────

-- Interruptor apagado: no hay nada que calentar.
update public.app_config set value = jsonb_set(jsonb_set(value, '{percent}', '0'), '{users}', '[]') where key = 'daily_brief';
do $$
begin
  perform pg_temp.check_true('apagado: sin plan', not exists (select 1 from public.daily_brief_warm_plan('latam')));
end $$;

-- Prendido para a1, a2 y a3 (a4 queda afuera).
update public.app_config
   set value = jsonb_set(value, '{users}', jsonb_build_array(
     '00000000-0000-0000-0000-0000000c0a01', '00000000-0000-0000-0000-0000000c0a02', '00000000-0000-0000-0000-0000000c0a03'))
 where key = 'daily_brief';

-- a1 apaga fed_rates (por defecto); a2 sigue latam_markets.
insert into public.user_news_topics (user_id, topic_id, followed) values
  ('00000000-0000-0000-0000-0000000c0a01', 'fed_rates', false),
  ('00000000-0000-0000-0000-0000000c0a02', 'latam_markets', true);

do $$
begin
  -- Idiomas con usuarios en latam: es (a1) y en (a2), 1 cada uno.
  perform pg_temp.check_true('pulso es', exists (select 1 from public.daily_brief_warm_plan('latam') where lang = 'es' and topic_id is null and users = 1));
  perform pg_temp.check_true('pulso en', exists (select 1 from public.daily_brief_warm_plan('latam') where lang = 'en' and topic_id is null and users = 1));
  -- Por defecto global: inflation para los dos idiomas.
  perform pg_temp.check_true('tema global es', exists (select 1 from public.daily_brief_warm_plan('latam') where lang = 'es' and topic_id = 'inflation'));
  perform pg_temp.check_true('tema global en', exists (select 1 from public.daily_brief_warm_plan('latam') where lang = 'en' and topic_id = 'inflation'));
  -- a1 apagó fed_rates: no se genera en es; en en sí (a2 lo tiene por defecto).
  perform pg_temp.check_true('tema apagado no va en es', not exists (select 1 from public.daily_brief_warm_plan('latam') where lang = 'es' and topic_id = 'fed_rates'));
  perform pg_temp.check_true('tema por defecto en en', exists (select 1 from public.daily_brief_warm_plan('latam') where lang = 'en' and topic_id = 'fed_rates'));
  -- Por cartera: .BA → ar_bcra_dollar solo en es (a1); cripto solo en en (a2).
  perform pg_temp.check_true('.BA en es', exists (select 1 from public.daily_brief_warm_plan('latam') where lang = 'es' and topic_id = 'ar_bcra_dollar'));
  perform pg_temp.check_true('.BA no en en', not exists (select 1 from public.daily_brief_warm_plan('latam') where lang = 'en' and topic_id = 'ar_bcra_dollar'));
  perform pg_temp.check_true('cripto en en', exists (select 1 from public.daily_brief_warm_plan('latam') where lang = 'en' and topic_id = 'crypto'));
  perform pg_temp.check_true('cripto no en es', not exists (select 1 from public.daily_brief_warm_plan('latam') where lang = 'es' and topic_id = 'crypto'));
  -- Seguido explícito.
  perform pg_temp.check_true('tema seguido', exists (select 1 from public.daily_brief_warm_plan('latam') where lang = 'en' and topic_id = 'latam_markets'));
  -- Otras regiones: Tokio (a3, es) está en asia; a4 tiene el interruptor apagado.
  perform pg_temp.check_true('asia solo es', exists (select 1 from public.daily_brief_warm_plan('asia') where lang = 'es' and topic_id is null)
    and not exists (select 1 from public.daily_brief_warm_plan('asia') where lang = 'en'));
  perform pg_temp.check_true('us sin usuarios con el interruptor', not exists (select 1 from public.daily_brief_warm_plan('us')));
  -- Sin user_id: la función no expone ese dato.
  perform pg_temp.check_true('sin user_id', not exists (
    select 1 from information_schema.parameters p
     where p.specific_schema = 'public' and p.parameter_mode = 'OUT' and p.parameter_name = 'user_id'
       and p.specific_name like 'daily_brief_warm_plan%'));
end $$;

-- ── 5. Purga ────────────────────────────────────────────────────────────────

insert into public.video_channel_allowlist (channel_id, uploads_playlist_id, name, lang)
values ('UCaaaaaaaaaaaaaaaaaaaaaa', 'UUaaaaaaaaaaaaaaaaaaaaaa', 'Canal de prueba', 'es');
insert into public.news_videos (video_id, channel_id, title, published_at, lang, region, fetched_at) values
  ('old00000001', 'UCaaaaaaaaaaaaaaaaaaaaaa', 'Viejo', now() - interval '9 days', 'es', 'global', now() - interval '8 days'),
  ('new00000001', 'UCaaaaaaaaaaaaaaaaaaaaaa', 'Nuevo', now() - interval '1 day', 'es', 'global', now() - interval '1 day');
insert into public.daily_briefs (user_id, brief_day, status, variant, created_at) values
  ('00000000-0000-0000-0000-0000000c0a01', current_date - 20, 'ready', 'numbers', now() - interval '20 days'),
  ('00000000-0000-0000-0000-0000000c0a01', current_date - 1, 'ready', 'numbers', now() - interval '1 day');

do $$
declare
  v jsonb := public.daily_brief_purge();
begin
  perform pg_temp.check_true('purga: videos viejos', (v ->> 'videos')::int = 1);
  perform pg_temp.check_true('purga: briefs viejos', (v ->> 'briefs')::int >= 1);
  perform pg_temp.check_true('purga: queda el video nuevo', exists (select 1 from public.news_videos where video_id = 'new00000001'));
  perform pg_temp.check_true('purga: no queda el viejo', not exists (select 1 from public.news_videos where video_id = 'old00000001'));
  perform pg_temp.check_true('purga: queda el brief de ayer', exists (
    select 1 from public.daily_briefs where user_id = '00000000-0000-0000-0000-0000000c0a01' and brief_day = current_date - 1));
  perform pg_temp.check_true('purga: no queda el de hace 20 días', not exists (
    select 1 from public.daily_briefs where user_id = '00000000-0000-0000-0000-0000000c0a01' and brief_day = current_date - 20));
end $$;

-- ── 6. Permisos: solo service_role ──────────────────────────────────────────

do $$
declare
  v_role text;
  v_call text;
  v_denied boolean;
begin
  foreach v_role in array array['anon', 'authenticated'] loop
    foreach v_call in array array[
      'select public.daily_brief_purge()',
      'select * from public.daily_brief_warm_plan(''latam'')',
      'select * from public.daily_brief_warm_zones(0, 10)',
      'select public._daily_brief_tz_region(''UTC'')'
    ] loop
      execute format('set local role %I', v_role);
      begin
        execute v_call;
        v_denied := false;
      exception when insufficient_privilege then
        v_denied := true;
      end;
      reset role;
      perform pg_temp.check_true(v_role || ' no puede: ' || v_call, v_denied);
    end loop;
  end loop;
  -- service_role sí.
  set local role service_role;
  perform public.daily_brief_purge();
  perform * from public.daily_brief_warm_zones(0, 10);
  perform * from public.daily_brief_warm_plan('latam');
  reset role;
end $$;

select 'DAILY_BRIEF_PHASE2_DB_TEST_OK';
rollback;
