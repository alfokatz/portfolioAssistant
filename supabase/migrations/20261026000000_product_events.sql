-- Eventos de producto para medir cuánto tarda un usuario nuevo en llegar al
-- "aha" (docs/superpowers/plans/2026-10-26-aha-moment.md, fase 1).
--
-- La app solo inserta los suyos (RLS); no los lee. Se consultan desde el
-- panel con la vista `product_funnel` (minutos desde el alta hasta cada
-- paso), que no está expuesta a la app.

create table if not exists public.product_events (
  id bigint generated always as identity primary key,
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  name text not null check (name ~ '^[a-z][a-z0-9_]{2,39}$'),
  props jsonb not null default '{}'::jsonb
    check (jsonb_typeof(props) = 'object' and pg_column_size(props) <= 2048),
  created_at timestamptz not null default now()
);

create index if not exists product_events_user_name_idx
  on public.product_events (user_id, name, created_at);
create index if not exists product_events_name_created_idx
  on public.product_events (name, created_at);

alter table public.product_events enable row level security;

drop policy if exists "Users insert own product events" on public.product_events;
create policy "Users insert own product events" on public.product_events
  for insert to authenticated with check (auth.uid() = user_id);

revoke all on public.product_events from anon, authenticated;
grant insert (name, props) on public.product_events to authenticated;

-- Minutos desde el alta hasta la primera vez de cada paso. `null` = todavía
-- no llegó. Time-to-aha = `min_to_diagnosis`.
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
    bool_or(e.name = 'diagnosis_question') as asked_from_diagnosis
  from auth.users u
  left join public.product_events e on e.user_id = u.id
  group by u.id, u.created_at;

revoke all on public.product_funnel from public, anon, authenticated;
