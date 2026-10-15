-- Fuentes de datos con uso comercial para noticias, resultados y
-- fundamentals (plan "reemplazar las fuentes de noticias", 2026-10-11):
--
--   - SEC EDGAR (edge function `sec`): presentaciones, resultados y
--     fundamentals. Gratis, sin key; fair access de la SEC.
--   - Búsqueda web de OpenAI (edge function `news-context`): "qué está
--     pasando y por qué", con citas.
--   - GDELT DOC 2.0 (edge function `headlines`): titulares, filtrados por
--     una lista de medios permitidos.
--
-- Todo detrás de `app_config.news_provider` (legacy | v2) para volver
-- atrás sin publicar la app. El acceso por plan se valida en el servidor
-- (`gold_data_allowed`), no solo en la app.

-- ---------------------------------------------------------------------------
-- Interruptor
-- ---------------------------------------------------------------------------

-- Pasar a v2 (y volver con 'legacy'):
--   update public.app_config set value = '{"provider": "v2"}', updated_at = now()
--    where key = 'news_provider';
insert into public.app_config (key, value)
values ('news_provider', '{"provider": "legacy"}'::jsonb)
on conflict (key) do nothing;

create or replace function public._news_provider()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select value ->> 'provider' from public.app_config where key = 'news_provider'),
    'legacy'
  );
$$;

-- ---------------------------------------------------------------------------
-- Ticker → CIK de la SEC (company_tickers.json, se refresca una vez al día)
-- ---------------------------------------------------------------------------

create table if not exists public.sec_ticker_cik (
  ticker text primary key,
  cik text not null check (cik ~ '^[0-9]{10}$'),
  title text not null,
  refreshed_at timestamptz not null default now()
);

alter table public.sec_ticker_cik enable row level security;
-- Sin políticas: solo la service role (las edge functions).

-- ---------------------------------------------------------------------------
-- Caché compartida de las fuentes nuevas (sec:*, news:*, gdelt:*)
-- ---------------------------------------------------------------------------

create table if not exists public.data_source_cache (
  cache_key text primary key,
  body jsonb not null,
  fetched_at timestamptz not null default now()
);

create index if not exists data_source_cache_fetched_idx
  on public.data_source_cache (fetched_at);

alter table public.data_source_cache enable row level security;

-- ---------------------------------------------------------------------------
-- Limitador global por fuente externa (GDELT pide 1 pedido cada 5 s)
-- ---------------------------------------------------------------------------

create table if not exists public.upstream_rate_gate (
  source text primary key,
  next_allowed_at timestamptz not null default now()
);

alter table public.upstream_rate_gate enable row level security;

-- `true` = se puede llamar ahora (y reserva el próximo turno dentro de
-- p_interval_ms). Atómico entre instancias de la función.
create or replace function public.upstream_rate_take(p_source text, p_interval_ms int)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_taken int;
begin
  insert into public.upstream_rate_gate (source, next_allowed_at)
  values (p_source, now() - interval '1 second')
  on conflict (source) do nothing;

  update public.upstream_rate_gate
     set next_allowed_at = now() + make_interval(secs => p_interval_ms / 1000.0)
   where source = p_source and next_allowed_at <= now();
  get diagnostics v_taken = row_count;
  return v_taken = 1;
end;
$$;

revoke all on function public.upstream_rate_take(text, int) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Medios permitidos (titulares de GDELT y allowed_domains de la búsqueda web)
-- ---------------------------------------------------------------------------

create table if not exists public.news_source_allowlist (
  domain text primary key check (domain ~ '^[a-z0-9.-]+\.[a-z]{2,}$'),
  name text not null,
  lang text not null check (lang in ('es', 'en')),
  enabled boolean not null default true
);

alter table public.news_source_allowlist enable row level security;

insert into public.news_source_allowlist (domain, name, lang) values
  ('reuters.com', 'Reuters', 'en'),
  ('apnews.com', 'AP', 'en'),
  ('cnbc.com', 'CNBC', 'en'),
  ('bloomberg.com', 'Bloomberg', 'en'),
  ('ft.com', 'Financial Times', 'en'),
  ('wsj.com', 'The Wall Street Journal', 'en'),
  ('marketwatch.com', 'MarketWatch', 'en'),
  ('barrons.com', 'Barron''s', 'en'),
  ('finance.yahoo.com', 'Yahoo Finance', 'en'),
  ('investing.com', 'Investing.com', 'en'),
  ('nytimes.com', 'The New York Times', 'en'),
  ('economist.com', 'The Economist', 'en'),
  ('forbes.com', 'Forbes', 'en'),
  ('fortune.com', 'Fortune', 'en'),
  ('businessinsider.com', 'Business Insider', 'en'),
  ('axios.com', 'Axios', 'en'),
  ('bbc.com', 'BBC', 'en'),
  ('ambito.com', 'Ámbito', 'es'),
  ('infobae.com', 'Infobae', 'es'),
  ('lanacion.com.ar', 'La Nación', 'es'),
  ('cronista.com', 'El Cronista', 'es'),
  ('iproup.com', 'iProUP', 'es'),
  ('clarin.com', 'Clarín', 'es'),
  ('expansion.com', 'Expansión', 'es'),
  ('eleconomista.es', 'El Economista', 'es'),
  ('eleconomista.com.mx', 'El Economista (MX)', 'es'),
  ('cincodias.elpais.com', 'Cinco Días', 'es'),
  ('elpais.com', 'El País', 'es')
on conflict (domain) do nothing;

-- ---------------------------------------------------------------------------
-- Acceso a los datos de Gold, validado en el servidor
-- ---------------------------------------------------------------------------

-- `true` si el usuario puede ver datos de Gold de [p_ticker]:
--   - tiene Gold activo; o
--   - es el ticker del análisis de cortesía de esta semana
--     (`weekly_free_analysis`, que la app gasta ANTES de pedir los datos); o
--   - está generando su informe semanal (`claim_weekly_report` lo habilitó,
--     incluida la degustación) y el pedido no trae ticker o es de su
--     informe — el informe pide titulares y resultados de su cartera.
create or replace function public.gold_data_allowed(p_user_id uuid, p_ticker text default null)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public._effective_tier(p_user_id), 'free') = 'gold'
    or (p_ticker is not null and exists (
      select 1 from public.weekly_free_analysis w
       where w.user_id = p_user_id
         and w.ticker = upper(p_ticker)
         and w.used_at > now() - interval '8 days'))
    or exists (
      select 1 from public.weekly_reports r
       where r.user_id = p_user_id
         and r.status = 'generating'
         and r.claimed_at > now() - interval '30 minutes');
$$;

revoke all on function public.gold_data_allowed(uuid, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- news-context: tope diario por plan y costo de la búsqueda web por turno
-- ---------------------------------------------------------------------------

alter table public.plan_limits
  add column if not exists news_context_per_day int not null default 0
    check (news_context_per_day >= 0);

-- Solo Gold (más la cortesía/informe, que entran por gold_data_allowed y
-- usan el tope de Gold). Un hit de caché no cuenta.
update public.plan_limits set news_context_per_day = case tier
  when 'gold' then 40
  else 5
end
where news_context_per_day = 0;

create table if not exists public.news_context_usage (
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null,
  count int not null default 0,
  primary key (user_id, day)
);

alter table public.news_context_usage enable row level security;

create or replace function public.news_context_hit(p_user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tier text := coalesce(public._effective_tier(p_user_id), 'free');
  v_limit int;
  v_count int;
begin
  select news_context_per_day into v_limit from public.plan_limits where tier = v_tier;
  insert into public.news_context_usage (user_id, day, count)
  values (p_user_id, current_date, 1)
  on conflict (user_id, day)
    do update set count = public.news_context_usage.count + 1
  returning count into v_count;
  if v_count > coalesce(v_limit, 0) then
    update public.news_context_usage set count = count - 1
      where user_id = p_user_id and day = current_date;
    return false;
  end if;
  return true;
end;
$$;

revoke all on function public.news_context_hit(uuid) from public, anon, authenticated;

alter table public.ai_turn_usage
  add column if not exists web_search_calls int not null default 0,
  add column if not exists web_search_cost_usd numeric(12, 6) not null default 0;

-- El turno al que se le carga una búsqueda: el de [p_turn_id] si es del
-- usuario; si no viene, su turno más reciente de los últimos 10 minutos
-- (las tools corren entre rondas del turno, que ya tiene su fila).
create or replace function public._turn_for_web_search(p_user_id uuid, p_turn_id text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select turn_id from public.ai_turn_usage
   where user_id = p_user_id
     and (case when p_turn_id is not null then turn_id = p_turn_id
               else created_at > now() - interval '10 minutes' end)
   order by created_at desc
   limit 1;
$$;

-- Búsquedas web ya hechas en el turno (para el tope de 1 por turno).
create or replace function public.turn_web_search_calls(p_user_id uuid, p_turn_id text default null)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select web_search_calls from public.ai_turn_usage
      where turn_id = public._turn_for_web_search(p_user_id, p_turn_id)),
    0);
$$;

create or replace function public.record_web_search_usage(
  p_user_id uuid,
  p_turn_id text,
  p_calls int,
  p_cost_usd numeric
)
returns void
language sql
security definer
set search_path = public
as $$
  update public.ai_turn_usage
     set web_search_calls = web_search_calls + p_calls,
         web_search_cost_usd = web_search_cost_usd + p_cost_usd
   where turn_id = public._turn_for_web_search(p_user_id, p_turn_id);
$$;

revoke all on function public._turn_for_web_search(uuid, text) from public, anon, authenticated;
revoke all on function public.turn_web_search_calls(uuid, text) from public, anon, authenticated;
revoke all on function public.record_web_search_usage(uuid, text, int, numeric) from public, anon, authenticated;

-- Misma vista de 20260930120000, con las búsquedas web al final (una vista
-- solo admite columnas nuevas al final).
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
      then sum(cached_tokens)::numeric / sum(prompt_tokens) end as cache_ratio,
    sum(web_search_calls) as web_search_calls,
    sum(web_search_cost_usd) as web_search_cost_usd
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
  avg(cache_ratio) as avg_cache_ratio,
  sum(web_search_calls) as web_search_calls_total,
  sum(web_search_cost_usd) as web_search_cost_total_usd
from per_user
group by month, tier;

revoke all on public.ai_usage_monthly_stats from public, anon, authenticated;
grant select on public.ai_usage_monthly_stats to service_role;
