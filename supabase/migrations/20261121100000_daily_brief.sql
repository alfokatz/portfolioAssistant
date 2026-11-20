-- Brief diario de tu cartera: esquema, RPC, interruptor y cron
-- (docs/superpowers/specs/2026-11-20-brief-diario-tech.md §3.2 y §3.3).
-- Requiere 20261103110000_rollout_flag_sql.sql (`_rollout_on`).
--
-- Todo detrás de `app_config.daily_brief`, que arranca APAGADO: con el
-- interruptor apagado `claim_daily_brief` devuelve `disabled`,
-- `daily_brief_status.enabled = false`, `ai_brief_begin` corta y el cron de
-- `news-warm` no llama a nada. Nada de lo que ya existe cambia de
-- comportamiento (el check de `ai_turn_usage.purpose` y de
-- `notification_outbox.kind` solo aceptan un valor más).
--
-- Prender (lo hace el usuario, con OK; el historial queda en
-- `app_config_history`):
--   update public.app_config
--      set value = value || '{"percent": 100}'::jsonb, updated_at = now()
--    where key = 'daily_brief';
-- o para la lista interna: `{"users": ["<uuid>", ...]}`.

-- ---------------------------------------------------------------------------
-- Interruptor y ayudas
-- ---------------------------------------------------------------------------

insert into public.app_config (key, value)
values (
  'daily_brief',
  '{"percent": 0, "users": [], "courtesy_days": 7, "courtesy_since": "2026-12-01",
    "pieces": {"push": true, "feed": true, "topics": true, "sources": true,
               "market": true, "compare": true, "videos": true}}'::jsonb
)
on conflict (key) do nothing;

create or replace function public._daily_brief_on(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public._rollout_on('daily_brief', p_user_id);
$$;

-- Sub-interruptor de una pieza (`pieces.<clave>`). Si la clave falta o no es
-- booleana, vale true: apagar es una decisión explícita.
create or replace function public._daily_brief_piece(p_key text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select case
              when jsonb_typeof(value -> 'pieces' -> p_key) = 'boolean'
                then (value -> 'pieces' ->> p_key)::boolean
              else true
            end
       from public.app_config where key = 'daily_brief'),
    true
  );
$$;

-- Briefs completos de cortesía para una alta nueva: `courtesy_days` acotado
-- a 1..15 (7 si falta o no es número).
create or replace function public._daily_brief_courtesy_days()
returns int
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select least(greatest(floor((value ->> 'courtesy_days')::numeric), 1), 15)::int
       from public.app_config
      where key = 'daily_brief' and jsonb_typeof(value -> 'courtesy_days') = 'number'),
    7
  );
$$;

-- Fecha desde la que una cuenta es "alta nueva" con cortesía. Falla cerrado:
-- sin fila o con un valor que no es fecha, null = nadie recibe cortesía (la
-- base actual no recibe regalo sin que el usuario lo decida).
create or replace function public._daily_brief_courtesy_since()
returns timestamptz
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_raw text;
begin
  select value ->> 'courtesy_since' into v_raw
    from public.app_config where key = 'daily_brief';
  if v_raw is null then
    return null;
  end if;
  return (v_raw::date)::timestamp at time zone 'utc';
exception when others then
  return null;
end;
$$;

-- true si el interruptor está prendido para alguien (percent > 0 o la lista
-- interna no está vacía): el cron de `news-warm` no llama a nada si no.
create or replace function public._daily_brief_cron_on()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select (jsonb_typeof(value -> 'percent') = 'number' and (value ->> 'percent')::numeric > 0)
         or (jsonb_typeof(value -> 'users') = 'array' and jsonb_array_length(value -> 'users') > 0)
       from public.app_config where key = 'daily_brief'),
    false
  );
$$;

-- Día del brief plausible: entre ayer y mañana en UTC (margen por zona
-- horaria; adelantar el reloj del teléfono no habilita días futuros) y hábil.
create or replace function public._daily_brief_valid_day(p_day date)
returns boolean
language sql
stable
as $$
  select p_day is not null
    and extract(isodow from p_day) between 1 and 5
    and p_day between (now() at time zone 'utc')::date - 1
                  and (now() at time zone 'utc')::date + 1;
$$;

revoke all on function public._daily_brief_on(uuid) from public, anon, authenticated;
revoke all on function public._daily_brief_piece(text) from public, anon, authenticated;
revoke all on function public._daily_brief_courtesy_days() from public, anon, authenticated;
revoke all on function public._daily_brief_courtesy_since() from public, anon, authenticated;
revoke all on function public._daily_brief_cron_on() from public, anon, authenticated;
revoke all on function public._daily_brief_valid_day(date) from public, anon, authenticated;
grant execute on function
  public._daily_brief_on(uuid),
  public._daily_brief_piece(text),
  public._daily_brief_courtesy_days(),
  public._daily_brief_courtesy_since(),
  public._daily_brief_cron_on(),
  public._daily_brief_valid_day(date)
to service_role;

-- ---------------------------------------------------------------------------
-- Columnas nuevas en news_source_allowlist
-- ---------------------------------------------------------------------------

alter table public.news_source_allowlist
  add column if not exists region text not null default 'global',
  add column if not exists kind text not null default 'media'
    check (kind in ('media', 'official')),
  -- null = no va en la cláusula `domain:` de GDELT.
  add column if not exists gdelt_priority smallint;

-- La pantalla de medios lee solo estas columnas (no `enabled` ni la
-- prioridad de GDELT): se saca el acceso a la tabla entera y se concede por
-- columna.
revoke all on public.news_source_allowlist from public, anon, authenticated;
grant select (domain, name, lang, region, kind) on public.news_source_allowlist to authenticated;
grant select, insert, update, delete on public.news_source_allowlist to service_role;

drop policy if exists "Authenticated read enabled allowlist" on public.news_source_allowlist;
create policy "Authenticated read enabled allowlist" on public.news_source_allowlist
  for select to authenticated using (enabled);

-- ---------------------------------------------------------------------------
-- Tablas
-- ---------------------------------------------------------------------------

create table if not exists public.daily_briefs (
  user_id uuid not null references auth.users (id) on delete cascade,
  -- Fecha LOCAL del usuario.
  brief_day date not null,
  status text not null check (status in ('generating', 'ready', 'failed')),
  variant text not null check (variant in ('full', 'numbers')),
  courtesy boolean not null default false,
  payload jsonb,
  attempts smallint not null default 1,
  llm_rounds smallint not null default 0,
  claimed_at timestamptz not null default now(),
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  primary key (user_id, brief_day)
);

create index if not exists daily_briefs_courtesy_idx
  on public.daily_briefs (user_id) where courtesy;
create index if not exists daily_briefs_created_idx
  on public.daily_briefs (created_at);

alter table public.daily_briefs enable row level security;
drop policy if exists "Users read own daily briefs" on public.daily_briefs;
create policy "Users read own daily briefs" on public.daily_briefs
  for select using (auth.uid() = user_id);
-- Sin policies de escritura: solo por las RPC de abajo.
revoke all on public.daily_briefs from public, anon, authenticated;
grant select on public.daily_briefs to authenticated;
grant select, insert, update, delete on public.daily_briefs to service_role;

-- Catálogo cerrado de temas.
create table if not exists public.news_topics (
  id text primary key check (id ~ '^[a-z0-9_]{2,40}$'),
  kind text not null check (kind in ('macro', 'asset', 'sector', 'region', 'market')),
  label_es text not null,
  label_en text not null,
  query_en text not null,
  query_es text not null,
  keywords text[] not null default '{}',
  auto_markets text[] not null default '{}',
  auto_asset_classes text[] not null default '{}',
  -- Frase fija "tenés X que...": mapeo tema → clase de activo.
  asset_link_es text,
  asset_link_en text,
  default_global boolean not null default false,
  region text not null default 'global',
  sort smallint not null default 100,
  enabled boolean not null default true
);

alter table public.news_topics enable row level security;
drop policy if exists "Authenticated read topics" on public.news_topics;
create policy "Authenticated read topics" on public.news_topics
  for select to authenticated using (true);
revoke all on public.news_topics from public, anon, authenticated;
grant select on public.news_topics to authenticated;
grant select, insert, update, delete on public.news_topics to service_role;

create table if not exists public.user_news_topics (
  user_id uuid not null references auth.users (id) on delete cascade,
  topic_id text not null references public.news_topics (id) on delete cascade,
  -- false = apagó un tema "por defecto".
  followed boolean not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, topic_id)
);

alter table public.user_news_topics enable row level security;
drop policy if exists "user_news_topics own" on public.user_news_topics;
create policy "user_news_topics own" on public.user_news_topics
  for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
revoke all on public.user_news_topics from public, anon, authenticated;
grant select, insert, update, delete on public.user_news_topics to authenticated;
grant select, insert, update, delete on public.user_news_topics to service_role;

create table if not exists public.user_news_sources (
  user_id uuid not null references auth.users (id) on delete cascade,
  domain text not null references public.news_source_allowlist (domain) on delete cascade,
  preference text not null check (preference in ('prefer', 'mute')),
  updated_at timestamptz not null default now(),
  primary key (user_id, domain)
);

alter table public.user_news_sources enable row level security;
drop policy if exists "user_news_sources own" on public.user_news_sources;
create policy "user_news_sources own" on public.user_news_sources
  for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
revoke all on public.user_news_sources from public, anon, authenticated;
grant select, insert, update, delete on public.user_news_sources to authenticated;
grant select, insert, update, delete on public.user_news_sources to service_role;

-- Topes: hasta 12 temas seguidos y hasta 10 medios preferidos y 10
-- silenciados. Se aplican en la base (la app solo los muestra). El lock
-- por usuario evita que dos pedidos en paralelo se pasen del tope.
create or replace function public._user_news_topics_limit()
returns trigger
language plpgsql
as $$
begin
  if new.followed then
    perform pg_advisory_xact_lock(hashtext('user_news_topics:' || new.user_id::text));
    if (select count(*) from public.user_news_topics t
         where t.user_id = new.user_id and t.followed
           and t.topic_id <> new.topic_id) >= 12 then
      raise exception 'topic_limit_reached';
    end if;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists user_news_topics_limit on public.user_news_topics;
create trigger user_news_topics_limit
  before insert or update on public.user_news_topics
  for each row execute function public._user_news_topics_limit();

create or replace function public._user_news_sources_limit()
returns trigger
language plpgsql
as $$
begin
  perform pg_advisory_xact_lock(hashtext('user_news_sources:' || new.user_id::text));
  if (select count(*) from public.user_news_sources s
       where s.user_id = new.user_id and s.preference = new.preference
         and s.domain <> new.domain) >= 10 then
    raise exception 'source_limit_reached';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists user_news_sources_limit on public.user_news_sources;
create trigger user_news_sources_limit
  before insert or update on public.user_news_sources
  for each row execute function public._user_news_sources_limit();

create table if not exists public.video_channel_allowlist (
  channel_id text primary key check (channel_id ~ '^UC[A-Za-z0-9_-]{22}$'),
  uploads_playlist_id text not null,
  name text not null,
  outlet_domain text references public.news_source_allowlist (domain),
  lang text not null check (lang in ('es', 'en')),
  region text not null default 'global',
  enabled boolean not null default true
);

alter table public.video_channel_allowlist enable row level security;
revoke all on public.video_channel_allowlist from public, anon, authenticated;
grant select, insert, update, delete on public.video_channel_allowlist to service_role;

-- Caché de videos: se purga a los 7 días.
create table if not exists public.news_videos (
  video_id text primary key,
  channel_id text not null references public.video_channel_allowlist (channel_id) on delete cascade,
  title text not null,
  published_at timestamptz not null,
  lang text not null,
  topic_ids text[] not null default '{}',
  region text not null,
  fetched_at timestamptz not null default now()
);

create index if not exists news_videos_published_idx
  on public.news_videos (published_at desc);

alter table public.news_videos enable row level security;
revoke all on public.news_videos from public, anon, authenticated;
grant select, insert, update, delete on public.news_videos to service_role;

create table if not exists public.market_reference_instruments (
  symbol text primary key,
  kind text not null check (kind in ('index', 'sector', 'commodity', 'rate', 'fx', 'crypto')),
  region text not null,
  label_es text not null,
  label_en text not null,
  -- Mercados de cartera que lo suman a "Mercado hoy".
  markets text[] not null default '{}',
  -- Se muestra siempre.
  core boolean not null default false,
  sort smallint not null default 100,
  enabled boolean not null default true
);

alter table public.market_reference_instruments enable row level security;
drop policy if exists "Authenticated read instruments" on public.market_reference_instruments;
create policy "Authenticated read instruments" on public.market_reference_instruments
  for select to authenticated using (true);
revoke all on public.market_reference_instruments from public, anon, authenticated;
grant select on public.market_reference_instruments to authenticated;
grant select, insert, update, delete on public.market_reference_instruments to service_role;

-- ---------------------------------------------------------------------------
-- Uso de IA: el purpose del brief
-- ---------------------------------------------------------------------------

alter table public.ai_turn_usage
  drop constraint if exists ai_turn_usage_purpose_check;
alter table public.ai_turn_usage
  add constraint ai_turn_usage_purpose_check
  check (purpose in ('chat', 'weekly_report', 'daily_brief'));

-- ---------------------------------------------------------------------------
-- RPC de la app (rol authenticated, auth.uid())
-- ---------------------------------------------------------------------------

-- {enabled, pieces}. Apagado: todo en false (la app no muestra nada nuevo).
create or replace function public.daily_brief_status()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_on boolean;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  v_on := public._daily_brief_on(v_user_id);
  return jsonb_build_object(
    'enabled', v_on,
    'pieces', jsonb_build_object(
      'push', v_on and public._daily_brief_piece('push'),
      'feed', v_on and public._daily_brief_piece('feed'),
      'topics', v_on and public._daily_brief_piece('topics'),
      'sources', v_on and public._daily_brief_piece('sources'),
      'market', v_on and public._daily_brief_piece('market'),
      'compare', v_on and public._daily_brief_piece('compare'),
      'videos', v_on and public._daily_brief_piece('videos')
    )
  );
end;
$$;

-- Qué hacer con el brief de un día. Devuelve {state, ...}:
-- - disabled         → el interruptor no cubre al usuario
-- - no_portfolio     → sin posiciones
-- - not_business_day → el día no es hábil o no es plausible
-- - ready            → ya está: {payload, variant, courtesy}
-- - claimed          → generalo vos ahora: {variant:'full', courtesy,
--                      courtesy_number?, courtesy_total?, attempt}
-- - numbers_only     → sin plan ni cortesía: la app arma los números sin LLM
-- - in_progress      → otro dispositivo lo está generando
-- - failed           → se agotaron los intentos
-- Mismo patrón que claim_weekly_report (20261103120000).
create or replace function public.claim_daily_brief(p_day date)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_tier text;
  v_row public.daily_briefs%rowtype;
  v_courtesy boolean;
  v_limit int;
  v_used int;
  v_since timestamptz;
  v_created timestamptz;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  if not public._daily_brief_on(v_user_id) then
    return jsonb_build_object('state', 'disabled');
  end if;
  if not public._daily_brief_valid_day(p_day) then
    return jsonb_build_object('state', 'not_business_day');
  end if;
  if not exists (
    select 1 from public.positions where user_id = v_user_id and quantity > 0
  ) then
    return jsonb_build_object('state', 'no_portfolio');
  end if;

  v_tier := coalesce(public._effective_tier(v_user_id), 'free');

  select * into v_row from public.daily_briefs
  where user_id = v_user_id and brief_day = p_day
  for update;

  if found then
    if v_row.status = 'ready' then
      return jsonb_build_object(
        'state', 'ready', 'payload', v_row.payload,
        'variant', v_row.variant, 'courtesy', v_row.courtesy
      );
    end if;
    if v_row.status = 'generating'
       and v_row.claimed_at > now() - public._report_claim_ttl() then
      return jsonb_build_object('state', 'in_progress');
    end if;
    if v_row.attempts >= public._report_max_attempts() then
      if v_row.status <> 'failed' then
        update public.daily_briefs set status = 'failed'
        where user_id = v_user_id and brief_day = p_day;
      end if;
      return jsonb_build_object('state', 'failed');
    end if;
    update public.daily_briefs
    set status = 'generating',
        attempts = attempts + 1,
        claimed_at = now()
    where user_id = v_user_id and brief_day = p_day;
    if v_row.courtesy then
      -- Número de este regalo: los regalos hasta este día inclusive.
      select count(*) into v_used from public.daily_briefs
      where user_id = v_user_id and courtesy and brief_day <= p_day;
      return jsonb_build_object(
        'state', 'claimed', 'variant', 'full', 'courtesy', true,
        'attempt', v_row.attempts + 1,
        'courtesy_number', v_used,
        'courtesy_total', public._daily_brief_courtesy_days()
      );
    end if;
    return jsonb_build_object(
      'state', 'claimed', 'variant', 'full', 'courtesy', false,
      'attempt', v_row.attempts + 1
    );
  end if;

  if v_tier in ('premium', 'gold') then
    v_courtesy := false;
  else
    -- Cortesía: solo altas desde `courtesy_since` y hasta `courtesy_days`
    -- briefs. El lock serializa los claims del mismo usuario: dos
    -- dispositivos para días distintos verían el mismo v_used y
    -- regalarían uno de más.
    v_since := public._daily_brief_courtesy_since();
    select created_at into v_created from auth.users where id = v_user_id;
    if v_since is null or v_created is null or v_created < v_since then
      return jsonb_build_object('state', 'numbers_only');
    end if;
    v_limit := public._daily_brief_courtesy_days();
    perform pg_advisory_xact_lock(hashtext('daily_brief_courtesy:' || v_user_id::text));
    select count(*) into v_used from public.daily_briefs
    where user_id = v_user_id and courtesy;
    if v_used >= v_limit then
      return jsonb_build_object('state', 'numbers_only');
    end if;
    v_courtesy := true;
  end if;

  insert into public.daily_briefs (user_id, brief_day, status, variant, courtesy)
  values (v_user_id, p_day, 'generating', 'full', v_courtesy)
  on conflict (user_id, brief_day) do nothing;
  if not found then
    -- Otro dispositivo ganó la carrera en este mismo instante.
    return jsonb_build_object('state', 'in_progress');
  end if;

  if v_courtesy then
    return jsonb_build_object(
      'state', 'claimed', 'variant', 'full', 'courtesy', true, 'attempt', 1,
      'courtesy_number', v_used + 1, 'courtesy_total', v_limit
    );
  end if;
  return jsonb_build_object(
    'state', 'claimed', 'variant', 'full', 'courtesy', false, 'attempt', 1
  );
end;
$$;

-- Guarda el brief. `full` solo sobre una fila propia en 'generating' (el
-- claim). `numbers` no necesita claim: inserta la fila en 'ready' (o cierra
-- una fila que quedó en generating/failed); si ya está lista, no la pisa.
create or replace function public.complete_daily_brief(
  p_day date,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_variant text;
  v_audio jsonb;
  v_row public.daily_briefs%rowtype;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    return jsonb_build_object('ok', false, 'reason', 'invalid_payload');
  end if;
  if octet_length(p_payload::text) > 65536 then
    return jsonb_build_object('ok', false, 'reason', 'payload_too_large');
  end if;

  v_variant := p_payload ->> 'variant';
  v_audio := p_payload -> 'audio';
  if p_payload ->> 'v' is distinct from '1'
     or p_payload ->> 'day' is distinct from p_day::text
     or v_variant is null or v_variant not in ('full', 'numbers')
     or jsonb_typeof(p_payload -> 'numbers') is distinct from 'object'
     or (p_payload ? 'sources' and jsonb_typeof(p_payload -> 'sources') <> 'object')
     -- Punto de extensión del TTS: null o {url, duration_s}.
     or (v_audio is not null and jsonb_typeof(v_audio) <> 'null' and not coalesce(
           jsonb_typeof(v_audio) = 'object'
           and jsonb_typeof(v_audio -> 'url') = 'string'
           and jsonb_typeof(v_audio -> 'duration_s') = 'number', false)) then
    return jsonb_build_object('ok', false, 'reason', 'invalid_payload');
  end if;

  -- Apagado: no se guarda nada (tampoco los números).
  if not public._daily_brief_on(v_user_id) or not public._daily_brief_valid_day(p_day) then
    return jsonb_build_object('ok', false, 'reason', 'not_claimed');
  end if;

  if v_variant = 'full' then
    update public.daily_briefs
    set status = 'ready', variant = 'full', payload = p_payload, completed_at = now()
    where user_id = v_user_id
      and brief_day = p_day
      and status = 'generating';
    if not found then
      return jsonb_build_object('ok', false, 'reason', 'not_claimed');
    end if;
    return jsonb_build_object('ok', true);
  end if;

  -- numbers
  select * into v_row from public.daily_briefs
  where user_id = v_user_id and brief_day = p_day
  for update;
  if found then
    if v_row.status = 'ready' then
      return jsonb_build_object('ok', true);
    end if;
    update public.daily_briefs
    set status = 'ready', variant = 'numbers', payload = p_payload, completed_at = now()
    where user_id = v_user_id and brief_day = p_day;
    return jsonb_build_object('ok', true);
  end if;
  insert into public.daily_briefs (user_id, brief_day, status, variant, payload, completed_at)
  values (v_user_id, p_day, 'ready', 'numbers', p_payload, now())
  on conflict (user_id, brief_day) do nothing;
  return jsonb_build_object('ok', true);
end;
$$;

-- La generación falló en este intento: libera el claim para reintentar
-- (hasta _report_max_attempts) sin esperar el TTL.
create or replace function public.fail_daily_brief(p_day date)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  update public.daily_briefs
  set status = 'failed'
  where user_id = v_user_id
    and brief_day = p_day
    and status = 'generating';
  return jsonb_build_object('ok', found);
end;
$$;

revoke all on function public.daily_brief_status() from public, anon;
revoke all on function public.claim_daily_brief(date) from public, anon;
revoke all on function public.complete_daily_brief(date, jsonb) from public, anon;
revoke all on function public.fail_daily_brief(date) from public, anon;
grant execute on function
  public.daily_brief_status(),
  public.claim_daily_brief(date),
  public.complete_daily_brief(date, jsonb),
  public.fail_daily_brief(date)
to authenticated;

-- ---------------------------------------------------------------------------
-- RPC del servidor (service role)
-- ---------------------------------------------------------------------------

-- ai_report_begin (20261106100000) contra daily_briefs: antes de cada
-- llamada al LLM del brief. {ok} o {ok:false, reason}: disabled |
-- model_not_allowed | rate_limited | not_claimed | too_many_rounds |
-- turn_mismatch.
create or replace function public.ai_brief_begin(
  p_user_id uuid,
  p_turn_id text,
  p_day date,
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
  v_row public.daily_briefs%rowtype;
  v_owner uuid;
begin
  -- Apagado a mitad de una generación: no se gasta ni una llamada más.
  if not public._daily_brief_on(p_user_id) then
    return jsonb_build_object('ok', false, 'reason', 'disabled');
  end if;
  if not exists (
    select 1 from public.model_prices where model = p_model and allowed
  ) then
    return jsonb_build_object('ok', false, 'reason', 'model_not_allowed');
  end if;

  if not public.rate_limit_hit(p_user_id, 'ai', p_rate_per_minute) then
    return jsonb_build_object('ok', false, 'reason', 'rate_limited');
  end if;

  select * into v_row from public.daily_briefs
  where user_id = p_user_id and brief_day = p_day
  for update;
  if not found
     or v_row.status <> 'generating'
     or v_row.variant <> 'full'
     or v_row.claimed_at <= now() - public._report_claim_ttl() then
    return jsonb_build_object('ok', false, 'reason', 'not_claimed');
  end if;
  if v_row.llm_rounds >= p_max_rounds then
    return jsonb_build_object('ok', false, 'reason', 'too_many_rounds');
  end if;

  insert into public.ai_turn_usage (turn_id, user_id, tier, model, purpose)
  values (
    p_turn_id, p_user_id,
    coalesce(public._effective_tier(p_user_id), 'free'), p_model,
    'daily_brief'
  )
  on conflict (turn_id) do nothing;
  select user_id into v_owner from public.ai_turn_usage where turn_id = p_turn_id;
  if v_owner <> p_user_id then
    return jsonb_build_object('ok', false, 'reason', 'turn_mismatch');
  end if;

  update public.daily_briefs
  set llm_rounds = llm_rounds + 1
  where user_id = p_user_id and brief_day = p_day;
  update public.ai_turn_usage
  set round_count = round_count + 1
  where turn_id = p_turn_id;

  return jsonb_build_object('ok', true);
end;
$$;

-- Todo lo que `daily-brief` necesita saber del usuario, en una consulta. Solo
-- service role: la función deriva todo de [p_user_id] (el del JWT), nunca de
-- lo que mande el cliente.
--
--   {enabled, pieces, tier, variant, courtesy,
--    held:[{symbol, weight_pct}], watchlist:[symbol], topics:[id],
--    prefer:[domain], mute:[domain], markets:[...], asset_classes:[...]}
--
-- - `variant`/`courtesy` salen de la fila del día. Sin fila, Premium y Gold
--   son `full`; cualquier otro es `numbers`: la cortesía solo vale con el
--   claim hecho (la app reclama antes de pedir el bundle), así que sin
--   claim no se puede leer lo de la cartera sin gastar un día de cortesía.
-- - `watchlist` solo con Gold.
-- - `topics` = (por defecto según mercados y clases de la cartera o
--   globales) ∪ seguidos − apagados.
-- - Sin posiciones, `held` y `markets` vienen vacíos.
create or replace function public.daily_brief_entitlement(p_user_id uuid, p_day date)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_on boolean := public._daily_brief_on(p_user_id);
  v_tier text;
  v_row public.daily_briefs%rowtype;
  v_variant text;
  v_courtesy boolean := false;
  v_held jsonb;
  v_watch jsonb := '[]'::jsonb;
  v_markets text[];
  v_classes text[];
  v_topics jsonb;
  v_prefer jsonb;
  v_mute jsonb;
begin
  if not v_on or p_user_id is null then
    return jsonb_build_object(
      'enabled', false,
      'pieces', jsonb_build_object(
        'push', false, 'feed', false, 'topics', false, 'sources', false,
        'market', false, 'compare', false, 'videos', false)
    );
  end if;

  v_tier := coalesce(public._effective_tier(p_user_id), 'free');

  select * into v_row from public.daily_briefs
  where user_id = p_user_id and brief_day = p_day;
  if found then
    v_variant := v_row.variant;
    v_courtesy := v_row.courtesy;
  elsif v_tier in ('premium', 'gold') then
    v_variant := 'full';
  else
    v_variant := 'numbers';
  end if;

  -- Cartera: una fila por ticker en mayúsculas, con su peso.
  with h as (
    select upper(p.ticker) as symbol
      from public.positions p
     where p.user_id = p_user_id
     group by upper(p.ticker)
    having sum(p.quantity) > 0
  ),
  w as (
    select upper(symbol) as symbol, weight_pct
      from public.push_holding_weights(array[p_user_id])
  )
  select coalesce(jsonb_agg(jsonb_build_object('symbol', h.symbol, 'weight_pct', w.weight_pct)
                            order by w.weight_pct desc nulls last, h.symbol), '[]'::jsonb)
    into v_held
    from h left join w on w.symbol = h.symbol;

  -- Mercados (sufijo de la bolsa; sin sufijo = EE. UU.; .A/.B/.C son clases
  -- de acciones, no una bolsa) y clases de activo (quoteType de Yahoo).
  with h as (
    select upper(p.ticker) as symbol
      from public.positions p
     where p.user_id = p_user_id
     group by upper(p.ticker)
    having sum(p.quantity) > 0
  ),
  c as (
    select h.symbol,
           q.quote_type,
           coalesce(h.symbol ~ '-(USD|USDT|EUR)$' or q.quote_type = 'CRYPTOCURRENCY', false) as is_crypto,
           substring(h.symbol from '\.([A-Z]{1,3})$') as suffix
      from h left join public.market_quotes q on q.symbol = h.symbol
  )
  select
    coalesce(array_agg(distinct
      case when is_crypto then null
           when suffix is null or suffix in ('A', 'B', 'C') then 'US'
           else '.' || suffix end
    ) filter (where not is_crypto), '{}'),
    coalesce(array_agg(distinct
      case when is_crypto then 'crypto'
           when quote_type = 'ETF' then 'etf'
           else 'equity' end
    ), '{}')
    into v_markets, v_classes
    from c;
  v_markets := array_remove(v_markets, null);

  if v_tier = 'gold' then
    select coalesce(jsonb_agg(w.symbol order by w.created_at, w.symbol), '[]'::jsonb)
      into v_watch
      from public.watchlist_items w
     where w.user_id = p_user_id;
  end if;

  select coalesce(jsonb_agg(t.id order by t.sort, t.id), '[]'::jsonb)
    into v_topics
    from public.news_topics t
   where t.enabled
     and (
       exists (select 1 from public.user_news_topics u
                where u.user_id = p_user_id and u.topic_id = t.id and u.followed)
       or (
         not exists (select 1 from public.user_news_topics u
                      where u.user_id = p_user_id and u.topic_id = t.id and not u.followed)
         and (t.default_global
              or t.auto_markets && v_markets
              or t.auto_asset_classes && v_classes)
       )
     );

  select coalesce(jsonb_agg(s.domain order by s.domain) filter (where s.preference = 'prefer'), '[]'::jsonb),
         coalesce(jsonb_agg(s.domain order by s.domain) filter (where s.preference = 'mute'), '[]'::jsonb)
    into v_prefer, v_mute
    from public.user_news_sources s
   where s.user_id = p_user_id;

  return jsonb_build_object(
    'enabled', true,
    'pieces', jsonb_build_object(
      'push', public._daily_brief_piece('push'),
      'feed', public._daily_brief_piece('feed'),
      'topics', public._daily_brief_piece('topics'),
      'sources', public._daily_brief_piece('sources'),
      'market', public._daily_brief_piece('market'),
      'compare', public._daily_brief_piece('compare'),
      'videos', public._daily_brief_piece('videos')
    ),
    'tier', v_tier,
    'variant', v_variant,
    'courtesy', v_courtesy,
    'held', v_held,
    'watchlist', v_watch,
    'topics', v_topics,
    'prefer', v_prefer,
    'mute', v_mute,
    'markets', to_jsonb(v_markets),
    'asset_classes', to_jsonb(v_classes)
  );
end;
$$;

-- Insumos del push de las 8 de [p_user_ids]: tenencias, plan, sensibilidad,
-- si el interruptor y la pieza `push` están prendidos y `show_amounts`.
-- `last_brief_day` = último brief listo (para exigir "un cierre nuevo").
create or replace function public.daily_brief_push_inputs(p_user_ids uuid[])
returns table (
  user_id uuid,
  tier text,
  big_move_sensitivity text,
  brief_on boolean,
  push_piece boolean,
  show_amounts boolean,
  last_brief_day date,
  holdings jsonb
)
language sql
stable
security definer
set search_path = public
as $$
  select
    u.id,
    coalesce(public._effective_tier(u.id), 'free'),
    coalesce(np.big_move_sensitivity, 'normal'),
    public._daily_brief_on(u.id),
    public._daily_brief_piece('push'),
    coalesce(np.show_amounts, false),
    (select max(b.brief_day) from public.daily_briefs b
      where b.user_id = u.id and b.status = 'ready'),
    coalesce(
      (select jsonb_agg(jsonb_build_object(
                'symbol', h.symbol, 'weight_pct', w.weight_pct)
              order by w.weight_pct desc nulls last, h.symbol)
         from (
           select upper(p.ticker) as symbol
             from public.positions p
            where p.user_id = u.id
            group by upper(p.ticker)
           having sum(p.quantity) > 0
         ) h
         left join public.push_holding_weights(array[u.id]) w
           on upper(w.symbol) = h.symbol),
      '[]'::jsonb
    )
  from auth.users u
  left join public.notification_preferences np on np.user_id = u.id
  where u.id = any (p_user_ids);
$$;

-- Los símbolos más tenidos por usuarios cuyo dispositivo más reciente está en
-- alguno de [p_timezones] (con el interruptor prendido), con cuántos usuarios
-- los tienen. Sin `user_id`: es para calentar la caché de titulares.
create or replace function public.daily_brief_warm_symbols(
  p_timezones text[],
  p_limit int default 200
)
returns table (symbol text, holders int)
language sql
stable
security definer
set search_path = public
as $$
  with latest as (
    select distinct on (d.user_id) d.user_id, d.timezone
      from public.push_devices d
     order by d.user_id, d.last_seen_at desc
  )
  select upper(p.ticker) as symbol, count(distinct p.user_id)::int as holders
    from latest l
    join public.positions p on p.user_id = l.user_id and p.quantity > 0
   where l.timezone = any (p_timezones)
     and public._daily_brief_on(l.user_id)
   group by upper(p.ticker)
   order by holders desc, symbol
   limit least(greatest(coalesce(p_limit, 200), 1), 500);
$$;

revoke all on function public.ai_brief_begin(uuid, text, date, text, int, int) from public, anon, authenticated;
revoke all on function public.daily_brief_entitlement(uuid, date) from public, anon, authenticated;
revoke all on function public.daily_brief_push_inputs(uuid[]) from public, anon, authenticated;
revoke all on function public.daily_brief_warm_symbols(text[], int) from public, anon, authenticated;
grant execute on function
  public.ai_brief_begin(uuid, text, date, text, int, int),
  public.daily_brief_entitlement(uuid, date),
  public.daily_brief_push_inputs(uuid[]),
  public.daily_brief_warm_symbols(text[], int)
to service_role;

-- ---------------------------------------------------------------------------
-- Notificaciones: el kind `daily_brief`
-- ---------------------------------------------------------------------------

-- Lista vigente: 20261024000300_contribution_reminder.sql, más `daily_brief`.
alter table public.notification_outbox
  drop constraint if exists notification_outbox_kind_check;
alter table public.notification_outbox
  add constraint notification_outbox_kind_check check (kind in (
    'test', 'price_alert', 'big_move', 'big_move_digest', 'portfolio_move',
    'weekly_report', 'etoro_reconnect', 'earnings_tomorrow', 'earnings_result',
    'allocation_drift', 'watchlist_move', 'morning_brief',
    'contribution_reminder', 'daily_brief'
  ));

-- Cuerpo vigente: 20261024000000_morning_brief.sql, más `daily_brief` en el
-- conteo de automáticas de 24 h. No hay preferencia nueva: se usa
-- `morning_brief`.
create or replace function public.push_dispatch_context(p_user_ids uuid[])
returns table (
  user_id uuid,
  tier text,
  prefs jsonb,
  devices jsonb,
  automatic_last_24h int
)
language sql
stable
security definer
set search_path = public
as $$
  select
    u.id,
    coalesce(public._effective_tier(u.id), 'free'),
    coalesce(
      (select to_jsonb(p) - 'user_id' - 'updated_at'
         from public.notification_preferences p where p.user_id = u.id),
      jsonb_build_object(
        'enabled', true, 'price_alerts', true, 'big_moves', true,
        'portfolio_moves', true, 'weekly_report', true, 'earnings', true,
        'service', true, 'morning_brief', true,
        'big_move_sensitivity', 'normal',
        'quiet_start', '22:00:00', 'quiet_end', '08:00:00',
        'show_amounts', false)
    ),
    coalesce(
      (select jsonb_agg(jsonb_build_object(
                'id', d.id, 'token', d.token, 'platform', d.platform,
                'locale', d.locale, 'timezone', d.timezone)
              order by d.last_seen_at desc)
         from public.push_devices d where d.user_id = u.id),
      '[]'::jsonb
    ),
    (select count(*)::int from public.notification_log l
      where l.user_id = u.id
        and l.sent_at > now() - interval '24 hours'
        and l.kind in ('big_move', 'big_move_digest', 'portfolio_move',
                       'weekly_report', 'earnings_tomorrow', 'earnings_result',
                       'allocation_drift', 'watchlist_move',
                       'morning_brief', 'daily_brief'))
  from auth.users u
  where u.id = any (p_user_ids);
$$;

revoke all on function public.push_dispatch_context(uuid[]) from public, anon, authenticated;
grant execute on function public.push_dispatch_context(uuid[]) to service_role;

-- ---------------------------------------------------------------------------
-- Cron (pg_cron). `news-warm` llega en la fase 2; mientras el interruptor
-- esté apagado para todos, `_daily_brief_cron_on()` es false y no se llama a
-- nada (tampoco si la función todavía no se desplegó).
-- ---------------------------------------------------------------------------

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule(
      'news-warm', '*/15 * * * *',
      $c$select public._call_function('news-warm') where public._daily_brief_cron_on()$c$
    );
  end if;
end $$;
