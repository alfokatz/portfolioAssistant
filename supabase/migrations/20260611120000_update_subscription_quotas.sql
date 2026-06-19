-- Update monthly AI query quotas: Premium 500, Gold 1000.

create or replace function public._monthly_quota(p_tier text)
returns int
language sql
immutable
as $$
  select case p_tier
    when 'premium' then 500
    when 'gold' then 1000
    else 20
  end;
$$;
