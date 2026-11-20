-- Test de 20261123100000_daily_brief_fixes.sql: la purga no renueva la
-- cortesía, el entitlement ignora filas de días fuera de ventana y
-- `news_compare_allowed` mira el plan efectivo.
--
-- Corre contra una base con las migraciones aplicadas (supabase start). Si
-- termina, imprime DAILY_BRIEF_FIXES_DB_TEST_OK.
--
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/daily_brief_fixes_db_test.sql
--
-- Todo corre dentro de una transacción que se deshace al final.
--
-- Usuarios: f1 free alta nueva (con posiciones), f2 free, p1 premium (NVDA),
-- g1 gold.

begin;

insert into auth.users (id, email, created_at) values
  ('00000000-0000-0000-0000-0000000d0f01', 'f1@test.local', now()),
  ('00000000-0000-0000-0000-0000000d0f02', 'f2@test.local', now()),
  ('00000000-0000-0000-0000-0000000d0a01', 'p1@test.local', now()),
  ('00000000-0000-0000-0000-0000000d0c01', 'g1@test.local', now());
insert into public.user_subscriptions (user_id, tier, status) values
  ('00000000-0000-0000-0000-0000000d0f01', 'free', 'active'),
  ('00000000-0000-0000-0000-0000000d0f02', 'free', 'active'),
  ('00000000-0000-0000-0000-0000000d0a01', 'premium', 'active'),
  ('00000000-0000-0000-0000-0000000d0c01', 'gold', 'active')
on conflict (user_id) do update set tier = excluded.tier, status = excluded.status;
insert into public.positions (id, user_id, ticker, quantity, purchase_price, purchase_date) values
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000d0f01', 'AAPL', 1, 100, now()),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000d0f02', 'AAPL', 1, 100, now()),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000d0a01', 'NVDA', 1, 100, now());

create function pg_temp.as_user(u text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
end;
$$;

create function pg_temp.check_true(label text, ok boolean) returns void language plpgsql as $$
begin
  if ok is not true then raise exception '%', label; end if;
end;
$$;

-- Primer día hábil dentro de la ventana (ayer..mañana UTC).
create function pg_temp.bday() returns date language sql as $$
  select d::date from generate_series(
    (now() at time zone 'utc')::date - 1, (now() at time zone 'utc')::date + 1, interval '1 day') d
  where extract(isodow from d) between 1 and 5
  order by d limit 1;
$$;

-- Día hábil fuera de la ventana (hace 5 a 9 días).
create function pg_temp.old_bday() returns date language sql as $$
  select d::date from generate_series(
    (now() at time zone 'utc')::date - 9, (now() at time zone 'utc')::date - 5, interval '1 day') d
  where extract(isodow from d) between 1 and 5
  order by d desc limit 1;
$$;

update public.app_config set value = jsonb_build_object(
  'percent', 0,
  'users', jsonb_build_array(
    '00000000-0000-0000-0000-0000000d0f01', '00000000-0000-0000-0000-0000000d0f02',
    '00000000-0000-0000-0000-0000000d0a01', '00000000-0000-0000-0000-0000000d0c01'),
  'courtesy_days', 1,
  'courtesy_since', to_char(now() at time zone 'utc' - interval '1 day', 'YYYY-MM-DD')),
  updated_at = now()
where key = 'daily_brief';

-- ── 1. La purga no devuelve la cortesía ──────────────────────────────────────

set local role authenticated;
do $$
begin
  perform pg_temp.as_user('00000000-0000-0000-0000-0000000d0f01');
  perform pg_temp.check_true('primer claim: cortesía',
    (public.claim_daily_brief(pg_temp.bday()) ->> 'courtesy') = 'true');
end $$;
reset role;

-- Pasan 20 días: la fila de cortesía queda vieja. Una fila común vieja de
-- otro usuario sí se purga.
update public.daily_briefs
   set created_at = now() - interval '20 days', brief_day = pg_temp.old_bday()
 where user_id = '00000000-0000-0000-0000-0000000d0f01';
insert into public.daily_briefs (user_id, brief_day, status, variant, courtesy, created_at)
values ('00000000-0000-0000-0000-0000000d0a01', pg_temp.old_bday(), 'ready', 'full', false, now() - interval '20 days');

do $$
declare r jsonb;
begin
  set local role service_role;
  r := public.daily_brief_purge();
  reset role;
  perform pg_temp.check_true('purga borró la fila común', (r ->> 'briefs')::int = 1);
  perform pg_temp.check_true('purga conserva la cortesía usada', exists (
    select 1 from public.daily_briefs
     where user_id = '00000000-0000-0000-0000-0000000d0f01' and courtesy));
end $$;

set local role authenticated;
do $$
declare r jsonb;
begin
  perform pg_temp.as_user('00000000-0000-0000-0000-0000000d0f01');
  r := public.claim_daily_brief(pg_temp.bday());
  perform pg_temp.check_true('Free con cortesía usada no vuelve a tener full: ' || r::text,
    r ->> 'state' = 'numbers_only');
end $$;
reset role;

-- ── 2. Entitlement: día fuera de ventana no usa la fila ──────────────────────

insert into public.daily_briefs (user_id, brief_day, status, variant, courtesy)
values ('00000000-0000-0000-0000-0000000d0f02', pg_temp.old_bday(), 'ready', 'full', false),
       ('00000000-0000-0000-0000-0000000d0f02', pg_temp.bday(), 'ready', 'full', false);

do $$
begin
  perform pg_temp.check_true('día válido: usa la fila (full)',
    public.daily_brief_entitlement('00000000-0000-0000-0000-0000000d0f02', pg_temp.bday()) ->> 'variant' = 'full');
  perform pg_temp.check_true('día fuera de ventana: ignora la fila (numbers)',
    public.daily_brief_entitlement('00000000-0000-0000-0000-0000000d0f02', pg_temp.old_bday()) ->> 'variant' = 'numbers');
  perform pg_temp.check_true('premium sin fila sigue en full',
    public.daily_brief_entitlement('00000000-0000-0000-0000-0000000d0a01', pg_temp.bday()) ->> 'variant' = 'full');
end $$;

-- ── 3. news_compare_allowed ──────────────────────────────────────────────────

insert into public.app_config (key, value) values ('news_provider', '{"provider":"v2"}'::jsonb)
on conflict (key) do update set value = excluded.value;

-- Un informe semanal en curso abre `gold_data_allowed` a un Free; acá no.
insert into public.weekly_reports (user_id, week_start, status, claimed_at)
values ('00000000-0000-0000-0000-0000000d0f02', date_trunc('week', now())::date, 'generating', now());

do $$
declare f2 text := '00000000-0000-0000-0000-0000000d0f02';
begin
  perform pg_temp.check_true('premisa: gold_data_allowed deja pasar al Free con informe en curso',
    public.gold_data_allowed(f2::uuid, 'TSLA'));
  perform pg_temp.check_true('Free con informe en curso no compara un ticker',
    not public.news_compare_allowed(f2::uuid, 'TSLA'));
  perform pg_temp.check_true('Free con informe en curso no compara un tema',
    not public.news_compare_allowed(f2::uuid, null));
  perform pg_temp.check_true('Premium: ticker en cartera',
    public.news_compare_allowed('00000000-0000-0000-0000-0000000d0a01', 'nvda'));
  perform pg_temp.check_true('Premium: ticker fuera de cartera no',
    not public.news_compare_allowed('00000000-0000-0000-0000-0000000d0a01', 'TSLA'));
  perform pg_temp.check_true('Premium: tema no',
    not public.news_compare_allowed('00000000-0000-0000-0000-0000000d0a01', null));
  perform pg_temp.check_true('Gold: ticker cualquiera',
    public.news_compare_allowed('00000000-0000-0000-0000-0000000d0c01', 'TSLA'));
  perform pg_temp.check_true('Gold: tema',
    public.news_compare_allowed('00000000-0000-0000-0000-0000000d0c01', null));
end $$;

-- Permisos: solo service_role.
do $$
declare v_denied boolean;
begin
  set local role authenticated;
  begin
    perform public.news_compare_allowed('00000000-0000-0000-0000-0000000d0c01', null);
    v_denied := false;
  exception when insufficient_privilege then
    v_denied := true;
  end;
  reset role;
  perform pg_temp.check_true('authenticated no puede news_compare_allowed', v_denied);
end $$;

select 'DAILY_BRIEF_FIXES_DB_TEST_OK';
rollback;
