-- Topes mensuales de las búsquedas pagas (spec 2026-11-05-diferenciacion-planes-v2 §3.6).
-- Además del tope diario, `web-search` y `news-context` quedan acotados por
-- mes UTC (el mismo mes que `_current_usage_month`).
--
--   web_searches_per_month   : búsquedas web (1 por búsqueda sin caché).
--   news_context_per_month   : UNIDADES de news-context = tickers buscados sin
--                              caché (un pedido con 5 tickers gasta hasta 5).
--   news_context_per_day     : sigue contando PEDIDOS, no unidades.
--
-- Las booleanas viejas (`web_search_hit`, `news_context_hit`) se redefinen
-- sobre las nuevas, así el `db push` ya protege el costo aunque las edge
-- functions desplegadas todavía no usen las RPC nuevas.

alter table public.plan_limits
  add column if not exists web_searches_per_month int not null default 0
    check (web_searches_per_month >= 0),
  add column if not exists news_context_per_month int not null default 0
    check (news_context_per_month >= 0);

update public.plan_limits set web_searches_per_month = case tier
  when 'free' then 15
  when 'premium' then 60
  when 'gold' then 100
end
where web_searches_per_month = 0 and tier in ('free', 'premium', 'gold');

update public.plan_limits set news_context_per_month = case tier
  when 'free' then 10
  when 'premium' then 80
  when 'gold' then 160
end
where news_context_per_month = 0 and tier in ('free', 'premium', 'gold');

-- Unidades gastadas por día (el `count` diario sigue siendo de pedidos).
alter table public.news_context_usage
  add column if not exists units int not null default 0 check (units >= 0);
update public.news_context_usage set units = count where units = 0 and count > 0;

-- ---------------------------------------------------------------------------
-- web-search
-- ---------------------------------------------------------------------------

-- {"ok": true} | {"ok": false, "reason": "daily_limit" | "monthly_limit"}
create or replace function public.web_search_quota_hit(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_day date := (now() at time zone 'utc')::date;
  v_month_start date := date_trunc('month', now() at time zone 'utc')::date;
  v_day_limit int;
  v_month_limit int;
  v_day_count int;
  v_month_count int;
begin
  select web_searches_per_day, web_searches_per_month into v_day_limit, v_month_limit
    from public.plan_limits
   where tier = coalesce(public._effective_tier(p_user_id), 'free');

  perform pg_advisory_xact_lock(hashtext('web_search_quota:' || p_user_id::text));

  insert into public.web_search_usage (user_id, day, count)
  values (p_user_id, v_day, 1)
  on conflict (user_id, day)
    do update set count = public.web_search_usage.count + 1
  returning count into v_day_count;

  if v_day_count > coalesce(v_day_limit, 0) then
    update public.web_search_usage set count = count - 1
      where user_id = p_user_id and day = v_day;
    return jsonb_build_object('ok', false, 'reason', 'daily_limit');
  end if;

  select coalesce(sum(count), 0) into v_month_count from public.web_search_usage
   where user_id = p_user_id and day >= v_month_start and day < (v_month_start + interval '1 month')::date;
  if v_month_count > coalesce(v_month_limit, 0) then
    update public.web_search_usage set count = count - 1
      where user_id = p_user_id and day = v_day;
    return jsonb_build_object('ok', false, 'reason', 'monthly_limit');
  end if;
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.web_search_hit(p_user_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select coalesce((public.web_search_quota_hit(p_user_id) ->> 'ok')::boolean, false);
$$;

-- ---------------------------------------------------------------------------
-- news-context
-- ---------------------------------------------------------------------------

-- p_units = búsquedas sin caché del pedido (1..5). Cuenta 1 pedido al día y
-- p_units al mes.
-- {"ok": true} | {"ok": false, "reason": "daily_limit" | "monthly_limit" | "invalid_units"}
create or replace function public.news_context_quota_hit(p_user_id uuid, p_units int)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_day date := (now() at time zone 'utc')::date;
  v_month_start date := date_trunc('month', now() at time zone 'utc')::date;
  v_day_limit int;
  v_month_limit int;
  v_day_count int;
  v_month_units int;
begin
  if p_units is null or p_units < 1 or p_units > 5 then
    return jsonb_build_object('ok', false, 'reason', 'invalid_units');
  end if;
  select news_context_per_day, news_context_per_month into v_day_limit, v_month_limit
    from public.plan_limits
   where tier = coalesce(public._effective_tier(p_user_id), 'free');

  perform pg_advisory_xact_lock(hashtext('news_context_quota:' || p_user_id::text));

  insert into public.news_context_usage (user_id, day, count, units)
  values (p_user_id, v_day, 1, p_units)
  on conflict (user_id, day)
    do update set count = public.news_context_usage.count + 1,
                  units = public.news_context_usage.units + p_units
  returning count into v_day_count;

  if v_day_count > coalesce(v_day_limit, 0) then
    update public.news_context_usage set count = count - 1, units = units - p_units
      where user_id = p_user_id and day = v_day;
    return jsonb_build_object('ok', false, 'reason', 'daily_limit');
  end if;

  select coalesce(sum(units), 0) into v_month_units from public.news_context_usage
   where user_id = p_user_id and day >= v_month_start and day < (v_month_start + interval '1 month')::date;
  if v_month_units > coalesce(v_month_limit, 0) then
    update public.news_context_usage set count = count - 1, units = units - p_units
      where user_id = p_user_id and day = v_day;
    return jsonb_build_object('ok', false, 'reason', 'monthly_limit');
  end if;
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.news_context_hit(p_user_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select coalesce((public.news_context_quota_hit(p_user_id, 1) ->> 'ok')::boolean, false);
$$;

revoke all on function public.web_search_quota_hit(uuid) from public, anon, authenticated;
revoke all on function public.web_search_hit(uuid) from public, anon, authenticated;
revoke all on function public.news_context_quota_hit(uuid, int) from public, anon, authenticated;
revoke all on function public.news_context_hit(uuid) from public, anon, authenticated;
-- Las llaman las edge functions con la service role.
grant execute on function public.web_search_quota_hit(uuid) to service_role;
grant execute on function public.web_search_hit(uuid) to service_role;
grant execute on function public.news_context_quota_hit(uuid, int) to service_role;
grant execute on function public.news_context_hit(uuid) to service_role;
