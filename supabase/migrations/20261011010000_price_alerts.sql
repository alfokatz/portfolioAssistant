-- Alertas de precio y cotizaciones del servidor (F2 del plan
-- docs/superpowers/plans/2026-10-10-notificaciones-push.md).
--
-- - `price_alerts`: las arma el usuario (app o Porty). Las evalúa
--   `market-watch` cada 5 minutos con el mercado abierto.
-- - Tope de alertas activas por plan en `plan_limits.price_alerts`
--   (Free 1, Premium 20, Gold 50). Lo controla un trigger: la app y Porty
--   reciben `alert_limit_reached` y muestran el paywall.
-- - Si el plan baja, las alertas que sobran pasan a `paused` (motivo
--   `plan`); si sube, vuelven solas.
-- - `market_quotes`: última cotización por símbolo (solo service role).

-- ---------------------------------------------------------------------------
-- Tope por plan
-- ---------------------------------------------------------------------------

alter table public.plan_limits
  add column if not exists price_alerts int not null default 0 check (price_alerts >= 0);

update public.plan_limits set price_alerts = case tier
  when 'free' then 1
  when 'premium' then 20
  when 'gold' then 50
end
where price_alerts = 0;

create or replace function public._price_alert_limit(p_user_id uuid)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select price_alerts from public.plan_limits
      where tier = coalesce(public._effective_tier(p_user_id), 'free')),
    0
  );
$$;

-- ---------------------------------------------------------------------------
-- Alertas
-- ---------------------------------------------------------------------------

create table if not exists public.price_alerts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  symbol text not null check (symbol ~ '^[A-Z0-9.\-^=]{1,15}$'),
  -- above/below: `target` es un precio. pct_up/pct_down: `target` es un
  -- porcentaje contra `reference_price` (el precio al crearla).
  condition text not null check (condition in ('above', 'below', 'pct_up', 'pct_down')),
  target numeric not null check (target > 0),
  reference_price numeric check (reference_price is null or reference_price > 0),
  -- once: se cumple y queda cumplida. daily: vuelve a avisar otro día, si
  -- antes el precio volvió al otro lado (histéresis de 1%).
  repeat text not null default 'once' check (repeat in ('once', 'daily')),
  status text not null default 'active' check (status in ('active', 'triggered', 'paused')),
  paused_reason text check (paused_reason in ('user', 'plan')),
  rearm_ready boolean not null default true,
  last_price numeric,
  last_checked_at timestamptz,
  triggered_at timestamptz,
  triggered_price numeric,
  source text not null default 'app' check (source in ('app', 'porty')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (condition in ('above', 'below') or reference_price is not null),
  check (condition in ('above', 'below') or target < 1000)
);

create index if not exists price_alerts_user_idx on public.price_alerts (user_id, created_at desc);
create index if not exists price_alerts_active_symbol_idx
  on public.price_alerts (symbol) where status = 'active';

alter table public.price_alerts enable row level security;

drop policy if exists "price_alerts own" on public.price_alerts;
create policy "price_alerts own" on public.price_alerts
  for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

revoke all on public.price_alerts from public, anon, authenticated;
grant select, insert, update, delete on public.price_alerts to authenticated;
grant select, insert, update, delete on public.price_alerts to service_role;

-- Corta con `alert_limit_reached` si [p_user_id] ya tiene el tope de
-- alertas activas de su plan (sin contar [p_alert_id]). Security definer
-- para leer el plan, pero solo para uno mismo: desde la app no sirve para
-- averiguar el plan de otro.
create or replace function public._price_alert_check_limit(p_user_id uuid, p_alert_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_limit int;
  v_active int;
begin
  if auth.uid() is not null and auth.uid() <> p_user_id then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  v_limit := public._price_alert_limit(p_user_id);
  select count(*) into v_active from public.price_alerts
   where user_id = p_user_id and status = 'active' and id <> p_alert_id;
  if v_active >= v_limit then
    raise exception 'alert_limit_reached'
      using errcode = 'P0001',
            detail = json_build_object('limit', v_limit)::text,
            hint = 'Mejorá tu plan para tener más alertas activas.';
  end if;
end;
$$;

-- Desde la app solo se eligen los datos de la alerta y su estado (activa o
-- pausada); lo que registra el servidor (última lectura, disparo) no se
-- puede escribir. Cambiar la condición o el objetivo la rearma.
-- Sin security definer: `current_user` tiene que ser el rol del pedido.
create or replace function public._price_alerts_guard()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user in ('anon', 'authenticated') then
    if tg_op = 'INSERT' then
      new.status := 'active';
      new.paused_reason := null;
      new.rearm_ready := true;
      new.last_price := null;
      new.last_checked_at := null;
      new.triggered_at := null;
      new.triggered_price := null;
      new.created_at := now();
    else
      new.user_id := old.user_id;
      new.created_at := old.created_at;
      new.last_price := old.last_price;
      new.last_checked_at := old.last_checked_at;
      if new.status = 'triggered' and old.status <> 'triggered' then
        raise exception 'invalid_status' using errcode = '22023';
      end if;
      if new.condition is distinct from old.condition
         or new.target is distinct from old.target
         or new.reference_price is distinct from old.reference_price
         or (new.status = 'active' and old.status <> 'active') then
        -- Rearmar: vuelve a evaluarse desde cero.
        new.status := case when new.status = 'paused' then 'paused' else 'active' end;
        new.rearm_ready := true;
        new.triggered_at := null;
        new.triggered_price := null;
      else
        new.triggered_at := old.triggered_at;
        new.triggered_price := old.triggered_price;
        new.rearm_ready := old.rearm_ready;
      end if;
      new.paused_reason := case
        when new.status <> 'paused' then null
        when old.status = 'paused' then coalesce(old.paused_reason, 'user')
        else 'user'
      end;
    end if;
  end if;

  -- Tope por plan al activar (alta o reactivación).
  if new.status = 'active' and (tg_op = 'INSERT' or old.status <> 'active') then
    perform public._price_alert_check_limit(new.user_id, new.id);
  end if;

  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists price_alerts_guard on public.price_alerts;
create trigger price_alerts_guard
  before insert or update on public.price_alerts
  for each row execute function public._price_alerts_guard();

-- Cambio de plan: pausa las alertas activas que pasan el tope nuevo (quedan
-- las más nuevas) o reactiva las pausadas por plan hasta el tope.
create or replace function public.price_alerts_apply_plan(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_limit int := public._price_alert_limit(p_user_id);
  v_active int;
begin
  update public.price_alerts set status = 'paused', paused_reason = 'plan', updated_at = now()
   where id in (
     select id from public.price_alerts
      where user_id = p_user_id and status = 'active'
      order by created_at desc
      offset v_limit
   );

  select count(*) into v_active from public.price_alerts
   where user_id = p_user_id and status = 'active';

  update public.price_alerts set status = 'active', paused_reason = null,
         rearm_ready = true, updated_at = now()
   where id in (
     select id from public.price_alerts
      where user_id = p_user_id and status = 'paused' and paused_reason = 'plan'
      order by created_at desc
      limit greatest(v_limit - v_active, 0)
   );
end;
$$;

create or replace function public._price_alerts_on_subscription()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT'
     or new.tier is distinct from old.tier
     or new.status is distinct from old.status then
    perform public.price_alerts_apply_plan(new.user_id);
  end if;
  return new;
end;
$$;

drop trigger if exists price_alerts_on_subscription on public.user_subscriptions;
create trigger price_alerts_on_subscription
  after insert or update on public.user_subscriptions
  for each row execute function public._price_alerts_on_subscription();

-- ---------------------------------------------------------------------------
-- Cotizaciones del servidor
-- ---------------------------------------------------------------------------

create table if not exists public.market_quotes (
  symbol text primary key,
  price numeric not null,
  prev_close numeric,
  change_pct numeric,
  currency text,
  -- REGULAR, PRE, POST, CLOSED (Yahoo `marketState`).
  market_state text,
  -- EQUITY, ETF, MUTUALFUND, CRYPTOCURRENCY... (Yahoo `quoteType`).
  quote_type text,
  fetched_at timestamptz not null default now()
);

alter table public.market_quotes enable row level security;
revoke all on public.market_quotes from public, anon, authenticated;
grant select, insert, update, delete on public.market_quotes to service_role;

-- ---------------------------------------------------------------------------
-- RPCs de market-watch (solo service role)
-- ---------------------------------------------------------------------------

-- Registra una corrida sobre las alertas, todo junto: última lectura,
-- rearmado y disparos (que van al outbox en la misma transacción).
-- p_rows: [{id, price, fire, rearm_ready, fired_on}]; `fired_on` es la fecha
-- de mercado (ET) para la clave de duplicados de las diarias.
create or replace function public.price_alerts_record(p_rows jsonb)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  r jsonb;
  v_alert public.price_alerts;
  v_fired int := 0;
begin
  for r in select * from jsonb_array_elements(p_rows) loop
    if coalesce((r ->> 'fire')::boolean, false) then
      update public.price_alerts
         set last_price = (r ->> 'price')::numeric,
             last_checked_at = now(),
             status = case when repeat = 'once' then 'triggered' else status end,
             rearm_ready = false,
             triggered_at = now(),
             triggered_price = (r ->> 'price')::numeric
       where id = (r ->> 'id')::uuid and status = 'active'
      returning * into v_alert;
      if v_alert.id is not null then
        insert into public.notification_outbox (user_id, kind, dedupe_key, data)
        values (
          v_alert.user_id, 'price_alert',
          'price_alert:' || v_alert.id || ':' || coalesce(r ->> 'fired_on', current_date::text),
          jsonb_build_object(
            'alert_id', v_alert.id, 'symbol', v_alert.symbol,
            'condition', v_alert.condition, 'target', v_alert.target,
            'reference_price', v_alert.reference_price,
            'price', (r ->> 'price')::numeric, 'repeat', v_alert.repeat)
        )
        on conflict (user_id, dedupe_key) do nothing;
        v_fired := v_fired + 1;
      end if;
    else
      update public.price_alerts
         set last_price = (r ->> 'price')::numeric,
             last_checked_at = now(),
             rearm_ready = coalesce((r ->> 'rearm_ready')::boolean, rearm_ready)
       where id = (r ->> 'id')::uuid and status = 'active';
    end if;
  end loop;
  return v_fired;
end;
$$;

revoke all on function public._price_alert_limit(uuid) from public, anon, authenticated;
revoke all on function public._price_alert_check_limit(uuid, uuid) from public, anon;
grant execute on function public._price_alert_check_limit(uuid, uuid) to authenticated, service_role;
revoke all on function public.price_alerts_apply_plan(uuid) from public, anon, authenticated;
revoke all on function public.price_alerts_record(jsonb) from public, anon, authenticated;
grant execute on function public.price_alerts_apply_plan(uuid) to service_role;
grant execute on function public.price_alerts_record(jsonb) to service_role;
