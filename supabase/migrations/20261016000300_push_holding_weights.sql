-- Cuánto pesa cada acción en la cartera de cada usuario, para el aviso de
-- resultados de mañana (F5 de
-- docs/superpowers/plans/2026-10-16-porty-siguiente-nivel.md). Con el
-- último precio del servidor (`market_quotes`) o, si no hay, el de compra
-- promedio.

create or replace function public.push_holding_weights(p_user_ids uuid[])
returns table (
  user_id uuid,
  symbol text,
  weight_pct numeric
)
language sql
stable
security definer
set search_path = public
as $$
  with h as (
    select p.user_id,
           upper(p.ticker) as symbol,
           sum(p.quantity) as quantity,
           sum(p.quantity * p.purchase_price) / nullif(sum(p.quantity), 0) as avg_price
      from public.positions p
     where p.user_id = any (p_user_ids)
     group by p.user_id, upper(p.ticker)
    having sum(p.quantity) > 0
  ),
  v as (
    select h.user_id, h.symbol, h.quantity * coalesce(q.price, h.avg_price) as value
      from h
      left join public.market_quotes q on q.symbol = h.symbol
  )
  select v.user_id,
         v.symbol,
         round(v.value / nullif(sum(v.value) over (partition by v.user_id), 0) * 100, 1)
    from v;
$$;

revoke all on function public.push_holding_weights(uuid[]) from public, anon, authenticated;
grant execute on function public.push_holding_weights(uuid[]) to service_role;
