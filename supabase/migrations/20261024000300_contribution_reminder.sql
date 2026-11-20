-- Recordatorio de aporte mensual (fase 6 de
-- docs/superpowers/plans/2026-10-24-porty-en-toda-la-app.md): el usuario
-- elige un día del mes (1-28) y, si quiere, cuánto aporta. Ese día, a las 9
-- locales, `daily-jobs` manda `contribution_reminder` con cómo repartirlo
-- para acercarse a su plan (solo compras, como la pantalla del plan).
-- Lo pidió el usuario: no cuenta para el tope diario de automáticas.

alter table public.allocation_plans
  add column if not exists contribution_day smallint
    check (contribution_day is null or contribution_day between 1 and 28),
  add column if not exists contribution_amount numeric
    check (contribution_amount is null
           or (contribution_amount > 0 and contribution_amount <= 10000000));

alter table public.notification_outbox
  drop constraint if exists notification_outbox_kind_check;
alter table public.notification_outbox
  add constraint notification_outbox_kind_check check (kind in (
    'test', 'price_alert', 'big_move', 'big_move_digest', 'portfolio_move',
    'weekly_report', 'etoro_reconnect', 'earnings_tomorrow', 'earnings_result',
    'allocation_drift', 'watchlist_move', 'morning_brief',
    'contribution_reminder'
  ));

-- Los planes con recordatorio de [p_user_ids] (Premium/Gold), con lo que
-- tiene valuado como `allocation_drift_inputs`. El día lo filtra
-- `daily-jobs` con la fecha local de cada usuario.
create or replace function public.contribution_reminder_inputs(p_user_ids uuid[])
returns table (
  user_id uuid,
  targets jsonb,
  contribution_day smallint,
  contribution_amount numeric,
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
    a.contribution_day,
    a.contribution_amount,
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
    and a.contribution_day is not null
    and a.targets <> '{}'::jsonb
    and coalesce(public._effective_tier(a.user_id), 'free') in ('premium', 'gold');
$$;

revoke all on function public.contribution_reminder_inputs(uuid[]) from public, anon, authenticated;
grant execute on function public.contribution_reminder_inputs(uuid[]) to service_role;
