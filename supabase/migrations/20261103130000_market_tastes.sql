-- Free prueba Premium: 3 consultas de mercado por mes
-- (docs/superpowers/specs/2026-11-03-free-prueba-premium.md §3.1 y §3.2).
-- Requiere 20261103110000_rollout_flag_sql.sql.
--
-- Prender (lo hace el usuario):
--   update public.app_config set value = '{"percent": 100, "users": []}'::jsonb, updated_at = now()
--    where key = 'market_taste';

insert into public.app_config (key, value)
values ('market_taste', '{"percent": 0, "users": []}'::jsonb)
on conflict (key) do nothing;

-- Espejo de PlanSpec.marketDataTastesPerMonth (el servidor manda).
alter table public.plan_limits
  add column if not exists market_tastes_per_month int not null default 0
    check (market_tastes_per_month >= 0);
update public.plan_limits set market_tastes_per_month = 3
 where tier = 'free' and market_tastes_per_month = 0;

-- Una fila por turno que usó una degustación. La PK hace idempotente el
-- "usar" (reintentos del mismo turno no gastan otra).
create table if not exists public.market_tastes (
  user_id uuid not null references auth.users (id) on delete cascade,
  turn_id text not null,
  month text not null check (month ~ '^\d{4}-\d{2}$'),
  tickers text[] not null,
  used_at timestamptz not null default now(),
  primary key (user_id, turn_id)
);
create index if not exists market_tastes_user_month_idx
  on public.market_tastes (user_id, month);

alter table public.market_tastes enable row level security;
drop policy if exists "Users read own market tastes" on public.market_tastes;
create policy "Users read own market tastes" on public.market_tastes
  for select using (auth.uid() = user_id);
revoke all on public.market_tastes from public, anon, authenticated;
grant select on public.market_tastes to authenticated;
grant select, insert, update, delete on public.market_tastes to service_role;

-- Límite mensual de degustaciones del plan efectivo (0 si no hay fila).
create or replace function public._market_taste_limit(p_user_id uuid)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select market_tastes_per_month from public.plan_limits
     where tier = coalesce(public._effective_tier(p_user_id), 'free')),
    0
  );
$$;
revoke all on function public._market_taste_limit(uuid) from public, anon, authenticated;

create or replace function public.market_taste_status()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_month text := public._current_usage_month();
  v_limit int;
  v_used int;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  v_limit := public._market_taste_limit(v_uid);
  if v_limit <= 0 or not public._rollout_on('market_taste', v_uid) then
    return jsonb_build_object(
      'enabled', false, 'limit', 0, 'used', 0, 'remaining', 0, 'month', v_month
    );
  end if;
  select count(*) into v_used from public.market_tastes
  where user_id = v_uid and month = v_month;
  return jsonb_build_object(
    'enabled', true, 'limit', v_limit, 'used', v_used,
    'remaining', greatest(v_limit - v_used, 0), 'month', v_month
  );
end;
$$;

create or replace function public.consume_market_taste(p_turn_id text, p_tickers text[])
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_month text := public._current_usage_month();
  v_limit int;
  v_used int;
  v_tickers text[];
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  -- Mismo formato que acepta ai-chat en x-porty-turn-id.
  if p_turn_id is null or p_turn_id !~ '^[A-Za-z0-9_-]{8,64}$' then
    return jsonb_build_object('ok', false, 'reason', 'invalid_turn_id');
  end if;
  if p_tickers is null or cardinality(p_tickers) not between 1 and 6 then
    return jsonb_build_object('ok', false, 'reason', 'invalid_tickers');
  end if;
  select array_agg(distinct upper(t)) into v_tickers from unnest(p_tickers) as t;
  if v_tickers is null or exists (
    select 1 from unnest(v_tickers) as t where t is null or t !~ '^[A-Z0-9.\-]{1,12}$'
  ) then
    return jsonb_build_object('ok', false, 'reason', 'invalid_tickers');
  end if;

  if not public._rollout_on('market_taste', v_uid) then
    return jsonb_build_object('ok', false, 'reason', 'disabled', 'remaining', 0, 'limit', 0);
  end if;
  v_limit := public._market_taste_limit(v_uid);
  if v_limit <= 0 then
    return jsonb_build_object('ok', false, 'reason', 'not_eligible', 'remaining', 0, 'limit', 0);
  end if;

  perform pg_advisory_xact_lock(hashtext('market_taste:' || v_uid::text));

  select count(*) into v_used from public.market_tastes
  where user_id = v_uid and month = v_month;

  if exists (
    select 1 from public.market_tastes where user_id = v_uid and turn_id = p_turn_id
  ) then
    return jsonb_build_object(
      'ok', true, 'remaining', greatest(v_limit - v_used, 0), 'limit', v_limit, 'reused', true
    );
  end if;

  if v_used >= v_limit then
    return jsonb_build_object('ok', false, 'reason', 'exhausted', 'remaining', 0, 'limit', v_limit);
  end if;

  insert into public.market_tastes (user_id, turn_id, month, tickers)
  values (v_uid, p_turn_id, v_month, v_tickers);
  return jsonb_build_object(
    'ok', true, 'remaining', v_limit - v_used - 1, 'limit', v_limit, 'reused', false
  );
end;
$$;

revoke all on function public.market_taste_status() from public, anon;
revoke all on function public.consume_market_taste(text, text[]) from public, anon;
grant execute on function public.market_taste_status() to authenticated;
grant execute on function public.consume_market_taste(text, text[]) to authenticated;
