# Migración a GPT-6 Luna

OpenAI apaga gpt-4o, gpt-4o-mini, gpt-4.1 y gpt-4.1-mini el **2027-01-14**. El reemplazo que recomienda es `gpt-6-luna` ([deprecations](https://developers.openai.com/api/docs/deprecations), [guía](https://help.openai.com/en/articles/20001600-migrating-from-gpt-4x-to-gpt-6-luna)).

## Qué cambió

| Pieza | Antes | Ahora |
|---|---|---|
| Chat de Porty e informe semanal (app) | `gpt-4.1-mini` | `gpt-6-luna` (`defaultModel` y `OPENAI_MODEL` en `assets/env/.env.*`) |
| Proxy `ai-chat` | aceptaba solo `gpt-4.1-mini` | reescribe `gpt-4.1-mini` → `gpt-6-luna` (versiones viejas de la app); en GPT-6 fija `reasoning_effort: "none"`, `service_tier: "fast"` y un punto de caché explícito al final del system prompt; paso gradual con `GPT6_ROLLOUT_PERCENT` |
| `web-search` | Chat Completions + `gpt-4o-mini-search-preview` (**apagado el 2026-07-23**, la función fallaba) | Responses API + tool `web_search` + `gpt-6-luna`, `reasoning.effort: low` |
| `news-context` | `gpt-5-mini` (no se retira) | sin cambios; precio de `gpt-6-luna` cargado por si se setea `NEWS_CONTEXT_MODEL` |
| Precios | — | `20261014120000_gpt6_luna.sql` (estándar) y `20261014130000_gpt6_luna_fast_prices.sql` (fast: 0,20 / 0,02 cacheado / 1,00 por 1M tokens) |

**Por qué `reasoning_effort: "none"`:** el default de Luna es `medium`, y en Chat Completions Luna acepta tools **solo** con `none` ([guía de GPT-6](https://developers.openai.com/api/docs/guides/latest-model)). Además es lo que la guía de migración sugiere como punto de partida desde GPT-4.x. Con `none` siguen funcionando `temperature`, `tool_choice` (`auto`, `none`, `allowed_tools`), `parallel_tool_calls` y `response_format: json_schema` (verificado el 2026-10-14 contra la API).

**Por qué `service_tier: "fast"`:** Luna estándar genera ~60 tokens/s; en fast, ~125 (gpt-4.1-mini: ~106), medido el 2026-10-14. Cuesta el doble que Luna estándar y sigue más barato que gpt-4.1-mini (0,20/1,00 contra 0,40/1,60).

**Por qué el punto de caché explícito:** GPT-6 no cachea cualquier prefijo como gpt-4.1: escribe la caché en puntos fijos ([prompt caching](https://developers.openai.com/api/docs/guides/prompt-caching)). El implícito del primer bloque de sistema cae después de `PORTFOLIO_BRIEF`, que cambia en cada turno, así que el prompt fijo (~13K tokens) no se reusaba nunca entre turnos (medido: 0 tokens cacheados). Con `prompt_cache_breakpoint: {mode: "explicit"}` en la parte de texto del system prompt pasa a ~99 %. El proxy lo agrega; el hash de la allowlist no cambia.

## Despliegue (en orden)

1. `supabase db push`: aplica `20261014120000_gpt6_luna.sql`. **Tiene que ir antes que el paso 2**: sin la fila de precios, el proxy rechaza el modelo (`model_not_allowed`).
2. Paso gradual, como pide la guía de OpenAI: `supabase secrets set GPT6_ROLLOUT_PERCENT=10` **antes** del deploy. Sin el secret, el default es 100: todos a Luna de una vez.
3. `supabase functions deploy ai-chat web-search news-context`. El porcentaje elegido de usuarios, con app vieja o nueva, pasa a `gpt-6-luna`; el resto sigue en `gpt-4.1-mini`.
4. Mirar unos días `ai_turn_usage` por modelo: costo, rondas, `cached_tokens`, errores en los logs de `ai-chat`. Después subir: `supabase secrets set GPT6_ROLLOUT_PERCENT=50`, luego `100`. Verificar en los logs que tome el valor nuevo; si no, redesplegar `ai-chat`. Desde el 2027-01-14 el proxy usa 100 sí o sí.
5. Publicar la app con el `OPENAI_MODEL` nuevo. No es obligatorio para el 14/1, porque el proxy reescribe el modelo, pero deja el pedido explícito.
6. Si se setea `WEB_SEARCH_MODEL` en los secrets, tiene que ser un modelo de la Responses API con `web_search`.

**Rollback:** `supabase secrets set GPT6_ROLLOUT_PERCENT=0`. Todos vuelven a `gpt-4.1-mini` (si no toma el valor, redesplegar `ai-chat`). Solo sirve hasta el 2027-01-14.

## Pendiente

- La escritura de caché de Luna cuesta 0,125/M y `model_prices` no tiene columna para eso: el costo registrado la estima al precio de input, así que queda apenas por debajo del real.
