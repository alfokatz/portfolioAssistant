-- Productores de notificaciones que no son del mercado (F3 y F6 del plan
-- docs/superpowers/plans/2026-10-10-notificaciones-push.md).
--
-- - eToro desconectado: un trigger en `etoro_connections`. La sincronización
--   corre al abrir la app, así que en ese momento el usuario ya lo ve
--   adentro: el aviso sale 6 horas después, solo si sigue sin reconectar.
-- - `daily-jobs` (cada hora): el informe del sábado a las 9 y los earnings
--   (Gold) en la hora local de cada uno. Lee los usuarios con
--   `push_users_at_local_hour` y encola con `push_enqueue`.

-- ---------------------------------------------------------------------------
-- eToro
-- ---------------------------------------------------------------------------

create or replace function public._push_on_etoro_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'reconnect_required' and old.status is distinct from 'reconnect_required' then
    insert into public.notification_outbox (user_id, kind, dedupe_key, not_before)
    values (
      new.user_id, 'etoro_reconnect',
      'etoro_reconnect:' || (now() at time zone 'utc')::date,
      now() + interval '6 hours'
    )
    on conflict (user_id, dedupe_key) do nothing;
  elsif new.status <> 'reconnect_required' and old.status = 'reconnect_required' then
    -- Reconectó (o desconectó): el aviso pendiente ya no corresponde.
    update public.notification_outbox
       set status = 'skipped', skip_reason = 'resolved', processed_at = now()
     where user_id = new.user_id and kind = 'etoro_reconnect' and status = 'pending';
  end if;
  return new;
end;
$$;

drop trigger if exists push_on_etoro_status on public.etoro_connections;
create trigger push_on_etoro_status
  after update of status on public.etoro_connections
  for each row execute function public._push_on_etoro_status();

-- ---------------------------------------------------------------------------
-- daily-jobs
-- ---------------------------------------------------------------------------

-- Usuarios para los que ahora son las [p_hour] (hora local del dispositivo
-- que abrió la app más recientemente), con su plan y sus tickers abiertos.
create or replace function public.push_users_at_local_hour(p_hour int)
returns table (
  user_id uuid,
  timezone text,
  local_date date,
  local_dow int,
  tier text,
  symbols text[]
)
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
  select
    l.user_id,
    l.timezone,
    (now() at time zone l.timezone)::date,
    extract(dow from now() at time zone l.timezone)::int,
    coalesce(public._effective_tier(l.user_id), 'free'),
    coalesce(
      (select array_agg(distinct upper(p.ticker) order by upper(p.ticker))
         from public.positions p where p.user_id = l.user_id and p.quantity > 0),
      '{}'
    )
  from latest l
  where extract(hour from now() at time zone l.timezone)::int = p_hour;
$$;

-- Encola filas en el outbox (las repetidas no hacen nada). p_rows:
-- [{user_id, kind, dedupe_key, data}]. Devuelve cuántas entraron.
create or replace function public.push_enqueue(p_rows jsonb)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int;
begin
  with ins as (
    insert into public.notification_outbox (user_id, kind, dedupe_key, data)
    select (r ->> 'user_id')::uuid, r ->> 'kind', r ->> 'dedupe_key', coalesce(r -> 'data', '{}'::jsonb)
      from jsonb_array_elements(p_rows) r
    on conflict (user_id, dedupe_key) do nothing
    returning 1
  )
  select count(*) into v_count from ins;
  return v_count;
end;
$$;

revoke all on function public._push_on_etoro_status() from public, anon, authenticated;
revoke all on function public.push_users_at_local_hour(int) from public, anon, authenticated;
revoke all on function public.push_enqueue(jsonb) from public, anon, authenticated;
grant execute on function public.push_users_at_local_hour(int) to service_role;
grant execute on function public.push_enqueue(jsonb) to service_role;
