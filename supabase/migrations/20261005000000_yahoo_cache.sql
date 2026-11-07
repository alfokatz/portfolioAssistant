-- Caché compartida del proxy de Yahoo Finance (edge function `yahoo`):
-- composición de ETFs y perfil de compañía. Misma forma que finnhub_cache.

create table if not exists public.yahoo_cache (
  cache_key text primary key,
  status int not null,
  body jsonb not null,
  fetched_at timestamptz not null default now()
);

alter table public.yahoo_cache enable row level security;
-- Sin policies: solo la service role.

grant select, insert, update, delete on public.yahoo_cache to service_role;
