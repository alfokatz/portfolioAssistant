-- Eventos de RevenueCat, uno por fila, para saber cuánto se cobra y qué
-- paywall vende (docs/superpowers/specs/2026-11-02-paywall-medible-y-anual.md §3.8).
--
-- La escribe solo el webhook `revenuecat-webhook` (service role). La app no
-- lee ni escribe: RLS activado y sin políticas. Idempotente por `event_id`
-- (RevenueCat reintenta y el webhook usa `on conflict do nothing`).
--
-- No se guarda el evento crudo: `subscriber_attributes` puede traer `$email`
-- y otros datos personales. Sin `check` sobre valores de RevenueCat: un tipo
-- o tienda nuevos no pueden romper el webhook.
--
-- `user_id on delete cascade` en este release (docs/product/decisions.md,
-- 2026-11-02): al borrar la cuenta se borran sus eventos. Pasar a `set null`
-- es una migración nueva (drop/add del constraint) cuando estén las
-- condiciones de compliance. user_id null = id anónimo de RevenueCat o evento
-- de una cuenta que ya no existía al llegar (el webhook lo guarda sin usuario).

create table if not exists public.subscription_events (
  id bigint generated always as identity primary key,
  event_id text not null,
  user_id uuid references auth.users (id) on delete cascade,
  event_type text not null,
  product_id text,
  new_product_id text,
  store text,
  period_type text,
  is_trial boolean not null default false,
  environment text,
  is_sandbox boolean generated always as (environment is distinct from 'PRODUCTION') stored,
  price_usd numeric(12,4),
  price_local numeric(14,4),
  currency text,
  takehome_pct numeric(5,4),
  paywall_source text,
  reason text,
  event_at timestamptz,
  purchased_at timestamptz,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  constraint subscription_events_event_id_key unique (event_id)
);

comment on table public.subscription_events is
  'Eventos de RevenueCat (sin datos personales). Solo service role.';

create index if not exists subscription_events_user_idx
  on public.subscription_events (user_id, event_at);
create index if not exists subscription_events_type_idx
  on public.subscription_events (event_type, event_at);

alter table public.subscription_events enable row level security;

-- Sin políticas: la app no lee ni escribe. Solo la service role (webhook).
revoke all on public.subscription_events from public, anon, authenticated;
grant select, insert on public.subscription_events to service_role;

-- ---------------------------------------------------------------------------
-- product_funnel: misma definición que 20261026000000_product_events.sql, con
-- las columnas en el mismo orden (create or replace view solo deja agregar al
-- final) y dos nuevas:
--   min_to_first_paywall: minutos hasta el primer `paywall_viewed`;
--   min_to_purchase: minutos hasta la primera compra real (INITIAL_PURCHASE
--   fuera de sandbox), según RevenueCat.
-- ---------------------------------------------------------------------------

create or replace view public.product_funnel as
  select
    u.id as user_id,
    u.created_at as signed_up_at,
    (select e.props->>'method'
       from public.product_events e
      where e.user_id = u.id and e.name = 'portfolio_loaded'
      order by e.created_at limit 1) as load_method,
    round(extract(epoch from (min(e.created_at) filter (where e.name = 'onboarding_finished') - u.created_at)) / 60.0, 1)
      as min_to_onboarding_done,
    round(extract(epoch from (min(e.created_at) filter (where e.name = 'portfolio_loaded') - u.created_at)) / 60.0, 1)
      as min_to_portfolio,
    round(extract(epoch from (min(e.created_at) filter (where e.name = 'diagnosis_seen') - u.created_at)) / 60.0, 1)
      as min_to_diagnosis,
    round(extract(epoch from (min(e.created_at) filter (where e.name = 'first_chat_answer') - u.created_at)) / 60.0, 1)
      as min_to_first_answer,
    bool_or(e.name = 'diagnosis_question') as asked_from_diagnosis,
    round(extract(epoch from (min(e.created_at) filter (where e.name = 'paywall_viewed') - u.created_at)) / 60.0, 1)
      as min_to_first_paywall,
    round(extract(epoch from (
      (select min(s.event_at)
         from public.subscription_events s
        where s.user_id = u.id
          and s.event_type = 'INITIAL_PURCHASE'
          and not s.is_sandbox)
      - u.created_at)) / 60.0, 1)
      as min_to_purchase
  from auth.users u
  left join public.product_events e on e.user_id = u.id
  group by u.id, u.created_at;

revoke all on public.product_funnel from public, anon, authenticated;
