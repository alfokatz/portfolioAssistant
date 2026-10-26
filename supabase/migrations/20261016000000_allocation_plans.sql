-- Plan de cartera: la asignación objetivo del usuario (F3 de
-- docs/superpowers/plans/2026-10-16-porty-siguiente-nivel.md).
--
-- - Una fila por usuario: `targets` es {SÍMBOLO: porcentaje}. Vacío = sin
--   plan. Si tiene objetivos, suman 100 (±0,5).
-- - Solo Premium y Gold guardan un plan (el trigger corta con
--   `allocation_plan_requires_premium`). Si el plan baja, la fila queda
--   pero no se usa (los avisos piden Premium).
-- - `daily-jobs` lee los planes con `allocation_drift_inputs` (lunes 10:00
--   local) y avisa si algo se desvía más que `drift_threshold` puntos.

create table if not exists public.allocation_plans (
  user_id uuid primary key references auth.users (id) on delete cascade,
  targets jsonb not null default '{}'::jsonb,
  -- Puntos porcentuales de desvío que disparan el aviso.
  drift_threshold numeric not null default 5 check (drift_threshold >= 1 and drift_threshold <= 50),
  notify boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.allocation_plans enable row level security;

drop policy if exists "allocation_plans own" on public.allocation_plans;
create policy "allocation_plans own" on public.allocation_plans
  for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

revoke all on public.allocation_plans from public, anon, authenticated;
grant select, insert, update, delete on public.allocation_plans to authenticated;
grant select, insert, update, delete on public.allocation_plans to service_role;

-- ¿[p_user_id] tiene Premium o Gold? Security definer para leer el plan,
-- pero solo para uno mismo: desde la app no sirve para averiguar el plan
-- de otro.
create or replace function public._allocation_plan_allowed(p_user_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null and auth.uid() <> p_user_id then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  return coalesce(public._effective_tier(p_user_id), 'free') in ('premium', 'gold');
end;
$$;

-- Valida los objetivos y el plan del usuario. Sin security definer:
-- `current_user` tiene que ser el rol del pedido.
create or replace function public._allocation_plans_guard()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_key text;
  v_value jsonb;
  v_sum numeric := 0;
  v_count int := 0;
begin
  if jsonb_typeof(new.targets) <> 'object' then
    raise exception 'allocation_invalid_targets' using errcode = '22023';
  end if;
  for v_key, v_value in select * from jsonb_each(new.targets) loop
    if v_key !~ '^[A-Z0-9.\-^=]{1,15}$'
       or jsonb_typeof(v_value) <> 'number'
       or (v_value #>> '{}')::numeric <= 0
       or (v_value #>> '{}')::numeric > 100 then
      raise exception 'allocation_invalid_targets'
        using errcode = '22023', detail = v_key;
    end if;
    v_sum := v_sum + (v_value #>> '{}')::numeric;
    v_count := v_count + 1;
  end loop;
  if v_count > 50 then
    raise exception 'allocation_invalid_targets' using errcode = '22023', detail = 'too_many';
  end if;
  if v_count > 0 and abs(v_sum - 100) > 0.5 then
    raise exception 'allocation_targets_must_sum_100'
      using errcode = '22023', detail = v_sum::text;
  end if;

  if current_user in ('anon', 'authenticated') then
    if not public._allocation_plan_allowed(new.user_id) then
      raise exception 'allocation_plan_requires_premium'
        using errcode = 'P0001', hint = 'El plan de cartera es de Premium.';
    end if;
    if tg_op = 'UPDATE' then
      new.user_id := old.user_id;
      new.created_at := old.created_at;
    end if;
  end if;

  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists allocation_plans_guard on public.allocation_plans;
create trigger allocation_plans_guard
  before insert or update on public.allocation_plans
  for each row execute function public._allocation_plans_guard();

-- Lo que `daily-jobs` necesita para calcular el desvío de cada usuario:
-- objetivos, umbral y sus posiciones abiertas sumadas por ticker, con el
-- último precio del servidor (`market_quotes`) o, si no hay, el de compra
-- promedio. Solo planes con avisos prendidos, objetivos y Premium o Gold.
create or replace function public.allocation_drift_inputs(p_user_ids uuid[])
returns table (
  user_id uuid,
  targets jsonb,
  drift_threshold numeric,
  holdings jsonb
)
language sql
stable
security definer
set search_path = public
as $$
  select
    a.user_id,
    a.targets,
    a.drift_threshold,
    coalesce(
      (select jsonb_agg(jsonb_build_object(
                'symbol', h.symbol,
                'quantity', h.quantity,
                'price', coalesce(q.price, h.avg_price)))
         from (
           select upper(p.ticker) as symbol,
                  sum(p.quantity) as quantity,
                  sum(p.quantity * p.purchase_price) / nullif(sum(p.quantity), 0) as avg_price
             from public.positions p
            where p.user_id = a.user_id
            group by upper(p.ticker)
           having sum(p.quantity) > 0
         ) h
         -- market-watch guarda la cotización con el ticker tal cual.
         left join public.market_quotes q on q.symbol = h.symbol),
      '[]'::jsonb
    )
  from public.allocation_plans a
  where a.user_id = any (p_user_ids)
    and a.notify
    and a.targets <> '{}'::jsonb
    and coalesce(public._effective_tier(a.user_id), 'free') in ('premium', 'gold');
$$;

revoke all on function public._allocation_plans_guard() from public, anon, authenticated;
revoke all on function public._allocation_plan_allowed(uuid) from public, anon;
grant execute on function public._allocation_plan_allowed(uuid) to authenticated, service_role;
revoke all on function public.allocation_drift_inputs(uuid[]) from public, anon, authenticated;
grant execute on function public.allocation_drift_inputs(uuid[]) to service_role;
