-- Premium: "por qué se movió lo tuyo" (spec 2026-11-05-diferenciacion-planes-v2 §3.4).
-- Premium recibe titulares y contexto con citas SOLO de tickers que tiene en
-- cartera y solo con el camino v2 (Google News RSS no admite uso comercial).
-- `sec` sigue siendo de Gold (`gold_data_allowed`).
--
-- p_ticker se compara en mayúsculas contra `positions.ticker` tal como viene
-- en el pedido (sufijos .BA, cripto -USD): sin normalizar.

create or replace function public.news_data_allowed(p_user_id uuid, p_ticker text default null)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.gold_data_allowed(p_user_id, p_ticker)
    or (
      p_ticker is not null
      and coalesce(public._effective_tier(p_user_id), 'free') = 'premium'
      and public._news_provider() = 'v2'
      and exists (
        select 1 from public.positions
         where user_id = p_user_id
           and upper(ticker) = upper(p_ticker)
           and quantity > 0
      )
    );
$$;

revoke all on function public.news_data_allowed(uuid, text) from public, anon, authenticated;
grant execute on function public.news_data_allowed(uuid, text) to service_role;

-- Premium ahora gasta hasta 5 búsquedas por pregunta: de 5 a 10 pedidos al día.
update public.plan_limits set news_context_per_day = 10
 where tier = 'premium' and news_context_per_day = 5;
