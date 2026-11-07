-- Investor profile (risk tolerance, horizon, objective), one row per user.
-- Read by the assistant's Invest and Plan engines; edited from
-- Settings → "Perfil de inversor". Lives server-side like user_subscriptions
-- so it survives reinstalls and is shared across devices.

create table if not exists public.investor_profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  risk_tolerance text not null
    check (risk_tolerance in ('conservative', 'moderate', 'aggressive')),
  horizon text not null
    check (horizon in ('short', 'medium', 'long')),
  objective text not null
    check (objective in ('growth', 'income', 'preservation', 'specific_goal')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- updated_at is server-owned: the client never sends it, so the 12-month
-- staleness check can't be skewed by a device clock.
create or replace function public.touch_investor_profile_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists investor_profiles_touch_updated_at
  on public.investor_profiles;

create trigger investor_profiles_touch_updated_at
  before insert or update on public.investor_profiles
  for each row
  execute function public.touch_investor_profile_updated_at();

-- ---------------------------------------------------------------------------
-- RLS: each user reads and writes only their own profile
-- ---------------------------------------------------------------------------

alter table public.investor_profiles enable row level security;

drop policy if exists "Users read own investor profile"
  on public.investor_profiles;
create policy "Users read own investor profile"
  on public.investor_profiles
  for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Users insert own investor profile"
  on public.investor_profiles;
create policy "Users insert own investor profile"
  on public.investor_profiles
  for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "Users update own investor profile"
  on public.investor_profiles;
create policy "Users update own investor profile"
  on public.investor_profiles
  for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
