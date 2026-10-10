-- Notificaciones push: infraestructura (F1 del plan
-- docs/superpowers/plans/2026-10-10-notificaciones-push.md).
--
-- - `push_devices`: un token de FCM por dispositivo. La app lo registra con
--   `register_push_device` y lo borra al cerrar sesión.
-- - `notification_preferences`: qué quiere recibir cada usuario.
-- - `notification_outbox`: lo que pasó (una alerta cumplida, un movimiento
--   fuerte, el informe listo). Lo escriben los productores (market-watch,
--   daily-jobs, etoro-sync); `notify-dispatch` decide si se manda.
-- - `notification_log`: lo que se mandó. Lo usan el tope diario y las
--   métricas (apertura).
-- - `app_config.push`: interruptor general y por tipo. Arranca apagado.
--
-- Las tareas programadas (pg_cron) NO van acá: la URL del proyecto y el
-- secreto cambian por entorno. Ver docs/runbooks/push-notifications.md.

-- ---------------------------------------------------------------------------
-- Extensiones (Supabase las trae; en un Postgres pelado no existen)
-- ---------------------------------------------------------------------------

do $$
begin
  create extension if not exists pg_cron with schema pg_catalog;
  create extension if not exists pg_net with schema extensions;
exception when others then
  raise notice 'pg_cron / pg_net no disponibles: %', sqlerrm;
end $$;

-- ---------------------------------------------------------------------------
-- Dispositivos
-- ---------------------------------------------------------------------------

create table if not exists public.push_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  -- Token de FCM. Único: si otra cuenta inicia sesión en el mismo teléfono,
  -- el token pasa a esa cuenta (la anterior deja de recibir ahí).
  token text not null unique check (length(token) between 20 and 4096),
  platform text not null check (platform in ('ios', 'android')),
  locale text not null default 'es' check (locale in ('es', 'en')),
  -- Zona IANA del teléfono (America/Argentina/Buenos_Aires). La usan el
  -- horario de silencio y las tareas "a las 9 de la mañana de cada uno".
  timezone text not null default 'UTC',
  app_build int,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index if not exists push_devices_user_idx on public.push_devices (user_id);

alter table public.push_devices enable row level security;

drop policy if exists "push_devices own read" on public.push_devices;
create policy "push_devices own read" on public.push_devices
  for select to authenticated using (auth.uid() = user_id);

revoke all on public.push_devices from public, anon, authenticated;
grant select on public.push_devices to authenticated;
grant select, insert, update, delete on public.push_devices to service_role;

-- Una zona inválida rompería los cálculos de hora local: se cae a UTC.
create or replace function public._valid_timezone(p_tz text)
returns text
language plpgsql
stable
as $$
begin
  if p_tz is null or length(p_tz) > 64 then
    return 'UTC';
  end if;
  perform now() at time zone p_tz;
  return p_tz;
exception when others then
  return 'UTC';
end;
$$;

create or replace function public.register_push_device(
  p_token text,
  p_platform text,
  p_locale text,
  p_timezone text,
  p_app_build int
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_locale text := case when p_locale in ('es', 'en') then p_locale else 'es' end;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  if p_platform not in ('ios', 'android') then
    raise exception 'invalid_platform';
  end if;

  insert into public.push_devices (user_id, token, platform, locale, timezone, app_build, last_seen_at)
  values (v_user_id, p_token, p_platform, v_locale, public._valid_timezone(p_timezone), p_app_build, now())
  on conflict (token) do update
    set user_id = excluded.user_id,
        platform = excluded.platform,
        locale = excluded.locale,
        timezone = excluded.timezone,
        app_build = excluded.app_build,
        last_seen_at = now();

  -- Las preferencias existen desde el primer dispositivo.
  insert into public.notification_preferences (user_id)
  values (v_user_id)
  on conflict (user_id) do nothing;
end;
$$;

create or replace function public.unregister_push_device(p_token text)
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.push_devices
  where token = p_token and user_id = auth.uid();
$$;

-- ---------------------------------------------------------------------------
-- Preferencias
-- ---------------------------------------------------------------------------

create table if not exists public.notification_preferences (
  user_id uuid primary key references auth.users (id) on delete cascade,
  enabled boolean not null default true,
  price_alerts boolean not null default true,
  big_moves boolean not null default true,
  portfolio_moves boolean not null default true,
  weekly_report boolean not null default true,
  earnings boolean not null default true,
  service boolean not null default true,
  big_move_sensitivity text not null default 'normal'
    check (big_move_sensitivity in ('low', 'normal', 'high')),
  quiet_start time not null default '22:00',
  quiet_end time not null default '08:00',
  -- Montos en $ en la pantalla bloqueada. Apagado: solo % y tickers.
  show_amounts boolean not null default false,
  updated_at timestamptz not null default now()
);

alter table public.notification_preferences enable row level security;

drop policy if exists "notification_preferences own" on public.notification_preferences;
create policy "notification_preferences own" on public.notification_preferences
  for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

revoke all on public.notification_preferences from public, anon, authenticated;
grant select, insert, update on public.notification_preferences to authenticated;
grant select, insert, update, delete on public.notification_preferences to service_role;

-- La fila con valores por defecto si todavía no existe.
create or replace function public.get_notification_preferences()
returns public.notification_preferences
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_row public.notification_preferences;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  insert into public.notification_preferences (user_id)
  values (v_user_id)
  on conflict (user_id) do nothing;
  select * into v_row from public.notification_preferences where user_id = v_user_id;
  return v_row;
end;
$$;

-- ---------------------------------------------------------------------------
-- Outbox y log
-- ---------------------------------------------------------------------------

create table if not exists public.notification_outbox (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null check (kind in (
    'test', 'price_alert', 'big_move', 'big_move_digest', 'portfolio_move',
    'weekly_report', 'etoro_reconnect', 'earnings_tomorrow', 'earnings_result'
  )),
  -- Insertar dos veces lo mismo no hace nada: `price_alert:<id>:<fecha>`,
  -- `big_move:NVDA:2026-10-10:down`, `weekly_report:2026-10-05`.
  dedupe_key text not null,
  data jsonb not null default '{}'::jsonb,
  -- No antes de esta hora (el informe que cae en el silencio se corre).
  not_before timestamptz not null default now(),
  status text not null default 'pending'
    check (status in ('pending', 'sending', 'sent', 'skipped', 'failed')),
  skip_reason text,
  attempts int not null default 0,
  -- Lease de `notify-dispatch`: dos corridas a la vez no mandan lo mismo.
  locked_until timestamptz,
  created_at timestamptz not null default now(),
  processed_at timestamptz,
  unique (user_id, dedupe_key)
);

create index if not exists notification_outbox_pending_idx
  on public.notification_outbox (not_before)
  where status in ('pending', 'sending');

alter table public.notification_outbox enable row level security;
-- Sin policies: solo la service role.
revoke all on public.notification_outbox from public, anon, authenticated;
grant select, insert, update, delete on public.notification_outbox to service_role;

create table if not exists public.notification_log (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  outbox_id bigint,
  kind text not null,
  device_count int not null default 0,
  sent_at timestamptz not null default now(),
  opened_at timestamptz
);

create index if not exists notification_log_user_sent_idx
  on public.notification_log (user_id, sent_at desc);

alter table public.notification_log enable row level security;
revoke all on public.notification_log from public, anon, authenticated;
grant select, insert, update, delete on public.notification_log to service_role;

-- La app avisa que el usuario tocó la notificación (métrica de apertura).
create or replace function public.mark_notification_opened(p_log_id bigint)
returns void
language sql
security definer
set search_path = public
as $$
  update public.notification_log
     set opened_at = coalesce(opened_at, now())
   where id = p_log_id and user_id = auth.uid();
$$;

-- "Enviarme una de prueba" (Ajustes → Notificaciones). Una por minuto como
-- mucho: la clave de duplicados lleva el minuto.
create or replace function public.request_test_notification()
returns void
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
  insert into public.notification_outbox (user_id, kind, dedupe_key)
  values (v_user_id, 'test', 'test:' || to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI'))
  on conflict (user_id, dedupe_key) do nothing;
end;
$$;

-- ---------------------------------------------------------------------------
-- Interruptor
-- ---------------------------------------------------------------------------

-- `enabled`: general. Apagado, solo reciben los `allow_users` (cuentas del
-- equipo para probar en producción). `kinds`: apagar un tipo sin tocar el
-- resto. Ver docs/runbooks/push-notifications.md.
insert into public.app_config (key, value)
values (
  'push',
  '{"enabled": false, "allow_users": [], "kinds": {}}'::jsonb
)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
-- RPCs de notify-dispatch (solo service role)
-- ---------------------------------------------------------------------------

-- Toma hasta `p_limit` filas listas para mandar y las marca `sending` con un
-- lease de 2 minutos. Una fila que quedó `sending` (la función murió) vuelve
-- a tomarse cuando vence el lease.
create or replace function public.push_claim_outbox(p_limit int default 200)
returns setof public.notification_outbox
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  update public.notification_outbox o
     set status = 'sending',
         attempts = o.attempts + 1,
         locked_until = now() + interval '2 minutes'
   where o.id in (
     select id from public.notification_outbox
      where not_before <= now()
        and (status = 'pending' or (status = 'sending' and locked_until < now()))
      order by not_before, id
      limit p_limit
      for update skip locked
   )
  returning o.*;
end;
$$;

-- Todo lo que el despacho necesita saber de cada usuario, en una llamada:
-- plan, preferencias (con defaults si no hay fila), dispositivos y cuántas
-- automáticas recibió en las últimas 24 h.
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
        'service', true, 'big_move_sensitivity', 'normal',
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
                       'weekly_report', 'earnings_tomorrow', 'earnings_result'))
  from auth.users u
  where u.id = any (p_user_ids);
$$;

-- Cierra una fila del outbox que NO se manda: `skipped` (con el motivo) o
-- `pending` otra vez con `p_not_before` (diferida por el silencio).
create or replace function public.push_finish_outbox(
  p_id bigint,
  p_status text,
  p_skip_reason text default null,
  p_not_before timestamptz default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_status = 'pending' then
    update public.notification_outbox
       set status = 'pending', locked_until = null, skip_reason = p_skip_reason,
           not_before = coalesce(p_not_before, now() + interval '5 minutes')
     where id = p_id;
  elsif p_status = 'skipped' then
    update public.notification_outbox
       set status = 'skipped', skip_reason = p_skip_reason,
           locked_until = null, processed_at = now()
     where id = p_id;
  else
    raise exception 'invalid_status %', p_status;
  end if;
end;
$$;

-- Envío: `push_begin_log` reserva el id del log ANTES de mandar (va en el
-- payload, para medir la apertura) y `push_complete` lo confirma. Si ningún
-- dispositivo lo recibió, borra el log y la fila vuelve a la cola (hasta 3
-- intentos).
create or replace function public.push_begin_log(p_outbox_id bigint)
returns bigint
language sql
security definer
set search_path = public
as $$
  insert into public.notification_log (user_id, outbox_id, kind)
  select user_id, id, kind from public.notification_outbox where id = p_outbox_id
  returning id;
$$;

create or replace function public.push_complete(
  p_outbox_id bigint,
  p_log_id bigint,
  p_device_count int
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_device_count > 0 then
    update public.notification_log set device_count = p_device_count where id = p_log_id;
    update public.notification_outbox
       set status = 'sent', locked_until = null, processed_at = now()
     where id = p_outbox_id;
  else
    delete from public.notification_log where id = p_log_id;
    update public.notification_outbox
       set status = case when attempts >= 3 then 'failed' else 'pending' end,
           skip_reason = 'delivery_failed',
           locked_until = null,
           not_before = now() + interval '2 minutes',
           processed_at = now()
     where id = p_outbox_id;
  end if;
end;
$$;

-- Limpieza: log de más de 90 días, outbox cerrado de más de 14, y
-- dispositivos que no abren la app hace 60 días.
create or replace function public.push_purge()
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.notification_log where sent_at < now() - interval '90 days';
  delete from public.notification_outbox
   where status in ('sent', 'skipped', 'failed') and created_at < now() - interval '14 days';
  delete from public.push_devices where last_seen_at < now() - interval '60 days';
$$;

revoke all on function public.register_push_device(text, text, text, text, int) from public, anon;
revoke all on function public.unregister_push_device(text) from public, anon;
revoke all on function public.get_notification_preferences() from public, anon;
revoke all on function public.mark_notification_opened(bigint) from public, anon;
revoke all on function public.request_test_notification() from public, anon;
grant execute on function public.request_test_notification() to authenticated;
grant execute on function public.register_push_device(text, text, text, text, int) to authenticated;
grant execute on function public.unregister_push_device(text) to authenticated;
grant execute on function public.get_notification_preferences() to authenticated;
grant execute on function public.mark_notification_opened(bigint) to authenticated;

revoke all on function public.push_claim_outbox(int) from public, anon, authenticated;
revoke all on function public.push_dispatch_context(uuid[]) from public, anon, authenticated;
revoke all on function public.push_finish_outbox(bigint, text, text, timestamptz) from public, anon, authenticated;
revoke all on function public.push_begin_log(bigint) from public, anon, authenticated;
revoke all on function public.push_complete(bigint, bigint, int) from public, anon, authenticated;
revoke all on function public.push_purge() from public, anon, authenticated;
grant execute on function public.push_claim_outbox(int) to service_role;
grant execute on function public.push_dispatch_context(uuid[]) to service_role;
grant execute on function public.push_finish_outbox(bigint, text, text, timestamptz) to service_role;
grant execute on function public.push_begin_log(bigint) to service_role;
grant execute on function public.push_complete(bigint, bigint, int) to service_role;
grant execute on function public.push_purge() to service_role;
