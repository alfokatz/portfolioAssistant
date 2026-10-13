-- Landing de validación de Porty (repo porty-web): lista de espera, eventos
-- del embudo y métricas por variante del titular. Todo pasa por la edge
-- function `landing` (service role): el cliente anónimo no lee ni escribe
-- estas tablas, y no hay políticas de RLS que lo habiliten.
--
-- Privacidad: no se guarda IP ni user agent. El rate limit usa un hash de la
-- IP con sal (lo calcula la función) y sus ventanas se borran a los minutos.

-- ---------------------------------------------------------------------------
-- Lista de espera
-- ---------------------------------------------------------------------------

create table if not exists public.waitlist (
  id uuid primary key default gen_random_uuid(),
  email text not null unique
    check (email = lower(email) and length(email) between 3 and 254),
  -- Orden de llegada: los primeros entran a la beta cerrada. Un email
  -- repetido no consume número (el alta es select-then-insert, ver
  -- `landing_signup`); solo una carrera entre dos altas puede dejar un hueco.
  position bigserial not null unique,
  created_at timestamptz not null default now(),
  variant text not null check (variant in ('a', 'b', 'c')),
  intended_plan text check (intended_plan in ('free', 'premium', 'gold')),
  utm_source text check (length(utm_source) <= 100),
  utm_medium text check (length(utm_medium) <= 100),
  utm_campaign text check (length(utm_campaign) <= 100),
  utm_content text check (length(utm_content) <= 100),
  ref_code text not null unique check (ref_code ~ '^[A-Z2-9]{6}$'),
  referred_by text references public.waitlist (ref_code) on delete set null,
  country text check (country ~ '^[A-Z]{2}$'),
  consent boolean not null check (consent),
  beta_invited_at timestamptz
);

create index if not exists waitlist_referred_by_idx on public.waitlist (referred_by);

alter table public.waitlist enable row level security;

-- ---------------------------------------------------------------------------
-- Eventos del embudo
-- ---------------------------------------------------------------------------

create table if not exists public.landing_events (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  -- Id aleatorio del navegador (localStorage). No identifica a la persona.
  anon_id text not null check (length(anon_id) between 8 and 64),
  variant text check (variant in ('a', 'b', 'c')),
  event text not null check (event in (
    'page_view', 'form_view', 'signup', 'pricing_view', 'plan_click',
    'founder_modal_open', 'founder_signup'
  )),
  plan text check (plan in ('free', 'premium', 'gold')),
  path text check (length(path) <= 200),
  utm_source text check (length(utm_source) <= 100),
  utm_medium text check (length(utm_medium) <= 100),
  utm_campaign text check (length(utm_campaign) <= 100),
  utm_content text check (length(utm_content) <= 100)
);

create index if not exists landing_events_created_idx on public.landing_events (created_at);

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
-- Alta en la lista
-- ---------------------------------------------------------------------------

-- Código propio para compartir: 6 caracteres sin los ambiguos (0/O, 1/I/L).
create or replace function public._landing_ref_code()
returns text
language sql
volatile
as $$
  select string_agg(substr('ABCDEFGHJKMNPQRSTUVWXYZ23456789', 1 + floor(random() * 31)::int, 1), '')
  from generate_series(1, 6);
$$;

-- Alta idempotente por email. Si el email ya está, devuelve su puesto sin
-- duplicarlo y, si llega un plan, lo actualiza. Registra el evento `signup`
-- (solo la primera vez) y `founder_signup` (cada vez que llega un plan) del
-- lado del servidor, así las métricas no dependen de bloqueadores.
-- Devuelve {position, ref_code, created}.
create or replace function public.landing_signup(
  p_email text,
  p_variant text,
  p_intended_plan text default null,
  p_utm jsonb default '{}'::jsonb,
  p_referred_by text default null,
  p_country text default null,
  p_anon_id text default null,
  p_path text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := lower(trim(p_email));
  v_row public.waitlist;
  v_created boolean := false;
  v_ref text;
begin
  select * into v_row from public.waitlist where email = v_email;

  if not found then
    -- Solo vale un código de alguien que ya está en la lista.
    if p_referred_by is not null then
      select ref_code into v_ref from public.waitlist where ref_code = upper(p_referred_by);
    end if;

    for i in 1..5 loop
      begin
        insert into public.waitlist (
          email, variant, intended_plan, utm_source, utm_medium, utm_campaign,
          utm_content, ref_code, referred_by, country, consent
        ) values (
          v_email, p_variant, p_intended_plan,
          left(p_utm ->> 'utm_source', 100), left(p_utm ->> 'utm_medium', 100),
          left(p_utm ->> 'utm_campaign', 100), left(p_utm ->> 'utm_content', 100),
          public._landing_ref_code(), v_ref, p_country, true
        )
        returning * into v_row;
        v_created := true;
        exit;
      exception when unique_violation then
        -- Otro alta del mismo email ganó la carrera: devolvemos esa fila.
        select * into v_row from public.waitlist where email = v_email;
        exit when found;
        -- Si no, chocó el ref_code: probamos otro.
      end;
    end loop;

    if v_row.id is null then
      raise exception 'landing_signup: no se pudo generar un ref_code';
    end if;
  elsif p_intended_plan is not null then
    update public.waitlist set intended_plan = p_intended_plan
    where id = v_row.id
    returning * into v_row;
  end if;

  if p_anon_id is not null then
    if v_created then
      insert into public.landing_events (anon_id, variant, event, path,
        utm_source, utm_medium, utm_campaign, utm_content)
      values (p_anon_id, p_variant, 'signup', p_path,
        left(p_utm ->> 'utm_source', 100), left(p_utm ->> 'utm_medium', 100),
        left(p_utm ->> 'utm_campaign', 100), left(p_utm ->> 'utm_content', 100));
    end if;
    if p_intended_plan is not null then
      insert into public.landing_events (anon_id, variant, event, plan, path,
        utm_source, utm_medium, utm_campaign, utm_content)
      values (p_anon_id, p_variant, 'founder_signup', p_intended_plan, p_path,
        left(p_utm ->> 'utm_source', 100), left(p_utm ->> 'utm_medium', 100),
        left(p_utm ->> 'utm_campaign', 100), left(p_utm ->> 'utm_content', 100));
    end if;
  end if;

  return jsonb_build_object(
    'position', v_row.position,
    'ref_code', v_row.ref_code,
    'created', v_created
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Métricas del checkpoint
-- ---------------------------------------------------------------------------

-- Por variante: por día (hora de Buenos Aires) y acumulado (`day` null).
-- Visitas únicas = navegadores distintos con algún page_view. Registros y
-- precio fundador salen de los eventos que escribe `landing_signup`, con la
-- variante que el visitante tenía al registrarse.
create or replace view public.landing_stats
with (security_invoker = true)
as
with e as (
  select
    (created_at at time zone 'America/Argentina/Buenos_Aires')::date as day,
    coalesce(variant, '?') as variant,
    anon_id, event, plan
  from public.landing_events
)
select
  day,
  variant,
  count(distinct anon_id) filter (where event = 'page_view') as unique_visitors,
  count(*) filter (where event = 'signup') as signups,
  round(
    count(*) filter (where event = 'signup')::numeric
      / nullif(count(distinct anon_id) filter (where event = 'page_view'), 0),
    4
  ) as conversion_rate,
  count(distinct anon_id) filter (where event = 'pricing_view') as pricing_visitors,
  count(*) filter (where event = 'plan_click' and plan = 'free') as clicks_free,
  count(*) filter (where event = 'plan_click' and plan = 'premium') as clicks_premium,
  count(*) filter (where event = 'plan_click' and plan = 'gold') as clicks_gold,
  count(*) filter (where event = 'founder_modal_open') as founder_modal_opens,
  count(*) filter (where event = 'founder_signup') as founder_signups,
  count(*) filter (where event = 'founder_signup' and plan = 'premium') as founder_signups_premium,
  count(*) filter (where event = 'founder_signup' and plan = 'gold') as founder_signups_gold
from e
group by grouping sets ((day, variant), (variant))
order by day nulls first, variant;

-- ---------------------------------------------------------------------------
-- Permisos: solo la service role (edge function y SQL editor del dashboard)
-- ---------------------------------------------------------------------------

revoke all on public.waitlist, public.landing_events, public.landing_rate_limits,
  public.landing_stats from public, anon, authenticated;
revoke all on function public.landing_rate_hit(text, text, int) from public, anon, authenticated;
revoke all on function public._landing_ref_code() from public, anon, authenticated;
revoke all on function public.landing_signup(text, text, text, jsonb, text, text, text, text)
  from public, anon, authenticated;

grant usage on schema public to service_role;
grant select, insert, update, delete on
  public.waitlist, public.landing_events, public.landing_rate_limits
to service_role;
grant usage, select on sequence public.waitlist_position_seq to service_role;
grant select on public.landing_stats to service_role;
grant execute on function
  public.landing_rate_hit(text, text, int),
  public._landing_ref_code(),
  public.landing_signup(text, text, text, jsonb, text, text, text, text)
to service_role;
