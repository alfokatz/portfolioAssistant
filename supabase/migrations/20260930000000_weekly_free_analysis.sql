-- Un análisis Gold de cortesía por semana para Free y Premium.
--
-- El contador vive acá (no en el dispositivo) para que reinstalar la app no
-- lo reinicie. Una fila por usuario y semana; la PK hace atómico el "usar":
-- dos pedidos en paralelo no pueden gastar la cortesía dos veces.
--
-- La semana es lunes a domingo en la zona horaria del USUARIO: la calcula la
-- app (p_week_start = lunes local) y el servidor solo valida que sea un
-- lunes plausible (a lo sumo 8 días atrás o 1 adelante del día UTC), así
-- adelantar el reloj del teléfono no regala semanas.

create table if not exists public.weekly_free_analysis (
  user_id uuid not null references auth.users (id) on delete cascade,
  week_start date not null,
  ticker text,
  used_at timestamptz not null default now(),
  primary key (user_id, week_start)
);

alter table public.weekly_free_analysis enable row level security;

drop policy if exists "Users read own weekly free analysis"
  on public.weekly_free_analysis;
create policy "Users read own weekly free analysis"
  on public.weekly_free_analysis
  for select
  using (auth.uid() = user_id);

-- Sin policies de insert/update: solo se escribe vía la RPC de abajo.

create or replace function public._valid_week_start(p_week_start date)
returns boolean
language sql
stable
as $$
  select p_week_start is not null
    and extract(isodow from p_week_start) = 1
    and p_week_start between (now() at time zone 'utc')::date - 8
                         and (now() at time zone 'utc')::date + 1;
$$;

-- Tier efectivo (un Gold vencido cuenta como Free), mismo criterio que
-- consume_ai_quota.
create or replace function public._effective_tier(p_user_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
    when s.status in ('active', 'trialing') then s.tier
    else 'free'
  end
  from public.user_subscriptions s
  where s.user_id = p_user_id;
$$;

create or replace function public.weekly_free_analysis_status(
  p_week_start date
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_tier text;
  v_used boolean;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  if not public._valid_week_start(p_week_start) then
    raise exception 'invalid_week_start';
  end if;

  v_tier := coalesce(public._effective_tier(v_user_id), 'free');
  select exists (
    select 1 from public.weekly_free_analysis
    where user_id = v_user_id and week_start = p_week_start
  ) into v_used;

  return jsonb_build_object(
    'eligible', v_tier <> 'gold',
    'available', v_tier <> 'gold' and not v_used,
    'week_start', p_week_start
  );
end;
$$;

create or replace function public.consume_weekly_free_analysis(
  p_week_start date,
  p_ticker text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_tier text;
  v_inserted int;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  if not public._valid_week_start(p_week_start) then
    raise exception 'invalid_week_start';
  end if;

  v_tier := coalesce(public._effective_tier(v_user_id), 'free');
  if v_tier = 'gold' then
    return jsonb_build_object('ok', false, 'reason', 'has_gold');
  end if;

  insert into public.weekly_free_analysis (user_id, week_start, ticker)
  values (v_user_id, p_week_start, upper(p_ticker))
  on conflict (user_id, week_start) do nothing;
  get diagnostics v_inserted = row_count;

  return jsonb_build_object(
    'ok', v_inserted = 1,
    'reason', case when v_inserted = 1 then null else 'already_used' end
  );
end;
$$;

revoke all on function public._effective_tier(uuid) from public, anon, authenticated;
grant execute on function public.weekly_free_analysis_status(date) to authenticated;
grant execute on function public.consume_weekly_free_analysis(date, text) to authenticated;
