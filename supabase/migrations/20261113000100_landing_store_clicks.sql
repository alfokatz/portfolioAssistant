-- Landing sin lista de espera: la app se publica directo en las tiendas y la
-- landing (repo porty-web, Cloudflare Pages) solo mide el embudo visita →
-- click a la tienda. Reemplaza lo de 20261013000000_landing_waitlist.sql.
--
-- En producción las tablas de la landing se borraron a mano (la migración
-- figura aplicada pero no existen); en una base nueva sí existen. Por eso
-- todo es `if exists` / recrear: el resultado es el mismo en los dos lados.
-- No hay datos que conservar (producción no tiene las tablas y las ramas
-- nuevas están vacías).
--
-- Privacidad: igual que antes, sin IP ni user agent. El país lo pone el
-- proxy de Cloudflare (2 letras) y el rate limit usa un hash de la IP con sal.

-- ---------------------------------------------------------------------------
-- Fuera la lista de espera
-- ---------------------------------------------------------------------------

drop view if exists public.landing_stats;
drop function if exists public.landing_signup(text, text, text, jsonb, text, text, text, text);
drop function if exists public._landing_ref_code();
drop table if exists public.waitlist cascade;
drop sequence if exists public.waitlist_position_seq;

-- ---------------------------------------------------------------------------
-- Eventos del embudo
-- ---------------------------------------------------------------------------

drop table if exists public.landing_events;

create table public.landing_events (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  -- Id aleatorio del navegador (localStorage). No identifica a la persona.
  anon_id text not null check (length(anon_id) between 8 and 64),
  -- Variante del titular (A/B), si la landing está probando una.
  variant text check (variant in ('a', 'b', 'c')),
  event text not null check (event in (
    'page_view', 'pricing_view', 'plan_click', 'store_click'
  )),
  plan text check (plan in ('free', 'premium', 'gold')),
  -- Solo en store_click.
  store text check (store in ('ios', 'android')),
  country text check (country ~ '^[A-Z]{2}$'),
  path text check (length(path) <= 200),
  utm_source text check (length(utm_source) <= 100),
  utm_medium text check (length(utm_medium) <= 100),
  utm_campaign text check (length(utm_campaign) <= 100),
  utm_content text check (length(utm_content) <= 100),
  check ((event = 'store_click') = (store is not null))
);

create index landing_events_created_idx on public.landing_events (created_at);

alter table public.landing_events enable row level security;

-- ---------------------------------------------------------------------------
-- Rate limit por IP (hash con sal, nunca la IP)
-- ---------------------------------------------------------------------------

create table if not exists public.landing_rate_limits (
  key_hash text not null,
  bucket text not null,
  window_start timestamptz not null,
  count int not null default 0,
  primary key (key_hash, bucket, window_start)
);

alter table public.landing_rate_limits enable row level security;

-- Suma un pedido a la ventana del minuto. `true` = puede seguir.
create or replace function public.landing_rate_hit(
  p_key_hash text,
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
  insert into public.landing_rate_limits (key_hash, bucket, window_start, count)
  values (p_key_hash, p_bucket, v_window, 1)
  on conflict (key_hash, bucket, window_start)
    do update set count = public.landing_rate_limits.count + 1
  returning count into v_count;
  -- Limpieza oportunista: ninguna ventana vive más de 10 minutos.
  delete from public.landing_rate_limits where window_start < v_window - interval '10 minutes';
  return v_count <= p_per_minute;
end;
$$;

-- ---------------------------------------------------------------------------
-- Métricas
-- ---------------------------------------------------------------------------

-- Por día y variante (más el total por variante). `store_ctr` = visitantes
-- únicos que tocaron una tienda / visitantes únicos.
create view public.landing_stats
with (security_invoker = true)
as
with e as (
  select
    (created_at at time zone 'America/Argentina/Buenos_Aires')::date as day,
    coalesce(variant, '-') as variant,
    anon_id, event, plan, store
  from public.landing_events
)
select
  day,
  variant,
  count(distinct anon_id) filter (where event = 'page_view') as unique_visitors,
  count(distinct anon_id) filter (where event = 'store_click') as store_clickers,
  round(
    count(distinct anon_id) filter (where event = 'store_click')::numeric
      / nullif(count(distinct anon_id) filter (where event = 'page_view'), 0),
    4
  ) as store_ctr,
  count(*) filter (where event = 'store_click' and store = 'ios') as clicks_ios,
  count(*) filter (where event = 'store_click' and store = 'android') as clicks_android,
  count(distinct anon_id) filter (where event = 'pricing_view') as pricing_visitors,
  count(*) filter (where event = 'plan_click' and plan = 'free') as clicks_free,
  count(*) filter (where event = 'plan_click' and plan = 'premium') as clicks_premium,
  count(*) filter (where event = 'plan_click' and plan = 'gold') as clicks_gold
from e
group by grouping sets ((day, variant), (variant))
order by day nulls first, variant;

-- Por origen de la visita (UTM), para comparar campañas.
create view public.landing_sources
with (security_invoker = true)
as
select
  coalesce(utm_source, '(directo)') as utm_source,
  coalesce(utm_campaign, '-') as utm_campaign,
  count(distinct anon_id) filter (where event = 'page_view') as unique_visitors,
  count(distinct anon_id) filter (where event = 'store_click') as store_clickers,
  round(
    count(distinct anon_id) filter (where event = 'store_click')::numeric
      / nullif(count(distinct anon_id) filter (where event = 'page_view'), 0),
    4
  ) as store_ctr,
  min(created_at) as first_seen,
  max(created_at) as last_seen
from public.landing_events
group by 1, 2
order by unique_visitors desc;

-- ---------------------------------------------------------------------------
-- Permisos: solo la service role (edge function y SQL editor del dashboard)
-- ---------------------------------------------------------------------------

revoke all on public.landing_events, public.landing_rate_limits,
  public.landing_stats, public.landing_sources from public, anon, authenticated;
revoke all on function public.landing_rate_hit(text, text, int) from public, anon, authenticated;

grant usage on schema public to service_role;
grant select, insert, update, delete on public.landing_events, public.landing_rate_limits to service_role;
grant select on public.landing_stats, public.landing_sources to service_role;
grant execute on function public.landing_rate_hit(text, text, int) to service_role;
