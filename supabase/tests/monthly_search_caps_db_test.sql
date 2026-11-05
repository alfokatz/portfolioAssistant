-- Test de 20261105100400_monthly_search_caps.sql (topes mensuales de
-- web-search y news-context).
--
-- Corre contra una base con las migraciones aplicadas (supabase start). Si
-- termina, imprime MONTHLY_SEARCH_CAPS_DB_TEST_OK.
--
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/monthly_search_caps_db_test.sql
--
-- Todo corre dentro de una transacción que se deshace al final.

begin;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'free@test.local'),
  ('00000000-0000-0000-0000-0000000000a2', 'premium@test.local'),
  ('00000000-0000-0000-0000-0000000000a3', 'gold@test.local'),
  ('00000000-0000-0000-0000-0000000000a4', 'otro@test.local');
insert into public.user_subscriptions (user_id, tier, status) values
  ('00000000-0000-0000-0000-0000000000a1', 'free', 'active'),
  ('00000000-0000-0000-0000-0000000000a2', 'premium', 'active'),
  ('00000000-0000-0000-0000-0000000000a3', 'gold', 'active'),
  ('00000000-0000-0000-0000-0000000000a4', 'free', 'active')
on conflict (user_id) do update set tier = excluded.tier, status = excluded.status;

-- 1. Límites por plan.
do $$
begin
  if (select array_agg(web_searches_per_month order by tier) from public.plan_limits) <> array[15, 100, 60] then
    raise exception 'web_searches_per_month (free,gold,premium): %',
      (select array_agg(tier || '=' || web_searches_per_month) from public.plan_limits);
  end if;
  if (select array_agg(news_context_per_month order by tier) from public.plan_limits) <> array[10, 160, 80] then
    raise exception 'news_context_per_month (free,gold,premium): %',
      (select array_agg(tier || '=' || news_context_per_month) from public.plan_limits);
  end if;
end $$;

-- 2. Permisos: solo la service role.
set local role authenticated;
do $$
begin
  begin
    perform public.web_search_quota_hit('00000000-0000-0000-0000-0000000000a1');
    raise exception 'authenticated pudo llamar web_search_quota_hit';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.news_context_quota_hit('00000000-0000-0000-0000-0000000000a1', 1);
    raise exception 'authenticated pudo llamar news_context_quota_hit';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.web_search_hit('00000000-0000-0000-0000-0000000000a1');
    raise exception 'authenticated pudo llamar web_search_hit';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.news_context_hit('00000000-0000-0000-0000-0000000000a1');
    raise exception 'authenticated pudo llamar news_context_hit';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

set local role service_role;

-- 3. web-search: tope diario (Free = 3) con la RPC nueva.
do $$
declare r jsonb;
begin
  for i in 1..3 loop
    r := public.web_search_quota_hit('00000000-0000-0000-0000-0000000000a1');
    if r <> '{"ok": true}'::jsonb then raise exception 'web diario %: %', i, r; end if;
  end loop;
  r := public.web_search_quota_hit('00000000-0000-0000-0000-0000000000a1');
  if r <> '{"ok": false, "reason": "daily_limit"}'::jsonb then raise exception 'web 4.º del día: %', r; end if;
  if (select count from public.web_search_usage where user_id = '00000000-0000-0000-0000-0000000000a1'
       and day = (now() at time zone 'utc')::date) <> 3 then
    raise exception 'el rechazo diario no revirtió el incremento';
  end if;
end $$;

-- 4. web-search: tope mensual (se sube el diario para llegar al mensual).
reset role;
update public.plan_limits set web_searches_per_day = 100 where tier = 'free';
-- Un mes anterior con mucho uso no cuenta.
insert into public.web_search_usage (user_id, day, count)
values ('00000000-0000-0000-0000-0000000000a1', (date_trunc('month', now() at time zone 'utc') - interval '1 day')::date, 99);
set local role service_role;
do $$
declare r jsonb;
begin
  -- Hoy ya tiene 3 de las 15 del mes.
  for i in 4..15 loop
    r := public.web_search_quota_hit('00000000-0000-0000-0000-0000000000a1');
    if r <> '{"ok": true}'::jsonb then raise exception 'web mensual %: %', i, r; end if;
  end loop;
  r := public.web_search_quota_hit('00000000-0000-0000-0000-0000000000a1');
  if r <> '{"ok": false, "reason": "monthly_limit"}'::jsonb then raise exception 'web 16.º del mes: %', r; end if;
  if (select count from public.web_search_usage where user_id = '00000000-0000-0000-0000-0000000000a1'
       and day = (now() at time zone 'utc')::date) <> 15 then
    raise exception 'el rechazo mensual no revirtió el incremento';
  end if;
  -- Otro usuario Free no se ve afectado.
  r := public.web_search_quota_hit('00000000-0000-0000-0000-0000000000a4');
  if r <> '{"ok": true}'::jsonb then raise exception 'otro usuario: %', r; end if;
end $$;

-- 5. La booleana vieja aplica el tope mensual (db push protege sin deploy).
do $$
begin
  if public.web_search_hit('00000000-0000-0000-0000-0000000000a1') is not false then
    raise exception 'web_search_hit ignora el tope mensual';
  end if;
  if public.web_search_hit('00000000-0000-0000-0000-0000000000a4') is not true then
    raise exception 'web_search_hit rechazó a un usuario con cupo';
  end if;
end $$;

-- 6. news-context: unidades, tope diario de PEDIDOS y tope mensual de UNIDADES.
do $$
declare r jsonb;
begin
  -- Un pedido de 3 búsquedas: 1 pedido del día, 3 unidades.
  r := public.news_context_quota_hit('00000000-0000-0000-0000-0000000000a2', 3);
  if r <> '{"ok": true}'::jsonb then raise exception 'news 3 unidades: %', r; end if;
  if (select count || '/' || units from public.news_context_usage
       where user_id = '00000000-0000-0000-0000-0000000000a2' and day = (now() at time zone 'utc')::date) <> '1/3' then
    raise exception 'news count/units: %', (select count || '/' || units from public.news_context_usage
       where user_id = '00000000-0000-0000-0000-0000000000a2');
  end if;
  -- Unidades fuera de 1..5 no gastan nada.
  foreach r in array array[
    public.news_context_quota_hit('00000000-0000-0000-0000-0000000000a2', 0),
    public.news_context_quota_hit('00000000-0000-0000-0000-0000000000a2', 6),
    public.news_context_quota_hit('00000000-0000-0000-0000-0000000000a2', null)
  ] loop
    if r <> '{"ok": false, "reason": "invalid_units"}'::jsonb then raise exception 'invalid_units: %', r; end if;
  end loop;
end $$;

reset role;
update public.plan_limits set news_context_per_month = 7 where tier = 'premium';
-- Unidades de un mes anterior no cuentan.
insert into public.news_context_usage (user_id, day, count, units)
values ('00000000-0000-0000-0000-0000000000a2', (date_trunc('month', now() at time zone 'utc') - interval '1 day')::date, 1, 50);
set local role service_role;
do $$
declare r jsonb;
begin
  -- Van 3 de 7: 5 más pasaría el mes.
  r := public.news_context_quota_hit('00000000-0000-0000-0000-0000000000a2', 5);
  if r <> '{"ok": false, "reason": "monthly_limit"}'::jsonb then raise exception 'news 8 de 7: %', r; end if;
  if (select count || '/' || units from public.news_context_usage
       where user_id = '00000000-0000-0000-0000-0000000000a2' and day = (now() at time zone 'utc')::date) <> '1/3' then
    raise exception 'el rechazo mensual no revirtió pedidos ni unidades';
  end if;
  r := public.news_context_quota_hit('00000000-0000-0000-0000-0000000000a2', 4);
  if r <> '{"ok": true}'::jsonb then raise exception 'news justo en el tope: %', r; end if;
  -- Tope mensual agotado: la booleana vieja también corta.
  if public.news_context_hit('00000000-0000-0000-0000-0000000000a2') is not false then
    raise exception 'news_context_hit ignora el tope mensual';
  end if;
end $$;

-- 7. Tope diario de pedidos (Premium = 10 desde held_news; Free = 5).
reset role;
update public.plan_limits set news_context_per_month = 1000 where tier = 'free';
set local role service_role;
do $$
declare r jsonb;
begin
  for i in 1..5 loop
    r := public.news_context_quota_hit('00000000-0000-0000-0000-0000000000a4', 1);
    if r <> '{"ok": true}'::jsonb then raise exception 'news diario %: %', i, r; end if;
  end loop;
  r := public.news_context_quota_hit('00000000-0000-0000-0000-0000000000a4', 1);
  if r <> '{"ok": false, "reason": "daily_limit"}'::jsonb then raise exception 'news 6.º pedido: %', r; end if;
  if public.news_context_hit('00000000-0000-0000-0000-0000000000a4') is not false then
    raise exception 'news_context_hit ignora el tope diario';
  end if;
end $$;

reset role;

select 'MONTHLY_SEARCH_CAPS_DB_TEST_OK' as result;

rollback;
