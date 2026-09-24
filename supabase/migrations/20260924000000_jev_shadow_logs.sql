-- Shadow-mode logging for the Jev/TypeSafe widget-routing experiment
-- (Explore mode only; client-side gate is dev-only — see JevShadowConfig
-- in lib/features/assistant/modes/explore/jev_shadow/). Not applied
-- automatically: run this migration yourself (Supabase CLI or SQL editor)
-- before enabling TYPESAFE_API_KEY.
--
-- Client can only INSERT its own rows; there is no SELECT policy for
-- client roles, so shadow logs are only readable from the Supabase
-- dashboard / SQL editor (service role bypasses RLS), never from the app.

create table if not exists public.jev_shadow_logs (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  source text not null default 'live_shadow'
    check (source in ('live_shadow', 'offline_regression')),
  user_id uuid references auth.users (id) on delete set null,
  user_message text not null,
  snapshot jsonb not null,
  current_widget text not null,
  jev_widget text,
  jev_confidence double precision,
  jev_probabilities jsonb,
  match boolean,
  jev_latency_ms int,
  current_pipeline_latency_ms int,
  hypothetical_total_ms int,
  jev_error text
);

create index if not exists jev_shadow_logs_created_at_idx
  on public.jev_shadow_logs (created_at);

alter table public.jev_shadow_logs enable row level security;

drop policy if exists "Users insert own shadow logs" on public.jev_shadow_logs;
create policy "Users insert own shadow logs"
  on public.jev_shadow_logs
  for insert
  to authenticated
  with check (auth.uid() = user_id);
