-- Subscription tiers and AI usage tracking (server-side source of truth).
-- Tier updates: service role / RevenueCat webhook only (not client-writable).

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table if not exists public.user_subscriptions (
  user_id uuid primary key references auth.users (id) on delete cascade,
  tier text not null default 'free'
    check (tier in ('free', 'premium', 'gold')),
  provider text,
  external_subscription_id text,
  status text not null default 'active'
    check (status in ('active', 'canceled', 'expired', 'trialing')),
  current_period_end timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.ai_usage_monthly (
  user_id uuid not null references auth.users (id) on delete cascade,
  month text not null check (month ~ '^\d{4}-\d{2}$'),
  queries_used int not null default 0 check (queries_used >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, month)
);

create index if not exists ai_usage_monthly_user_month_idx
  on public.ai_usage_monthly (user_id, month);

-- ---------------------------------------------------------------------------
-- Backfill existing users
-- ---------------------------------------------------------------------------

insert into public.user_subscriptions (user_id, tier)
select id, 'free'
from auth.users
on conflict (user_id) do nothing;

-- ---------------------------------------------------------------------------
-- Auto-create subscription row on signup
-- ---------------------------------------------------------------------------

create or replace function public.handle_new_user_subscription()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.user_subscriptions (user_id, tier)
  values (new.id, 'free')
  on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_subscription on auth.users;

create trigger on_auth_user_created_subscription
  after insert on auth.users
  for each row
  execute function public.handle_new_user_subscription();

-- ---------------------------------------------------------------------------
-- RLS: users can READ only; no direct writes from client
-- ---------------------------------------------------------------------------

alter table public.user_subscriptions enable row level security;
alter table public.ai_usage_monthly enable row level security;

drop policy if exists "Users read own subscription" on public.user_subscriptions;
create policy "Users read own subscription"
  on public.user_subscriptions
  for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Users read own ai usage" on public.ai_usage_monthly;
create policy "Users read own ai usage"
  on public.ai_usage_monthly
  for select
  to authenticated
  using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create or replace function public._monthly_quota(p_tier text)
returns int
language sql
immutable
as $$
  select case p_tier
    when 'premium' then 800
    when 'gold' then 900
    else 20
  end;
$$;

create or replace function public._current_usage_month()
returns text
language sql
stable
as $$
  select to_char(now() at time zone 'utc', 'YYYY-MM');
$$;

-- ---------------------------------------------------------------------------
-- RPC: read subscription + usage (authenticated)
-- ---------------------------------------------------------------------------

create or replace function public.get_subscription_status()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_tier text;
  v_status text;
  v_month text;
  v_used int;
  v_limit int;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  select tier, status
  into v_tier, v_status
  from public.user_subscriptions
  where user_id = v_user_id;

  if v_tier is null then
    insert into public.user_subscriptions (user_id, tier)
    values (v_user_id, 'free')
    on conflict (user_id) do nothing;
    v_tier := 'free';
    v_status := 'active';
  end if;

  if v_status is distinct from 'active' and v_status is distinct from 'trialing' then
    v_tier := 'free';
  end if;

  v_month := public._current_usage_month();
  v_limit := public._monthly_quota(v_tier);

  insert into public.ai_usage_monthly (user_id, month, queries_used)
  values (v_user_id, v_month, 0)
  on conflict (user_id, month) do nothing;

  select queries_used
  into v_used
  from public.ai_usage_monthly
  where user_id = v_user_id and month = v_month;

  return jsonb_build_object(
    'tier', v_tier,
    'queries_used', coalesce(v_used, 0),
    'queries_limit', v_limit,
    'month', v_month
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- RPC: atomically consume quota (authenticated)
-- ---------------------------------------------------------------------------

create or replace function public.consume_ai_quota(p_weight int)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_tier text;
  v_status text;
  v_month text;
  v_used int;
  v_limit int;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  if p_weight is null or p_weight < 1 then
    raise exception 'invalid_weight';
  end if;

  select tier, status
  into v_tier, v_status
  from public.user_subscriptions
  where user_id = v_user_id;

  if v_tier is null then
    insert into public.user_subscriptions (user_id, tier)
    values (v_user_id, 'free')
    on conflict (user_id) do nothing;
    v_tier := 'free';
    v_status := 'active';
  end if;

  if v_status is distinct from 'active' and v_status is distinct from 'trialing' then
    v_tier := 'free';
  end if;

  v_month := public._current_usage_month();
  v_limit := public._monthly_quota(v_tier);

  insert into public.ai_usage_monthly (user_id, month, queries_used)
  values (v_user_id, v_month, 0)
  on conflict (user_id, month) do nothing;

  select queries_used
  into v_used
  from public.ai_usage_monthly
  where user_id = v_user_id and month = v_month
  for update;

  if coalesce(v_used, 0) + p_weight > v_limit then
    return jsonb_build_object(
      'ok', false,
      'reason', 'quota_exceeded',
      'queries_used', coalesce(v_used, 0),
      'queries_limit', v_limit,
      'tier', v_tier
    );
  end if;

  update public.ai_usage_monthly
  set
    queries_used = coalesce(v_used, 0) + p_weight,
    updated_at = now()
  where user_id = v_user_id and month = v_month;

  return jsonb_build_object(
    'ok', true,
    'queries_used', coalesce(v_used, 0) + p_weight,
    'queries_limit', v_limit,
    'tier', v_tier
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- RPC: update tier from trusted backend (RevenueCat webhook — service role)
-- ---------------------------------------------------------------------------

create or replace function public.upsert_subscription_from_provider(
  p_user_id uuid,
  p_tier text,
  p_provider text,
  p_external_subscription_id text,
  p_status text,
  p_current_period_end timestamptz default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_tier not in ('free', 'premium', 'gold') then
    raise exception 'invalid_tier';
  end if;

  if p_status not in ('active', 'canceled', 'expired', 'trialing') then
    raise exception 'invalid_status';
  end if;

  insert into public.user_subscriptions (
    user_id,
    tier,
    provider,
    external_subscription_id,
    status,
    current_period_end,
    updated_at
  )
  values (
    p_user_id,
    p_tier,
    p_provider,
    p_external_subscription_id,
    p_status,
    p_current_period_end,
    now()
  )
  on conflict (user_id) do update set
    tier = excluded.tier,
    provider = excluded.provider,
    external_subscription_id = excluded.external_subscription_id,
    status = excluded.status,
    current_period_end = excluded.current_period_end,
    updated_at = now();
end;
$$;

revoke all on function public.upsert_subscription_from_provider(
  uuid, text, text, text, text, timestamptz
) from public, anon, authenticated;

grant execute on function public.get_subscription_status() to authenticated;
grant execute on function public.consume_ai_quota(int) to authenticated;
