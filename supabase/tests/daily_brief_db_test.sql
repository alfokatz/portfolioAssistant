-- Test de 20261121100000_daily_brief.sql y 20261121100100_daily_brief_catalogs.sql
-- (brief diario de tu cartera).
--
-- Corre contra una base con las migraciones aplicadas (supabase start). Si
-- termina, imprime DAILY_BRIEF_DB_TEST_OK.
--
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/daily_brief_db_test.sql
--
-- Todo corre dentro de una transacción que se deshace al final.
--
-- Usuarios:
--   f1 free, alta nueva         f2 free, alta vieja (antes de courtesy_since)
--   p1 premium (NVDA, MELI.BA)  p2 premium (AAPL)   g1 gold   n1 free sin posiciones

begin;

insert into auth.users (id, email, created_at) values
  ('00000000-0000-0000-0000-0000000b0f01', 'f1@test.local', now()),
  ('00000000-0000-0000-0000-0000000b0f02', 'f2@test.local', now() - interval '90 days'),
  ('00000000-0000-0000-0000-0000000b0a01', 'p1@test.local', now()),
  ('00000000-0000-0000-0000-0000000b0a02', 'p2@test.local', now()),
  ('00000000-0000-0000-0000-0000000b0c01', 'g1@test.local', now()),
  ('00000000-0000-0000-0000-0000000b0d01', 'n1@test.local', now());
insert into public.user_subscriptions (user_id, tier, status) values
  ('00000000-0000-0000-0000-0000000b0f01', 'free', 'active'),
  ('00000000-0000-0000-0000-0000000b0f02', 'free', 'active'),
  ('00000000-0000-0000-0000-0000000b0a01', 'premium', 'active'),
  ('00000000-0000-0000-0000-0000000b0a02', 'premium', 'active'),
  ('00000000-0000-0000-0000-0000000b0c01', 'gold', 'active'),
  ('00000000-0000-0000-0000-0000000b0d01', 'free', 'active')
on conflict (user_id) do update set tier = excluded.tier, status = excluded.status;

insert into public.positions (id, user_id, ticker, quantity, purchase_price, purchase_date) values
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000b0f01', 'AAPL', 1, 100, now()),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000b0f02', 'AAPL', 1, 100, now()),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000b0a01', 'NVDA', 10, 100, now()),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000b0a01', 'MELI.BA', 5, 100, now()),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000b0a02', 'AAPL', 3, 100, now()),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000b0a02', 'BTC-USD', 1, 100, now()),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000b0c01', 'MSFT', 2, 100, now());
insert into public.watchlist_items (user_id, symbol) values
  ('00000000-0000-0000-0000-0000000b0c01', 'TSLA'),
  ('00000000-0000-0000-0000-0000000b0a01', 'AMZN');

create function pg_temp.as_user(u text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
end;
$$;

create function pg_temp.expect(label text, got jsonb, want jsonb) returns void language plpgsql as $$
begin
  if got is distinct from want then
    raise exception '%: esperaba %, hubo %', label, want, got;
  end if;
end;
$$;

create function pg_temp.check_true(label text, ok boolean) returns void language plpgsql as $$
begin
  if ok is not true then raise exception '%', label; end if;
end;
$$;

-- Primer día hábil dentro de la ventana de claim (ayer..mañana UTC): siempre
-- hay uno, sea cual sea el día de hoy.
create function pg_temp.bday() returns date language sql as $$
  select d::date from generate_series(
    (now() at time zone 'utc')::date - 1, (now() at time zone 'utc')::date + 1, interval '1 day') d
  where extract(isodow from d) between 1 and 5
  order by d limit 1;
$$;

create function pg_temp.set_flag(v jsonb) returns void language sql as $$
  update public.app_config set value = v, updated_at = now() where key = 'daily_brief';
$$;

create function pg_temp.valid_payload(day date, variant text) returns jsonb language sql as $$
  select jsonb_build_object(
    'v', 1, 'day', day::text, 'lang', 'es', 'variant', variant,
    'numbers', jsonb_build_object('period', 'last_close', 'pct', 0.5),
    'why', '[]'::jsonb, 'sources', '{}'::jsonb, 'audio', null);
$$;

-- ── 1. Semillas y estado inicial ─────────────────────────────────────────────

do $$
begin
  perform pg_temp.check_true('el interruptor debe existir apagado',
    (select value ->> 'percent' = '0' and value -> 'users' = '[]'::jsonb
       from public.app_config where key = 'daily_brief'));
  perform pg_temp.check_true('catálogo de temas', (select count(*) from public.news_topics) >= 16);
  perform pg_temp.check_true('instrumentos core',
    (select count(*) from public.market_reference_instruments where core) = 9);
  -- Los medios nuevos entran deshabilitados hasta compliance.
  perform pg_temp.check_true('medios nuevos deshabilitados',
    not exists (select 1 from public.news_source_allowlist
                 where domain in ('asia.nikkei.com', 'imf.org') and enabled));
  perform pg_temp.check_true('reuters con prioridad de GDELT',
    (select gdelt_priority from public.news_source_allowlist where domain = 'reuters.com') = 1);
  perform pg_temp.check_true('notification kind', exists (
    select 1 from pg_constraint where conname = 'notification_outbox_kind_check'
       and pg_get_constraintdef(oid) like '%daily_brief%'));
  perform pg_temp.check_true('purpose daily_brief', exists (
    select 1 from pg_constraint where conname = 'ai_turn_usage_purpose_check'
       and pg_get_constraintdef(oid) like '%daily_brief%'));
end $$;

-- ── 2. Interruptor APAGADO: no pasa nada ─────────────────────────────────────

set local role authenticated;
do $$
declare r jsonb;
begin
  perform pg_temp.as_user('00000000-0000-0000-0000-0000000b0a01');
  perform pg_temp.expect('claim apagado', public.claim_daily_brief(pg_temp.bday()), '{"state":"disabled"}');
  r := public.daily_brief_status();
  perform pg_temp.check_true('status apagado', r ->> 'enabled' = 'false'
    and not exists (select 1 from jsonb_each_text(r -> 'pieces') where value = 'true'));
  perform pg_temp.expect('complete apagado',
    public.complete_daily_brief(pg_temp.bday(), pg_temp.valid_payload(pg_temp.bday(), 'numbers')),
    '{"ok":false,"reason":"not_claimed"}');
end $$;
reset role;
do $$
begin
  perform pg_temp.expect('entitlement apagado',
    public.daily_brief_entitlement('00000000-0000-0000-0000-0000000b0a01', pg_temp.bday()) -> 'enabled', 'false');
  perform pg_temp.check_true('entitlement apagado no filtra la cartera',
    not (public.daily_brief_entitlement('00000000-0000-0000-0000-0000000b0a01', pg_temp.bday()) ? 'held'));
  perform pg_temp.check_true('cron apagado', not public._daily_brief_cron_on());
  perform pg_temp.expect('ai_brief_begin apagado',
    public.ai_brief_begin('00000000-0000-0000-0000-0000000b0a01', 'turn-brief-off-0001',
                          pg_temp.bday(), 'gpt-6-luna', 2, 30),
    '{"ok":false,"reason":"disabled"}');
  perform pg_temp.check_true('no se escribió nada', not exists (select 1 from public.daily_briefs));
end $$;

-- ── 3. Prendido para la lista interna (users) ────────────────────────────────

select pg_temp.set_flag(jsonb_build_object(
  'percent', 0,
  'users', jsonb_build_array(
    '00000000-0000-0000-0000-0000000b0f01', '00000000-0000-0000-0000-0000000b0f02',
    '00000000-0000-0000-0000-0000000b0a01', '00000000-0000-0000-0000-0000000b0a02',
    '00000000-0000-0000-0000-0000000b0c01', '00000000-0000-0000-0000-0000000b0d01'),
  'courtesy_days', 2,
  'courtesy_since', to_char(now() at time zone 'utc' - interval '1 day', 'YYYY-MM-DD'),
  'pieces', jsonb_build_object('push', true, 'videos', false)));

do $$
begin
  perform pg_temp.check_true('cron prendido', public._daily_brief_cron_on());
  perform pg_temp.check_true('pieza faltante vale true', public._daily_brief_piece('feed'));
  perform pg_temp.check_true('pieza apagada', not public._daily_brief_piece('videos'));
  perform pg_temp.check_true('courtesy_days', public._daily_brief_courtesy_days() = 2);
end $$;

-- courtesy_days se acota a 1..15.
do $$
begin
  perform pg_temp.set_flag('{"percent":0,"users":[],"courtesy_days":99}');
  perform pg_temp.check_true('tope 15', public._daily_brief_courtesy_days() = 15);
  perform pg_temp.set_flag('{"percent":0,"users":[],"courtesy_days":0}');
  perform pg_temp.check_true('piso 1', public._daily_brief_courtesy_days() = 1);
  perform pg_temp.set_flag('{"percent":0,"users":[]}');
  perform pg_temp.check_true('default 7', public._daily_brief_courtesy_days() = 7);
  perform pg_temp.check_true('sin courtesy_since falla cerrado', public._daily_brief_courtesy_since() is null);
  perform pg_temp.set_flag('{"percent":0,"users":[],"courtesy_since":"no es fecha"}');
  perform pg_temp.check_true('courtesy_since inválido falla cerrado', public._daily_brief_courtesy_since() is null);
end $$;

select pg_temp.set_flag(jsonb_build_object(
  'percent', 0,
  'users', jsonb_build_array(
    '00000000-0000-0000-0000-0000000b0f01', '00000000-0000-0000-0000-0000000b0f02',
    '00000000-0000-0000-0000-0000000b0a01', '00000000-0000-0000-0000-0000000b0a02',
    '00000000-0000-0000-0000-0000000b0c01', '00000000-0000-0000-0000-0000000b0d01'),
  'courtesy_days', 2,
  'courtesy_since', to_char(now() at time zone 'utc' - interval '1 day', 'YYYY-MM-DD'),
  'pieces', jsonb_build_object('push', true, 'videos', false)));

-- ── 4. Estados de claim que no generan ───────────────────────────────────────

set local role authenticated;
do $$
declare r jsonb;
begin
  perform pg_temp.as_user('00000000-0000-0000-0000-0000000b0d01');
  perform pg_temp.expect('sin posiciones', public.claim_daily_brief(pg_temp.bday()), '{"state":"no_portfolio"}');

  perform pg_temp.as_user('00000000-0000-0000-0000-0000000b0a01');
  -- Fin de semana y fechas lejanas no son plausibles.
  perform pg_temp.expect('sábado',
    public.claim_daily_brief((date_trunc('week', now() at time zone 'utc')::date + 5)),
    '{"state":"not_business_day"}');
  perform pg_temp.expect('día lejano', public.claim_daily_brief(pg_temp.bday() + 30), '{"state":"not_business_day"}');
  perform pg_temp.expect('día nulo', public.claim_daily_brief(null), '{"state":"not_business_day"}');

  r := public.daily_brief_status();
  perform pg_temp.check_true('status prendido', r ->> 'enabled' = 'true'
    and r #>> '{pieces,push}' = 'true' and r #>> '{pieces,videos}' = 'false'
    and r #>> '{pieces,feed}' = 'true');
end $$;
reset role;

-- ── 5. Premium: claim → generando → complete → ready ─────────────────────────

set local role authenticated;
do $$
declare r jsonb; d date := pg_temp.bday();
begin
  perform pg_temp.as_user('00000000-0000-0000-0000-0000000b0a01');
  perform pg_temp.expect('premium claim', public.claim_daily_brief(d),
    '{"state":"claimed","variant":"full","courtesy":false,"attempt":1}');
  perform pg_temp.expect('segundo dispositivo', public.claim_daily_brief(d), '{"state":"in_progress"}');

  -- Payloads inválidos.
  perform pg_temp.expect('no objeto', public.complete_daily_brief(d, '[]'), '{"ok":false,"reason":"invalid_payload"}');
  perform pg_temp.expect('sin numbers', public.complete_daily_brief(d, '{"v":1,"day":"x","variant":"full"}'),
    '{"ok":false,"reason":"invalid_payload"}');
  perform pg_temp.expect('día distinto',
    public.complete_daily_brief(d, pg_temp.valid_payload(d + 1, 'full')), '{"ok":false,"reason":"invalid_payload"}');
  perform pg_temp.expect('variant raro',
    public.complete_daily_brief(d, pg_temp.valid_payload(d, 'otra')), '{"ok":false,"reason":"invalid_payload"}');
  perform pg_temp.expect('audio string',
    public.complete_daily_brief(d, pg_temp.valid_payload(d, 'full') || '{"audio":"x"}'),
    '{"ok":false,"reason":"invalid_payload"}');
  perform pg_temp.expect('audio sin duración',
    public.complete_daily_brief(d, pg_temp.valid_payload(d, 'full') || '{"audio":{"url":"https://x"}}'),
    '{"ok":false,"reason":"invalid_payload"}');
  perform pg_temp.expect('demasiado grande',
    public.complete_daily_brief(d, pg_temp.valid_payload(d, 'full') || jsonb_build_object('pad', repeat('x', 70000))),
    '{"ok":false,"reason":"payload_too_large"}');
  -- Sin claim de ese día (otro día hábil o sin fila): no_claimed para full.
  perform pg_temp.expect('full sin claim',
    public.complete_daily_brief(d + 1, pg_temp.valid_payload(d + 1, 'full')), '{"ok":false,"reason":"not_claimed"}');

  perform pg_temp.expect('complete full',
    public.complete_daily_brief(d, pg_temp.valid_payload(d, 'full') || '{"audio":{"url":"https://x","duration_s":30}}'),
    '{"ok":true}');
  r := public.claim_daily_brief(d);
  perform pg_temp.check_true('ready con payload', r ->> 'state' = 'ready' and r ->> 'variant' = 'full'
    and r ->> 'courtesy' = 'false' and r #>> '{payload,day}' = d::text);
  -- Ya listo: no se pisa con otro full.
  perform pg_temp.expect('full repetido',
    public.complete_daily_brief(d, pg_temp.valid_payload(d, 'full')), '{"ok":false,"reason":"not_claimed"}');
end $$;
reset role;

-- ── 6. Gold y fail/reintentos ────────────────────────────────────────────────

set local role authenticated;
do $$
declare d date := pg_temp.bday();
begin
  perform pg_temp.as_user('00000000-0000-0000-0000-0000000b0c01');
  perform pg_temp.expect('gold claim', public.claim_daily_brief(d),
    '{"state":"claimed","variant":"full","courtesy":false,"attempt":1}');
  perform pg_temp.expect('fail 1', public.fail_daily_brief(d), '{"ok":true}');
  perform pg_temp.expect('reintento 2', public.claim_daily_brief(d),
    '{"state":"claimed","variant":"full","courtesy":false,"attempt":2}');
  perform pg_temp.expect('fail 2', public.fail_daily_brief(d), '{"ok":true}');
  perform pg_temp.expect('reintento 3', public.claim_daily_brief(d),
    '{"state":"claimed","variant":"full","courtesy":false,"attempt":3}');
  perform pg_temp.expect('fail 3', public.fail_daily_brief(d), '{"ok":true}');
  perform pg_temp.expect('agotado', public.claim_daily_brief(d), '{"state":"failed"}');
  perform pg_temp.expect('fail sin claim', public.fail_daily_brief(d), '{"ok":false}');
end $$;
reset role;

-- ── 7. Free: cortesía, solo altas nuevas, tope y carrera ─────────────────────

-- f2 es de antes de courtesy_since: sin cortesía, solo números, y los guarda.
set local role authenticated;
do $$
declare d date := pg_temp.bday();
begin
  perform pg_temp.as_user('00000000-0000-0000-0000-0000000b0f02');
  perform pg_temp.expect('alta vieja', public.claim_daily_brief(d), '{"state":"numbers_only"}');
  perform pg_temp.expect('numbers sin claim',
    public.complete_daily_brief(d, pg_temp.valid_payload(d, 'numbers')), '{"ok":true}');
  perform pg_temp.check_true('numbers listo', public.claim_daily_brief(d) ->> 'state' = 'ready'
    and public.claim_daily_brief(d) ->> 'variant' = 'numbers'
    and public.claim_daily_brief(d) ->> 'courtesy' = 'false');
  -- Repetir no pisa el guardado.
  perform pg_temp.expect('numbers repetido',
    public.complete_daily_brief(d, pg_temp.valid_payload(d, 'numbers') || '{"extra":1}'), '{"ok":true}');
  perform pg_temp.check_true('no se pisó', not (
    (select payload from public.daily_briefs
      where user_id = '00000000-0000-0000-0000-0000000b0f02' and brief_day = d) ? 'extra'));
end $$;
reset role;

-- f1 (alta nueva, courtesy_days = 2): un regalo ya usado el día anterior.
insert into public.daily_briefs (user_id, brief_day, status, variant, courtesy, payload)
values ('00000000-0000-0000-0000-0000000b0f01', current_date - 20, 'ready', 'full', true, '{}');

set local role authenticated;
do $$
declare d date := pg_temp.bday();
begin
  perform pg_temp.as_user('00000000-0000-0000-0000-0000000b0f01');
  perform pg_temp.expect('cortesía 2 de 2', public.claim_daily_brief(d),
    '{"state":"claimed","variant":"full","courtesy":true,"attempt":1,"courtesy_number":2,"courtesy_total":2}');
  -- Otro dispositivo, mismo día: no regala uno de más.
  perform pg_temp.expect('segundo dispositivo cortesía', public.claim_daily_brief(d), '{"state":"in_progress"}');
  -- Otro día hábil de la ventana (si lo hay): el tope ya está usado.
  if exists (select 1 from generate_series((now() at time zone 'utc')::date - 1,
                (now() at time zone 'utc')::date + 1, interval '1 day') x
              where extract(isodow from x) between 1 and 5 and x::date <> d) then
    perform pg_temp.expect('tope de cortesía',
      public.claim_daily_brief((select x::date from generate_series((now() at time zone 'utc')::date - 1,
        (now() at time zone 'utc')::date + 1, interval '1 day') x
        where extract(isodow from x) between 1 and 5 and x::date <> d order by x limit 1)),
      '{"state":"numbers_only"}');
  end if;
  -- Re-claim de la cortesía propia después de un fail: mismo número.
  perform pg_temp.expect('fail cortesía', public.fail_daily_brief(d), '{"ok":true}');
  perform pg_temp.expect('re-claim cortesía', public.claim_daily_brief(d),
    '{"state":"claimed","variant":"full","courtesy":true,"attempt":2,"courtesy_number":2,"courtesy_total":2}');
end $$;
reset role;

-- Cortesía con courtesy_since en el futuro: nadie la recibe.
do $$
begin
  perform pg_temp.set_flag(jsonb_build_object(
    'percent', 100, 'users', '[]'::jsonb, 'courtesy_days', 2,
    'courtesy_since', to_char(now() at time zone 'utc' + interval '30 days', 'YYYY-MM-DD')));
  delete from public.daily_briefs where user_id = '00000000-0000-0000-0000-0000000b0f01';
end $$;
set local role authenticated;
do $$
begin
  perform pg_temp.as_user('00000000-0000-0000-0000-0000000b0f01');
  perform pg_temp.expect('courtesy_since futuro', public.claim_daily_brief(pg_temp.bday()), '{"state":"numbers_only"}');
end $$;
reset role;

-- Prendido por percent = 100 (el flag cubre a todos) y vuelve la lista.
select pg_temp.set_flag(jsonb_build_object(
  'percent', 0,
  'users', jsonb_build_array(
    '00000000-0000-0000-0000-0000000b0f01', '00000000-0000-0000-0000-0000000b0f02',
    '00000000-0000-0000-0000-0000000b0a01', '00000000-0000-0000-0000-0000000b0a02',
    '00000000-0000-0000-0000-0000000b0c01', '00000000-0000-0000-0000-0000000b0d01'),
  'courtesy_days', 2,
  'courtesy_since', to_char(now() at time zone 'utc' - interval '1 day', 'YYYY-MM-DD')));

-- ── 8. ai_brief_begin ────────────────────────────────────────────────────────

-- p2 y f1 reclaman (f1 con cortesía); p1 ya tiene el brief listo.
set local role authenticated;
do $$
begin
  perform pg_temp.as_user('00000000-0000-0000-0000-0000000b0a02');
  perform pg_temp.check_true('claim p2', public.claim_daily_brief(pg_temp.bday()) ->> 'state' = 'claimed');
  perform pg_temp.as_user('00000000-0000-0000-0000-0000000b0f01');
  perform pg_temp.check_true('claim f1', public.claim_daily_brief(pg_temp.bday()) ->> 'state' = 'claimed');
end $$;
reset role;

do $$
declare d date := pg_temp.bday();
begin
  perform pg_temp.expect('begin sin claim vigente (ready)',
    public.ai_brief_begin('00000000-0000-0000-0000-0000000b0a01', 'turn-brief-0001', d, 'gpt-6-luna', 2, 30),
    '{"ok":false,"reason":"not_claimed"}');
  perform pg_temp.expect('begin 1',
    public.ai_brief_begin('00000000-0000-0000-0000-0000000b0a02', 'turn-brief-0002', d, 'gpt-6-luna', 2, 30), '{"ok":true}');
  perform pg_temp.expect('begin 2',
    public.ai_brief_begin('00000000-0000-0000-0000-0000000b0a02', 'turn-brief-0003', d, 'gpt-6-luna', 2, 30), '{"ok":true}');
  perform pg_temp.expect('begin 3',
    public.ai_brief_begin('00000000-0000-0000-0000-0000000b0a02', 'turn-brief-0004', d, 'gpt-6-luna', 2, 30),
    '{"ok":false,"reason":"too_many_rounds"}');
  perform pg_temp.expect('modelo no permitido',
    public.ai_brief_begin('00000000-0000-0000-0000-0000000b0a02', 'turn-brief-0005', d, 'gpt-4.1', 2, 30),
    '{"ok":false,"reason":"model_not_allowed"}');
  -- f1 tiene claim vigente pero no puede colgarse del turno de p2.
  perform pg_temp.expect('turn_mismatch',
    public.ai_brief_begin('00000000-0000-0000-0000-0000000b0f01', 'turn-brief-0002', d, 'gpt-6-luna', 2, 30),
    '{"ok":false,"reason":"turn_mismatch"}');
  perform pg_temp.check_true('purpose registrado', (
    select purpose = 'daily_brief' and round_count = 1 from public.ai_turn_usage where turn_id = 'turn-brief-0002'));
  perform pg_temp.check_true('rondas del brief', (
    select llm_rounds = 2 from public.daily_briefs
     where user_id = '00000000-0000-0000-0000-0000000b0a02' and brief_day = d));
end $$;

-- Claim vencido (TTL): ya no sirve para el LLM.
do $$
declare d date := pg_temp.bday();
begin
  update public.daily_briefs set claimed_at = now() - interval '10 minutes'
   where user_id = '00000000-0000-0000-0000-0000000b0a02' and brief_day = d;
  perform pg_temp.expect('claim vencido',
    public.ai_brief_begin('00000000-0000-0000-0000-0000000b0a02', 'turn-brief-0006', d, 'gpt-6-luna', 9, 30),
    '{"ok":false,"reason":"not_claimed"}');
end $$;

-- ── 9. RLS y permisos ────────────────────────────────────────────────────────

set local role authenticated;
do $$
declare n int;
begin
  perform pg_temp.as_user('00000000-0000-0000-0000-0000000b0a01');
  select count(*) into n from public.daily_briefs;
  perform pg_temp.check_true('p1 solo ve lo suyo', n >= 1 and not exists (
    select 1 from public.daily_briefs where user_id <> '00000000-0000-0000-0000-0000000b0a01'));
  begin
    insert into public.daily_briefs (user_id, brief_day, status, variant)
    values ('00000000-0000-0000-0000-0000000b0a01', current_date - 400, 'ready', 'full');
    raise exception 'pudo escribir daily_briefs';
  exception when insufficient_privilege then null; end;
  begin
    update public.daily_briefs set status = 'ready';
    raise exception 'pudo actualizar daily_briefs';
  exception when insufficient_privilege then null; end;
  begin
    perform public.daily_brief_entitlement('00000000-0000-0000-0000-0000000b0a02', current_date);
    raise exception 'pudo llamar a entitlement';
  exception when insufficient_privilege then null; end;
  begin
    perform public.ai_brief_begin('00000000-0000-0000-0000-0000000b0a01', 'turn-x-00000001', current_date, 'gpt-6-luna', 2, 30);
    raise exception 'pudo llamar a ai_brief_begin';
  exception when insufficient_privilege then null; end;
  begin
    perform public.daily_brief_warm_symbols(array['UTC'], 10);
    raise exception 'pudo llamar a warm_symbols';
  exception when insufficient_privilege then null; end;
  begin
    perform public.daily_brief_push_inputs(array['00000000-0000-0000-0000-0000000b0a02'::uuid]);
    raise exception 'pudo llamar a push_inputs';
  exception when insufficient_privilege then null; end;
  begin
    perform count(*) from public.news_videos;
    raise exception 'pudo leer news_videos';
  exception when insufficient_privilege then null; end;
  begin
    perform count(*) from public.video_channel_allowlist;
    raise exception 'pudo leer video_channel_allowlist';
  exception when insufficient_privilege then null; end;
  begin
    update public.news_topics set enabled = false;
    raise exception 'pudo escribir news_topics';
  exception when insufficient_privilege then null; end;
  -- Catálogos de lectura.
  perform pg_temp.check_true('lee temas', (select count(*) from public.news_topics) >= 16);
  perform pg_temp.check_true('lee instrumentos', (select count(*) from public.market_reference_instruments) >= 20);
  -- Allowlist: solo las columnas públicas, y solo las habilitadas.
  perform pg_temp.check_true('lee medios', (select count(*) from public.news_source_allowlist) >= 28);
  perform pg_temp.check_true('no ve deshabilitados',
    not exists (select 1 from public.news_source_allowlist where domain = 'asia.nikkei.com'));
  begin
    perform enabled from public.news_source_allowlist;
    raise exception 'leyó enabled';
  exception when insufficient_privilege then null; end;
  begin
    perform gdelt_priority from public.news_source_allowlist;
    raise exception 'leyó gdelt_priority';
  exception when insufficient_privilege then null; end;
  begin
    update public.news_source_allowlist set name = 'x';
    raise exception 'pudo escribir la allowlist';
  exception when insufficient_privilege then null; end;
end $$;
reset role;

-- ── 10. Temas seguidos: CRUD propio, RLS y tope de 12 ────────────────────────

set local role authenticated;
do $$
declare t text; n int := 0; msg text;
begin
  perform pg_temp.as_user('00000000-0000-0000-0000-0000000b0a01');
  for t in select id from public.news_topics order by sort limit 12 loop
    insert into public.user_news_topics (user_id, topic_id, followed)
    values ('00000000-0000-0000-0000-0000000b0a01', t, true);
    n := n + 1;
  end loop;
  begin
    insert into public.user_news_topics (user_id, topic_id, followed)
    values ('00000000-0000-0000-0000-0000000b0a01', (select id from public.news_topics order by sort offset 12 limit 1), true);
    raise exception 'pasó el tope de temas';
  exception when others then
    get stacked diagnostics msg = message_text;
    if msg <> 'topic_limit_reached' then raise exception 'esperaba topic_limit_reached, hubo %', msg; end if;
  end;
  -- Dejar de seguir no cuenta y libera lugar; actualizar uno ya seguido no choca.
  update public.user_news_topics set followed = false
   where user_id = '00000000-0000-0000-0000-0000000b0a01'
     and topic_id = (select id from public.news_topics order by sort limit 1);
  update public.user_news_topics set followed = true
   where user_id = '00000000-0000-0000-0000-0000000b0a01'
     and topic_id = (select id from public.news_topics order by sort limit 1);
  update public.user_news_topics set followed = false
   where user_id = '00000000-0000-0000-0000-0000000b0a01'
     and topic_id = (select id from public.news_topics order by sort limit 1);
  insert into public.user_news_topics (user_id, topic_id, followed)
  values ('00000000-0000-0000-0000-0000000b0a01', (select id from public.news_topics order by sort offset 12 limit 1), true);
  -- Un tema "apagado" no cuenta para el tope de otro usuario.
  perform pg_temp.as_user('00000000-0000-0000-0000-0000000b0a02');
  insert into public.user_news_topics (user_id, topic_id, followed) values
    ('00000000-0000-0000-0000-0000000b0a02', 'crypto', true);
  perform pg_temp.check_true('p2 no ve los temas de p1',
    (select count(*) from public.user_news_topics) = 1);
  begin
    insert into public.user_news_topics (user_id, topic_id, followed)
    values ('00000000-0000-0000-0000-0000000b0a01', 'crypto', true);
    raise exception 'insertó a nombre de otro';
  exception when insufficient_privilege or check_violation then null; end;
  delete from public.user_news_topics where user_id = '00000000-0000-0000-0000-0000000b0a01';
  get diagnostics n = row_count;
  perform pg_temp.check_true('no borra ajenos', n = 0);
  begin
    insert into public.user_news_topics (user_id, topic_id, followed) values
      ('00000000-0000-0000-0000-0000000b0a02', 'no_existe', true);
    raise exception 'tema fuera del catálogo';
  exception when foreign_key_violation then null; end;
end $$;
reset role;

-- ── 11. Medios preferidos y silenciados: tope de 10 y 10 ─────────────────────

do $$
begin
  -- 12 dominios habilitados de prueba para llenar los topes.
  insert into public.news_source_allowlist (domain, name, lang)
  select 'medio' || g || '.test.com', 'Medio ' || g, 'en' from generate_series(1, 22) g
  on conflict do nothing;
end $$;
set local role authenticated;
do $$
declare g int; msg text;
begin
  perform pg_temp.as_user('00000000-0000-0000-0000-0000000b0a01');
  for g in 1..10 loop
    insert into public.user_news_sources (user_id, domain, preference)
    values ('00000000-0000-0000-0000-0000000b0a01', 'medio' || g || '.test.com', 'prefer');
  end loop;
  begin
    insert into public.user_news_sources (user_id, domain, preference)
    values ('00000000-0000-0000-0000-0000000b0a01', 'medio11.test.com', 'prefer');
    raise exception 'pasó el tope de preferidos';
  exception when others then
    get stacked diagnostics msg = message_text;
    if msg <> 'source_limit_reached' then raise exception 'esperaba source_limit_reached, hubo %', msg; end if;
  end;
  -- Los silenciados cuentan aparte.
  for g in 11..20 loop
    insert into public.user_news_sources (user_id, domain, preference)
    values ('00000000-0000-0000-0000-0000000b0a01', 'medio' || g || '.test.com', 'mute');
  end loop;
  begin
    insert into public.user_news_sources (user_id, domain, preference)
    values ('00000000-0000-0000-0000-0000000b0a01', 'medio21.test.com', 'mute');
    raise exception 'pasó el tope de silenciados';
  exception when others then
    get stacked diagnostics msg = message_text;
    if msg <> 'source_limit_reached' then raise exception 'esperaba source_limit_reached, hubo %', msg; end if;
  end;
  -- Pasar de silenciado a preferido con el tope lleno falla; con lugar, funciona.
  begin
    update public.user_news_sources set preference = 'prefer'
     where user_id = '00000000-0000-0000-0000-0000000b0a01' and domain = 'medio11.test.com';
    raise exception 'el cambio saltó el tope';
  exception when others then
    get stacked diagnostics msg = message_text;
    if msg <> 'source_limit_reached' then raise exception 'esperaba source_limit_reached, hubo %', msg; end if;
  end;
  delete from public.user_news_sources
   where user_id = '00000000-0000-0000-0000-0000000b0a01' and domain = 'medio1.test.com';
  update public.user_news_sources set preference = 'prefer'
   where user_id = '00000000-0000-0000-0000-0000000b0a01' and domain = 'medio11.test.com';
  -- RLS: p2 no ve ni toca lo de p1.
  perform pg_temp.as_user('00000000-0000-0000-0000-0000000b0a02');
  perform pg_temp.check_true('p2 no ve medios de p1', (select count(*) from public.user_news_sources) = 0);
  begin
    insert into public.user_news_sources (user_id, domain, preference)
    values ('00000000-0000-0000-0000-0000000b0a01', 'medio22.test.com', 'mute');
    raise exception 'insertó a nombre de otro';
  exception when insufficient_privilege or check_violation then null; end;
end $$;
reset role;

-- ── 12. Entitlement: solo lo del usuario, plan y temas por defecto ───────────

do $$
declare e jsonb;
begin
  -- p1: NVDA y MELI.BA (cartera) + AMZN en la watchlist, que Premium no recibe.
  e := public.daily_brief_entitlement('00000000-0000-0000-0000-0000000b0a01', pg_temp.bday());
  perform pg_temp.check_true('enabled', e ->> 'enabled' = 'true' and e ->> 'tier' = 'premium'
    and e ->> 'variant' = 'full' and e ->> 'courtesy' = 'false');
  perform pg_temp.check_true('held propia',
    (select array_agg(h ->> 'symbol' order by h ->> 'symbol') from jsonb_array_elements(e -> 'held') h)
      = array['MELI.BA', 'NVDA']);
  perform pg_temp.check_true('premium sin watchlist', e -> 'watchlist' = '[]'::jsonb);
  perform pg_temp.check_true('mercados', e -> 'markets' = '[".BA", "US"]'::jsonb);
  perform pg_temp.check_true('pesos', (select bool_and((h ->> 'weight_pct') is not null) from jsonb_array_elements(e -> 'held') h));
  -- p1 apagó fed_rates (sección 10), sigue latam_markets y recibe el argentino por .BA.
  perform pg_temp.check_true('temas de p1', e -> 'topics' ? 'ar_bcra_dollar' and e -> 'topics' ? 'latam_markets'
    and not (e -> 'topics' ? 'fed_rates'));
  perform pg_temp.check_true('prefer y mute',
    jsonb_array_length(e -> 'prefer') = 10 and jsonb_array_length(e -> 'mute') = 9);

  -- p2: AAPL + cripto, sin .BA: no recibe los temas argentinos; sí el de cripto.
  e := public.daily_brief_entitlement('00000000-0000-0000-0000-0000000b0a02', pg_temp.bday());
  perform pg_temp.check_true('held de p2 sin tickers de p1',
    (select array_agg(h ->> 'symbol' order by h ->> 'symbol') from jsonb_array_elements(e -> 'held') h)
      = array['AAPL', 'BTC-USD']);
  perform pg_temp.check_true('sin .BA no hay temas argentinos',
    not (e -> 'topics' ? 'ar_bcra_dollar') and not (e -> 'topics' ? 'ar_country_risk_cer'));
  perform pg_temp.check_true('globales por defecto', e -> 'topics' ? 'fed_rates' and e -> 'topics' ? 'global_indices');
  perform pg_temp.check_true('cripto por clase', e -> 'topics' ? 'crypto');
  perform pg_temp.check_true('clases', e -> 'asset_classes' @> '["crypto", "equity"]'::jsonb);
  perform pg_temp.check_true('cripto no suma mercado', e -> 'markets' = '["US"]'::jsonb);
  perform pg_temp.check_true('p2 sin preferencias', e -> 'prefer' = '[]'::jsonb and e -> 'mute' = '[]'::jsonb);

  -- Seguir un tema y apagar uno por defecto (como service role escribe directo).
  insert into public.user_news_topics (user_id, topic_id, followed) values
    ('00000000-0000-0000-0000-0000000b0a02', 'tech_ai', true),
    ('00000000-0000-0000-0000-0000000b0a02', 'fed_rates', false);
  e := public.daily_brief_entitlement('00000000-0000-0000-0000-0000000b0a02', pg_temp.bday());
  perform pg_temp.check_true('seguido suma, apagado resta',
    e -> 'topics' ? 'tech_ai' and not (e -> 'topics' ? 'fed_rates'));

  -- Gold: su watchlist, y nada de lo de otros.
  e := public.daily_brief_entitlement('00000000-0000-0000-0000-0000000b0c01', pg_temp.bday());
  perform pg_temp.check_true('gold watchlist', e -> 'watchlist' = '["TSLA"]'::jsonb and e ->> 'tier' = 'gold');
  perform pg_temp.check_true('held de g1', (select array_agg(h ->> 'symbol') from jsonb_array_elements(e -> 'held') h) = array['MSFT']);

  -- Free sin claim: números (la cortesía solo vale con el claim hecho).
  delete from public.daily_briefs where user_id = '00000000-0000-0000-0000-0000000b0f01';
  e := public.daily_brief_entitlement('00000000-0000-0000-0000-0000000b0f01', pg_temp.bday());
  perform pg_temp.check_true('free sin claim', e ->> 'variant' = 'numbers' and e ->> 'courtesy' = 'false');
  -- Con el claim de cortesía hecho: full + courtesy.
  insert into public.daily_briefs (user_id, brief_day, status, variant, courtesy)
  values ('00000000-0000-0000-0000-0000000b0f01', pg_temp.bday(), 'generating', 'full', true);
  e := public.daily_brief_entitlement('00000000-0000-0000-0000-0000000b0f01', pg_temp.bday());
  perform pg_temp.check_true('free con cortesía', e ->> 'variant' = 'full' and e ->> 'courtesy' = 'true');

  -- Usuario sin posiciones: vacío, sin error.
  e := public.daily_brief_entitlement('00000000-0000-0000-0000-0000000b0d01', pg_temp.bday());
  perform pg_temp.check_true('sin cartera', e -> 'held' = '[]'::jsonb and e -> 'markets' = '[]'::jsonb);
  -- Usuario fuera del interruptor.
  perform pg_temp.check_true('fuera del interruptor',
    public.daily_brief_entitlement(gen_random_uuid(), pg_temp.bday()) ->> 'enabled' = 'false');
end $$;

-- ── 13. Push: insumos y calentamiento ────────────────────────────────────────

do $$
declare r record; n int;
begin
  insert into public.push_devices (user_id, token, platform, timezone) values
    ('00000000-0000-0000-0000-0000000b0a01', 'brief-token-p1-0123456789', 'ios', 'America/New_York'),
    ('00000000-0000-0000-0000-0000000b0a02', 'brief-token-p2-0123456789', 'ios', 'America/New_York'),
    ('00000000-0000-0000-0000-0000000b0c01', 'brief-token-g1-0123456789', 'ios', 'Asia/Tokyo');
  select * into r from public.daily_brief_push_inputs(array['00000000-0000-0000-0000-0000000b0a01'::uuid]);
  perform pg_temp.check_true('push inputs', r.tier = 'premium' and r.brief_on and r.push_piece
    and r.big_move_sensitivity = 'normal' and not r.show_amounts
    and jsonb_array_length(r.holdings) = 2);
  select count(*) into n from public.daily_brief_push_inputs(array['00000000-0000-0000-0000-0000000b0a01'::uuid,
    '00000000-0000-0000-0000-0000000b0a02'::uuid]);
  perform pg_temp.check_true('push inputs en lote', n = 2);

  -- Más tenidos por huso, con conteo y sin user_id.
  perform pg_temp.check_true('warm_symbols sin user_id', not exists (
    select 1 from information_schema.routines r2, information_schema.parameters p
     where r2.routine_name = 'daily_brief_warm_symbols' and p.specific_name = r2.specific_name
       and p.parameter_mode = 'OUT' and p.parameter_name = 'user_id'));
  perform pg_temp.check_true('warm_symbols NY',
    (select array_agg(symbol order by symbol) from public.daily_brief_warm_symbols(array['America/New_York'], 10))
      = array['AAPL', 'BTC-USD', 'MELI.BA', 'NVDA']);
  perform pg_temp.check_true('AAPL tenida por 1 de NY (p2)',
    (select holders from public.daily_brief_warm_symbols(array['America/New_York'], 10) where symbol = 'AAPL') = 1);
  perform pg_temp.check_true('warm_symbols limit',
    (select count(*) from public.daily_brief_warm_symbols(array['America/New_York'], 2)) = 2);
  perform pg_temp.check_true('warm_symbols Tokyo', (select array_agg(symbol) from public.daily_brief_warm_symbols(array['Asia/Tokyo'], 10)) = array['MSFT']);
  perform pg_temp.check_true('warm_symbols sin husos', (select count(*) from public.daily_brief_warm_symbols(array['Europe/Madrid'], 10)) = 0);

  -- `daily_brief` cuenta en el tope diario de automáticas.
  insert into public.notification_log (user_id, kind) values ('00000000-0000-0000-0000-0000000b0a01', 'daily_brief');
  perform pg_temp.check_true('tope diario', (select automatic_last_24h from public.push_dispatch_context(
    array['00000000-0000-0000-0000-0000000b0a01'::uuid])) = 1);
  insert into public.notification_outbox (user_id, kind, dedupe_key)
  values ('00000000-0000-0000-0000-0000000b0a01', 'daily_brief', 'daily_brief:test');
end $$;

-- ── 14. Borrar un usuario se lleva todo lo suyo ──────────────────────────────

do $$
begin
  delete from auth.users where id = '00000000-0000-0000-0000-0000000b0a01';
  perform pg_temp.check_true('cascade', not exists (select 1 from public.daily_briefs where user_id = '00000000-0000-0000-0000-0000000b0a01')
    and not exists (select 1 from public.user_news_topics where user_id = '00000000-0000-0000-0000-0000000b0a01')
    and not exists (select 1 from public.user_news_sources where user_id = '00000000-0000-0000-0000-0000000b0a01'));
end $$;

rollback;

select 'DAILY_BRIEF_DB_TEST_OK' as result;
