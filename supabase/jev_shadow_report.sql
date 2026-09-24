-- Reporte de shadow-mode Jev/TypeSafe vs. pipeline actual (modo Explore).
-- Correr en el SQL editor de Supabase cuando quieras ver el estado del
-- experimento — no es una migración, no hace falta aplicarlo, es de
-- lectura. Requiere que 20260924000000_jev_shadow_logs.sql ya esté
-- aplicada.

-- 1) Tasa de coincidencia + latencias (agregado)
select
  count(*) filter (where jev_widget is not null) as evaluated,
  count(*) filter (where match) as matches,
  round(
    100.0 * count(*) filter (where match)
      / nullif(count(*) filter (where jev_widget is not null), 0),
    1
  ) as match_rate_pct,
  count(*) filter (where jev_error is not null) as jev_failures,
  round(avg(jev_latency_ms)) as avg_jev_latency_ms,
  percentile_cont(0.5) within group (order by jev_latency_ms) as p50_jev_latency_ms,
  percentile_cont(0.95) within group (order by jev_latency_ms) as p95_jev_latency_ms,
  round(avg(current_pipeline_latency_ms)) as avg_current_pipeline_ms,
  round(avg(hypothetical_total_ms)) as avg_hypothetical_total_ms
from public.jev_shadow_logs
where source = 'live_shadow';

-- 2) Pares de confusión entre widgets (qué se confunde con qué, y cuánto)
select current_widget, jev_widget, count(*) as n
from public.jev_shadow_logs
where source = 'live_shadow' and match = false and jev_widget is not null
group by current_widget, jev_widget
order by n desc;

-- 3) Casos divergentes concretos para revisar a mano (¿quién tenía razón?)
select
  created_at,
  user_message,
  current_widget,
  jev_widget,
  jev_confidence,
  jev_latency_ms,
  current_pipeline_latency_ms
from public.jev_shadow_logs
where source = 'live_shadow' and match = false
order by created_at desc
limit 50;

-- 4) ¿Meter a Jev en el camino crítico sería más rápido o más lento?
-- Si avg_hypothetical_total_ms > avg_current_pipeline_ms, partir el
-- pipeline en dos etapas SUMA latencia en vez de restarla (ver el informe
-- de factibilidad: Jev no genera contenido, así que igual hace falta una
-- segunda llamada a GPT después).
select
  round(avg(current_pipeline_latency_ms)) as avg_current_pipeline_ms,
  round(avg(hypothetical_total_ms)) as avg_hypothetical_total_ms,
  round(avg(hypothetical_total_ms) - avg(current_pipeline_latency_ms)) as avg_delta_ms
from public.jev_shadow_logs
where source = 'live_shadow' and jev_widget is not null;
