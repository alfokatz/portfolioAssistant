-- Test de 20261105100500_held_news.sql (Premium: noticias solo de lo que tiene).
--
-- Corre contra una base con las migraciones aplicadas (supabase start). Si
-- termina, imprime HELD_NEWS_DB_TEST_OK.
--
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/held_news_db_test.sql
--
-- Todo corre dentro de una transacción que se deshace al final.

begin;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000b1', 'free@test.local'),
  ('00000000-0000-0000-0000-0000000000b2', 'premium@test.local'),
  ('00000000-0000-0000-0000-0000000000b3', 'gold@test.local'),
  ('00000000-0000-0000-0000-0000000000b4', 'premiumvencido@test.local'),
  ('00000000-0000-0000-0000-0000000000b5', 'premiumsincartera@test.local');
insert into public.user_subscriptions (user_id, tier, status) values
  ('00000000-0000-0000-0000-0000000000b1', 'free', 'active'),
  ('00000000-0000-0000-0000-0000000000b2', 'premium', 'active'),
  ('00000000-0000-0000-0000-0000000000b3', 'gold', 'active'),
  ('00000000-0000-0000-0000-0000000000b4', 'premium', 'expired'),
  ('00000000-0000-0000-0000-0000000000b5', 'premium', 'active')
on conflict (user_id) do update set tier = excluded.tier, status = excluded.status;

-- Premium b2 tiene NVDA, GGAL.BA y BTC-USD. Free y el Premium vencido también
-- tienen NVDA: no alcanza. (Una posición en cero no se puede crear: check
-- positions_quantity_positive, igual que en producción.)
insert into public.positions (id, user_id, ticker, quantity, purchase_price, purchase_date) values
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000b2', 'nvda', 1, 100, now()),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000b2', 'GGAL.BA', 10, 5000, now()),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000b2', 'BTC-USD', 0.5, 60000, now()),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000b1', 'NVDA', 1, 100, now()),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000b4', 'NVDA', 1, 100, now());

-- 1. Con el camino legacy, Premium no recibe nada (ni de lo que tiene).
update public.app_config set value = '{"provider": "legacy"}' where key = 'news_provider';
do $$
begin
  if public.news_data_allowed('00000000-0000-0000-0000-0000000000b2', 'NVDA') then
    raise exception 'Premium con news_provider legacy';
  end if;
end $$;

-- 2. Con v2.
update public.app_config set value = '{"provider": "v2"}' where key = 'news_provider';
do $$
declare
  p constant uuid := '00000000-0000-0000-0000-0000000000b2';
begin
  if not public.news_data_allowed(p, 'NVDA') then raise exception 'Premium + NVDA en cartera'; end if;
  if not public.news_data_allowed(p, 'nvda') then raise exception 'Premium + nvda en minúsculas'; end if;
  -- Sufijos de bolsa y cripto, tal como vienen en el pedido.
  if not public.news_data_allowed(p, 'GGAL.BA') then raise exception 'Premium + GGAL.BA'; end if;
  if not public.news_data_allowed(p, 'BTC-USD') then raise exception 'Premium + BTC-USD'; end if;
  -- Ajeno y sin ticker.
  if public.news_data_allowed(p, 'TSLA') then raise exception 'Premium + ticker ajeno'; end if;
  if public.news_data_allowed(p, null) then raise exception 'Premium sin ticker'; end if;
  if public.news_data_allowed(p) then raise exception 'Premium con default'; end if;
  -- El ticker normalizado de la SEC (BTC.USD) no es el de la cartera.
  if public.news_data_allowed(p, 'BTC.USD') then raise exception 'Premium + BTC.USD normalizado'; end if;
  -- Otros planes y usuarios.
  if public.news_data_allowed('00000000-0000-0000-0000-0000000000b1', 'NVDA') then raise exception 'Free + NVDA'; end if;
  if public.news_data_allowed('00000000-0000-0000-0000-0000000000b4', 'NVDA') then raise exception 'Premium vencido + NVDA'; end if;
  if public.news_data_allowed('00000000-0000-0000-0000-0000000000b5', 'NVDA') then raise exception 'Premium sin cartera + NVDA'; end if;
  -- Gold sigue con todo.
  if not public.news_data_allowed('00000000-0000-0000-0000-0000000000b3', 'TSLA') then raise exception 'Gold + TSLA'; end if;
  if not public.news_data_allowed('00000000-0000-0000-0000-0000000000b3', null) then raise exception 'Gold sin ticker'; end if;
end $$;

-- 3. La cortesía semanal de Free y el informe en curso siguen entrando por Gold.
insert into public.weekly_free_analysis (user_id, week_start, ticker, used_at)
values ('00000000-0000-0000-0000-0000000000b1', date_trunc('week', now())::date, 'AAPL', now());
do $$
begin
  if not public.news_data_allowed('00000000-0000-0000-0000-0000000000b1', 'AAPL') then
    raise exception 'cortesía semanal de Free';
  end if;
  if public.news_data_allowed('00000000-0000-0000-0000-0000000000b1', 'MSFT') then
    raise exception 'la cortesía no es de MSFT';
  end if;
end $$;

-- 4. `sec` sigue siendo solo de Gold.
do $$
begin
  if public.gold_data_allowed('00000000-0000-0000-0000-0000000000b2', 'NVDA') then
    raise exception 'gold_data_allowed dejó pasar a Premium';
  end if;
end $$;

-- 5. Permisos: solo la service role.
set local role authenticated;
do $$
begin
  perform public.news_data_allowed('00000000-0000-0000-0000-0000000000b2', 'NVDA');
  raise exception 'authenticated pudo llamar news_data_allowed';
exception when insufficient_privilege then null;
end $$;
reset role;
set local role service_role;
do $$
begin
  if not public.news_data_allowed('00000000-0000-0000-0000-0000000000b2', 'NVDA') then
    raise exception 'la service role no pudo llamar news_data_allowed';
  end if;
end $$;
reset role;

-- 6. Premium sube a 10 pedidos de news-context por día; Free y Gold no cambian.
do $$
begin
  if (select array_agg(news_context_per_day order by tier) from public.plan_limits) <> array[5, 40, 10] then
    raise exception 'news_context_per_day (free,gold,premium): %',
      (select array_agg(tier || '=' || news_context_per_day) from public.plan_limits);
  end if;
end $$;

select 'HELD_NEWS_DB_TEST_OK' as result;

rollback;
