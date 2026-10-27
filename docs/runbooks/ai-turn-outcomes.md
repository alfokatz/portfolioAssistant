# Cómo terminan los turnos de Porty

Cada turno del chat tiene una fila en `ai_turn_usage`, que crea el proxy `ai-chat` al llegar la primera ronda (tokens, costo, si se cobró). Desde la migración `20261027000000_ai_turn_outcome.sql` la app agrega, al terminar el turno, **qué vio el usuario**: el proxy no lo sabe, porque el saneado del A2UI, los chequeos de la respuesta, los reintentos y los timeouts pasan en la app.

No agrega costos: es una RPC de Postgres por turno (`ai_report_turn_outcome`), sin edge functions, sin OpenAI y sin servicios externos.

## Columnas

| Columna | Qué es |
|---|---|
| `outcome` | `answered` (se mostró la respuesta), `fallback` (se mostró "No pude procesar tu consulta" o el texto de respaldo), `paywall` (todo lo pedido estaba fuera del plan), `connection_error` (sin conexión, se mostró el banner). `null`: no hubo reporte (ver abajo). |
| `outcome_reason` | Para `fallback`: `timeout` (el modelo no llegó a tiempo), `unreadable` (respuesta vacía o JSON roto, aun después del reintento), `invalid_json`, `error` (otra excepción). |
| `turn_latency_ms` | Desde que el usuario mandó la pregunta hasta que terminó el turno, en la app (incluye cargar cartera, perfil, memoria, las tools y las rondas). |
| `answer_rejected` | El chequeo de la respuesta (`AssistantAnswerReview`) pidió reescribirla: una ronda extra. |
| `final_retried` | La respuesta final llegó vacía o rota y se volvió a pedir. |

Un turno sin `outcome` puede ser: una versión de la app anterior a este cambio, un rechazo del proxy (cuota, tope diario: se ve en `charged_at` y `round_count`), la app cerrada en medio del turno, o el reporte perdido sin red. **No** cuenta como respuesta fallida.

## Consultas (SQL editor de Supabase)

Tasa de turnos sin respuesta útil por día:

```sql
select date_trunc('day', created_at) as dia,
       count(*) filter (where outcome is not null) as reportados,
       round(100.0 * count(*) filter (where outcome = 'fallback')
             / nullif(count(*) filter (where outcome is not null), 0), 1) as pct_fallback,
       round(100.0 * count(*) filter (where outcome = 'connection_error')
             / nullif(count(*) filter (where outcome is not null), 0), 1) as pct_sin_red
from ai_turn_usage
where purpose = 'chat' and created_at > now() - interval '14 days'
group by 1 order by 1 desc;
```

Por qué fallan:

```sql
select outcome_reason, model, count(*) as turnos,
       round(avg(round_count), 1) as rondas_prom,
       percentile_disc(0.5) within group (order by turn_latency_ms) as p50_ms
from ai_turn_usage
where outcome = 'fallback' and created_at > now() - interval '14 days'
group by 1, 2 order by turnos desc;
```

Latencia y reintentos de los turnos que sí respondieron:

```sql
select model, tier, count(*) as turnos,
       percentile_disc(0.5) within group (order by turn_latency_ms) as p50_ms,
       percentile_disc(0.9) within group (order by turn_latency_ms) as p90_ms,
       round(100.0 * avg((answer_rejected)::int), 1) as pct_reescrita,
       round(100.0 * avg((final_retried)::int), 1) as pct_reintento_final
from ai_turn_usage
where outcome = 'answered' and created_at > now() - interval '14 days'
group by 1, 2 order by turnos desc;
```

Cuánto se gasta en turnos que el usuario no pudo usar:

```sql
select outcome, count(*) as turnos, round(sum(cost_usd), 4) as usd
from ai_turn_usage
where purpose = 'chat' and created_at > now() - interval '30 days'
group by 1 order by usd desc;
```

## Qué hacer con los resultados

- `fallback` / `timeout` alto: mirar `round_count` y `turn_latency_ms` de esos turnos. Muchas rondas → el modelo pide de más o el chequeo lo hace reescribir (`answer_rejected`). Latencia alta con pocas rondas → una tool lenta (búsqueda web, SEC).
- `fallback` / `unreadable` alto: respuestas cortadas por el tope de salida o A2UI roto. Candidato a Structured Outputs.
- Cada caso concreto que se pueda reproducir va como caso del harness (`test/evals/assistant_tool_evals_test.dart`) para que no vuelva.

El contenido de la conversación **no** se guarda acá (solo el resultado). Para leer conversaciones haría falta trazas (p. ej. Langfuse), con enmascarado de datos financieros.
