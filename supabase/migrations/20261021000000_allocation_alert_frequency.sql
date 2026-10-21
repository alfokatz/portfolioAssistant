-- Plan de cartera: cada cuánto avisa si la cartera se alejó del plan.
--
-- - `notify_frequency`: 'weekly' (todos los lunes, como hasta ahora) o
--   'monthly' (el primer lunes del mes). El filtro del mes lo hace
--   `daily-jobs` con la fecha local del usuario.
-- - `allocation_drift_inputs` devuelve la frecuencia: cambia el tipo de
--   retorno, así que se borra y se vuelve a crear (con los mismos permisos).

alter table public.allocation_plans
  add column if not exists notify_frequency text not null default 'weekly';

alter table public.allocation_plans
  drop constraint if exists allocation_plans_notify_frequency_check;
alter table public.allocation_plans
  add constraint allocation_plans_notify_frequency_check
  check (notify_frequency in ('weekly', 'monthly'));

drop function if exists public.allocation_drift_inputs(uuid[]);

create function public.allocation_drift_inputs(p_user_ids uuid[])
returns table (
  user_id uuid,
  targets jsonb,
  drift_threshold numeric,
  notify_frequency text,
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
    a.notify_frequency,
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

revoke all on function public.allocation_drift_inputs(uuid[]) from public, anon, authenticated;
grant execute on function public.allocation_drift_inputs(uuid[]) to service_role;
