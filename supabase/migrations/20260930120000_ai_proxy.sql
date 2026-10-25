-- Proxy de OpenAI y Finnhub: la cuota, los topes y el costo se aplican y se
-- registran en el servidor. Las edge functions `ai-chat` y `finnhub` llaman a
-- estas RPC con la service role; ninguna es ejecutable por la app.
--
-- Cobro: una consulta por turno, cuando el modelo entrega la RESPUESTA FINAL
-- (una ronda sin tool calls). Así un turno cortado por un paywall antes de
-- responder no cuesta nada, y las rondas / reintentos de un mismo turno
-- (mismo turn_id) no vuelven a cobrar.

-- ---------------------------------------------------------------------------
-- Configuración: límites por plan y precios por modelo (un solo lugar)
-- ---------------------------------------------------------------------------

create table if not exists public.plan_limits (
  tier text primary key check (tier in ('free', 'premium', 'gold')),
  monthly_queries int not null check (monthly_queries >= 0),
  -- null = sin tope diario (Free: solo la cuota mensual).
  daily_queries int check (daily_queries is null or daily_queries >= 0),
  updated_at timestamptz not null default now()
);

insert into public.plan_limits (tier, monthly_queries, daily_queries) values
  ('free', 20, null),
  ('premium', 500, 60),
  ('gold', 1000, 100)
on conflict (tier) do nothing;

alter table public.plan_limits enable row level security;
drop policy if exists "Plan limits are public" on public.plan_limits;
create policy "Plan limits are public" on public.plan_limits
  for select using (true);

-- La cuota mensual ahora sale de plan_limits (antes, un CASE fijo).
create or replace function public._monthly_quota(p_tier text)
returns int
language sql
stable
as $$
  select coalesce(
    (select monthly_queries from public.plan_limits where tier = p_tier),
    (select monthly_queries from public.plan_limits where tier = 'free'),
    20
  );
$$;

create or replace function public._daily_quota(p_tier text)
returns int
language sql
stable
as $$
  select daily_queries from public.plan_limits where tier = p_tier;
$$;

-- Precios por 1M tokens (Standard). Verificados en
-- https://developers.openai.com/api/docs/pricing el 2026-09-30.
-- `allowed` = el proxy acepta este modelo (allowlist).
create table if not exists public.model_prices (
  model text primary key,
  input_per_mtok numeric not null,
  cached_input_per_mtok numeric not null,
  output_per_mtok numeric not null,
  allowed boolean not null default false,
  updated_at timestamptz not null default now()
);

insert into public.model_prices
  (model, input_per_mtok, cached_input_per_mtok, output_per_mtok, allowed)
values
  ('gpt-4.1-mini', 0.40, 0.10, 1.60, true),
  ('gpt-4.1-nano', 0.10, 0.025, 0.40, false),
  ('gpt-4.1', 2.00, 0.50, 8.00, false)
on conflict (model) do nothing;

alter table public.model_prices enable row level security;
-- Sin policies: solo la service role.

-- ---------------------------------------------------------------------------
-- Uso por turno (una fila por turno, sumando sus rondas)
-- ---------------------------------------------------------------------------

create table if not exists public.ai_turn_usage (
  turn_id text primary key check (char_length(turn_id) between 8 and 64),
  user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  tier text not null,
  model text not null,
  round_count int not null default 0,
  prompt_tokens bigint not null default 0,
  cached_tokens bigint not null default 0,
  completion_tokens bigint not null default 0,
  cost_usd numeric(12, 6) not null default 0,
  -- Cuándo se cobró la consulta (respuesta final). null = no cobrado.
  charged_at timestamptz
);

create index if not exists ai_turn_usage_user_charged_idx
  on public.ai_turn_usage (user_id, charged_at);
create index if not exists ai_turn_usage_created_idx
  on public.ai_turn_usage (created_at);

alter table public.ai_turn_usage enable row level security;
drop policy if exists "Users read own turn usage" on public.ai_turn_usage;
create policy "Users read own turn usage" on public.ai_turn_usage
  for select using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- Rate limit por usuario (ventana de 1 minuto, por "bucket": ai / finnhub)
-- ---------------------------------------------------------------------------

create table if not exists public.api_rate_limits (
  user_id uuid not null references auth.users (id) on delete cascade,
  bucket text not null,
  window_start timestamptz not null,
  count int not null default 0,
  primary key (user_id, bucket, window_start)
);

alter table public.api_rate_limits enable row level security;

-- true si el pedido entra en el límite (y lo cuenta).
create or replace function public.rate_limit_hit(
  p_user_id uuid,
  p_bucket text,
  p_per_minute int
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_window timestamptz := date_trunc('minute', now());
  v_count int;
begin
  insert into public.api_rate_limits (user_id, bucket, window_start, count)
  values (p_user_id, p_bucket, v_window, 1)
  on conflict (user_id, bucket, window_start)
    do update set count = public.api_rate_limits.count + 1
  returning count into v_count;
  -- Limpieza oportunista de ventanas viejas del mismo usuario.
  delete from public.api_rate_limits
  where user_id = p_user_id and window_start < v_window - interval '10 minutes';
  return v_count <= p_per_minute;
end;
$$;

-- ---------------------------------------------------------------------------
-- RPCs del proxy de OpenAI
-- ---------------------------------------------------------------------------

-- Antes de reenviar una ronda a OpenAI. Devuelve {ok} o {ok:false, reason}:
-- rate_limited | turn_mismatch | too_many_rounds | quota_exceeded |
-- daily_limit | model_not_allowed.
create or replace function public.ai_begin_request(
  p_user_id uuid,
  p_turn_id text,
  p_model text,
  p_max_rounds int,
  p_rate_per_minute int
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tier text;
  v_turn public.ai_turn_usage%rowtype;
  v_used int;
  v_daily_used int;
  v_monthly int;
  v_daily int;
begin
  if not exists (
    select 1 from public.model_prices where model = p_model and allowed
  ) then
    return jsonb_build_object('ok', false, 'reason', 'model_not_allowed');
  end if;

  if not public.rate_limit_hit(p_user_id, 'ai', p_rate_per_minute) then
    return jsonb_build_object('ok', false, 'reason', 'rate_limited');
  end if;

  v_tier := coalesce(public._effective_tier(p_user_id), 'free');

  insert into public.ai_turn_usage (turn_id, user_id, tier, model)
  values (p_turn_id, p_user_id, v_tier, p_model)
  on conflict (turn_id) do nothing;

  select * into v_turn from public.ai_turn_usage
  where turn_id = p_turn_id
  for update;

  if v_turn.user_id <> p_user_id then
    return jsonb_build_object('ok', false, 'reason', 'turn_mismatch');
  end if;

  if v_turn.round_count >= p_max_rounds then
    return jsonb_build_object('ok', false, 'reason', 'too_many_rounds');
  end if;

  -- Un turno ya cobrado puede seguir (p. ej. el repair de la surface).
  if v_turn.charged_at is null then
    v_monthly := public._monthly_quota(v_tier);
    select coalesce(queries_used, 0) into v_used
    from public.ai_usage_monthly
    where user_id = p_user_id and month = public._current_usage_month();
    if coalesce(v_used, 0) >= v_monthly then
      return jsonb_build_object(
        'ok', false, 'reason', 'quota_exceeded',
        'queries_used', coalesce(v_used, 0), 'queries_limit', v_monthly
      );
    end if;

    v_daily := public._daily_quota(v_tier);
    if v_daily is not null then
      select count(*) into v_daily_used from public.ai_turn_usage
      where user_id = p_user_id
        and charged_at >= date_trunc('day', now() at time zone 'utc');
      if v_daily_used >= v_daily then
        return jsonb_build_object(
          'ok', false, 'reason', 'daily_limit', 'daily_limit', v_daily
        );
      end if;
    end if;
  end if;

  update public.ai_turn_usage
  set round_count = round_count + 1
  where turn_id = p_turn_id;

  return jsonb_build_object('ok', true, 'tier', v_tier);
end;
$$;

-- Después de cada ronda: suma tokens y costo; si fue la respuesta final y el
-- turno no estaba cobrado, cobra 1 consulta (ai_usage_monthly, la misma
-- tabla que lee get_subscription_status).
create or replace function public.ai_record_round(
  p_user_id uuid,
  p_turn_id text,
  p_model text,
  p_prompt_tokens int,
  p_cached_tokens int,
  p_completion_tokens int,
  p_final boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_price public.model_prices%rowtype;
  v_cost numeric := 0;
  v_charged boolean := false;
  v_month text := public._current_usage_month();
begin
  select * into v_price from public.model_prices where model = p_model;
  if found then
    v_cost :=
      (greatest(p_prompt_tokens - p_cached_tokens, 0) * v_price.input_per_mtok
        + p_cached_tokens * v_price.cached_input_per_mtok
        + p_completion_tokens * v_price.output_per_mtok) / 1000000.0;
  end if;

  update public.ai_turn_usage
  set prompt_tokens = prompt_tokens + coalesce(p_prompt_tokens, 0),
      cached_tokens = cached_tokens + coalesce(p_cached_tokens, 0),
      completion_tokens = completion_tokens + coalesce(p_completion_tokens, 0),
      cost_usd = cost_usd + v_cost
  where turn_id = p_turn_id and user_id = p_user_id;

  if p_final then
    update public.ai_turn_usage
    set charged_at = now()
    where turn_id = p_turn_id and user_id = p_user_id and charged_at is null;
    v_charged := found;
    if v_charged then
      insert into public.ai_usage_monthly (user_id, month, queries_used)
      values (p_user_id, v_month, 1)
      on conflict (user_id, month) do update
        set queries_used = public.ai_usage_monthly.queries_used + 1,
            updated_at = now();
    end if;
  end if;

  return jsonb_build_object('ok', true, 'charged', v_charged, 'cost_usd', v_cost);
end;
$$;

-- ---------------------------------------------------------------------------
-- Estadísticas para decidir precios y límites (p50/p90/p99 por usuario)
-- ---------------------------------------------------------------------------

create or replace view public.ai_usage_monthly_stats as
with per_user as (
  select
    to_char(created_at at time zone 'utc', 'YYYY-MM') as month,
    tier,
    user_id,
    count(*) filter (where charged_at is not null) as queries,
    sum(cost_usd) as cost_usd,
    sum(round_count) as rounds,
    case when sum(prompt_tokens) > 0
      then sum(cached_tokens)::numeric / sum(prompt_tokens) end as cache_ratio
  from public.ai_turn_usage
  group by 1, 2, 3
)
select
  month,
  tier,
  count(*) as users,
  percentile_cont(0.5) within group (order by queries) as queries_p50,
  percentile_cont(0.9) within group (order by queries) as queries_p90,
  percentile_cont(0.99) within group (order by queries) as queries_p99,
  percentile_cont(0.5) within group (order by cost_usd) as cost_p50_usd,
  percentile_cont(0.9) within group (order by cost_usd) as cost_p90_usd,
  percentile_cont(0.99) within group (order by cost_usd) as cost_p99_usd,
  sum(cost_usd) as cost_total_usd,
  avg(cache_ratio) as avg_cache_ratio
from per_user
group by month, tier;

revoke all on public.ai_usage_monthly_stats from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Caché compartida de Finnhub (todas las cuentas ven el mismo dato)
-- ---------------------------------------------------------------------------

create table if not exists public.finnhub_cache (
  cache_key text primary key,
  status int not null,
  body jsonb not null,
  fetched_at timestamptz not null default now()
);

alter table public.finnhub_cache enable row level security;
-- Sin policies: solo la service role.

-- ---------------------------------------------------------------------------
-- Webhook de RevenueCat: registro de eventos y errores de sincronización
-- ---------------------------------------------------------------------------

create table if not exists public.subscription_sync_log (
  id bigserial primary key,
  user_id text,
  event_id text,
  event_type text,
  outcome text not null,
  detail text,
  created_at timestamptz not null default now()
);

alter table public.subscription_sync_log enable row level security;

-- ---------------------------------------------------------------------------
-- Permisos: todo esto lo llama solo la service role (edge functions)
-- ---------------------------------------------------------------------------

revoke all on function public.rate_limit_hit(uuid, text, int)
  from public, anon, authenticated;
revoke all on function public.ai_begin_request(uuid, text, text, int, int)
  from public, anon, authenticated;
revoke all on function public.ai_record_round(uuid, text, text, int, int, int, boolean)
  from public, anon, authenticated;

-- Grants explícitos. Los proyectos nuevos de Supabase ya no exponen por
-- defecto lo que se crea en `public` a los roles de la API (y ese pasa a ser
-- el comportamiento fijo): sin esto, ni la service role de las edge
-- functions puede usar estas tablas y funciones.
grant usage on schema public to service_role;
grant select, insert, update, delete on
  public.ai_turn_usage,
  public.api_rate_limits,
  public.finnhub_cache,
  public.subscription_sync_log,
  public.ai_usage_monthly,
  public.user_subscriptions,
  public.plan_limits,
  public.model_prices
to service_role;
grant usage, select on sequence public.subscription_sync_log_id_seq to service_role;
grant select on public.ai_usage_monthly_stats to service_role;
grant execute on function
  public.ai_begin_request(uuid, text, text, int, int),
  public.ai_record_round(uuid, text, text, int, int, int, boolean),
  public.rate_limit_hit(uuid, text, int),
  public.upsert_subscription_from_provider(uuid, text, text, text, text, timestamptz),
  public._current_usage_month(),
  public._monthly_quota(text),
  public._daily_quota(text),
  public._effective_tier(uuid)
to service_role;

-- Lectura propia desde la app (las policies ya filtran por usuario).
grant select on public.plan_limits to anon, authenticated;
grant select on public.ai_turn_usage to authenticated;
