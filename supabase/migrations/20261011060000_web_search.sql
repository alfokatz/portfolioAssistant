-- Búsqueda web de Porty (edge function `web-search`, tool `search_web`).
-- Para datos que ninguna otra fuente tiene, como el precio de un producto
-- para una meta de compra ("la MacBook Neo rosa"). Cada búsqueda cuesta
-- (modelo de búsqueda de OpenAI), así que:
--   - caché compartida por consulta normalizada (24 h): la misma pregunta
--     de otro usuario no vuelve a buscar;
--   - tope diario por usuario y plan (`plan_limits.web_searches_per_day`).

create table if not exists public.web_search_cache (
  query_key text primary key,
  body jsonb not null,
  fetched_at timestamptz not null default now()
);

alter table public.web_search_cache enable row level security;
-- Sin políticas: solo la service role (la edge function) la lee y escribe.

alter table public.plan_limits
  add column if not exists web_searches_per_day int not null default 0
    check (web_searches_per_day >= 0);

update public.plan_limits set web_searches_per_day = case tier
  when 'free' then 3
  when 'premium' then 10
  when 'gold' then 25
end
where web_searches_per_day = 0;

create table if not exists public.web_search_usage (
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null,
  count int not null default 0,
  primary key (user_id, day)
);

alter table public.web_search_usage enable row level security;

-- Suma una búsqueda del día si queda cupo. `true` = puede buscar.
create or replace function public.web_search_hit(p_user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_limit int;
  v_count int;
begin
  select web_searches_per_day into v_limit from public.plan_limits
    where tier = coalesce(public._effective_tier(p_user_id), 'free');
  insert into public.web_search_usage (user_id, day, count)
  values (p_user_id, current_date, 1)
  on conflict (user_id, day)
    do update set count = public.web_search_usage.count + 1
  returning count into v_count;
  if v_count > coalesce(v_limit, 0) then
    update public.web_search_usage set count = count - 1
      where user_id = p_user_id and day = current_date;
    return false;
  end if;
  return true;
end;
$$;

revoke all on function public.web_search_hit(uuid) from public, anon, authenticated;
