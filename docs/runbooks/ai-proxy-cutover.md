# Runbook — keys fuera de la app (proxy `ai-chat` + `finnhub`)

Estado al 2026-09-30: implementado y probado en local. **Nada desplegado, ninguna key rotada.**

## Arquitectura

| | Cliente (app) | Servidor (Supabase) |
|---|---|---|
| OpenAI | Arma el loop de tool calling (prompt, tools, rondas, reparación) y manda cada ronda a `functions/v1/ai-chat` con el JWT del usuario y `x-porty-turn-id` | `ai-chat`: valida JWT, prompt (hash en `allowed_system_prompts.json`), modelo (`model_prices.allowed`), tamaño del body, rondas por turno, rate limit, cuota mensual y tope diario (`plan_limits`); fuerza `max_completion_tokens`, `n=1`, `store=false`; agrega `OPENAI_API_KEY`; registra tokens y costo en `ai_turn_usage`; cobra 1 consulta por `turn_id` al responder |
| Finnhub | Llama a `functions/v1/finnhub/<endpoint>` con el JWT | `finnhub`: allowlist de endpoints, caché compartida (`finnhub_cache`, mismos TTL que la app), rate limit por usuario, reintentos ante 429/5xx, sirve caché vieja si Finnhub falla; agrega `FINNHUB_API_KEY` |
| Suscripción | Lee su plan (`user_subscriptions`) | `revenuecat-webhook`: ante cualquier evento consulta `GET /v1/subscribers/{id}` y guarda el entitlement activo más alto (incluye promocionales); si RevenueCat no responde, no toca nada y devuelve 503 para que reintente |
| Versión mínima | Al arrancar lee `app_config.min_supported_build`; por debajo muestra "Actualizá la app" (falla abierto sin red) | Fila en `public.app_config` |

La app solo conoce `SUPABASE_URL` y `SUPABASE_ANON_KEY`. `test/security/no_secrets_in_app_test.dart` falla si algo bundleado nombra o contiene un secreto.

### Secrets por función

| Función | Secrets |
|---|---|
| `ai-chat` | `OPENAI_API_KEY` |
| `finnhub` | `FINNHUB_API_KEY` |
| `revenuecat-webhook` | `REVENUECAT_WEBHOOK_SECRET` (el header que configurás en RevenueCat), `REVENUECAT_SECRET_API_KEY` (key secreta v1 del proyecto de RevenueCat) |

`SUPABASE_URL` y `SUPABASE_SERVICE_ROLE_KEY` los inyecta la plataforma.

### Dónde se cambia cada límite

- Consultas por mes / por día por plan: `update public.plan_limits set daily_queries = … where tier = 'gold';` (sin deploy).
- Modelos permitidos y precios: `public.model_prices`.
- Tope de tokens de salida, rondas por turno, tamaño de body, rate limit: `config` en `supabase/functions/ai-chat/handler.ts` (deploy de la función).
- TTL de Finnhub: `endpointTtlSeconds` en `supabase/functions/finnhub/handler.ts`.
- Versión mínima: `public.app_config` (sin deploy).

## Local

```sh
supabase start -x storage-api,imgproxy,studio,logflare,vector,realtime,inbucket,mailpit
supabase db reset
supabase functions serve --env-file supabase/functions/.env.local   # archivo ignorado por git
cd supabase/functions
eval "$(cd ../.. && supabase status -o env | grep -E '^(API_URL|SERVICE_ROLE_KEY|ANON_KEY)=' | sed 's/^/export /')"
deno task test        # 25 tests: proxy, finnhub, webhook
```

### Evals contra el proxy local

1. Pegá la key de OpenAI de **desarrollo** en `supabase/functions/.env.local` (`OPENAI_API_KEY=…`) y reiniciá `supabase functions serve`.
2. Desde `supabase/functions`, con las variables de arriba exportadas:
   ```sh
   export EVAL_PROXY_JWT=$(deno run -A scripts/eval_user.ts)
   export EVAL_ANON_KEY=$ANON_KEY
   cd ../.. && RUN_ASSISTANT_EVALS=1 EVAL_CASE_DELAY_S=2 ASSISTANT_EVALS_REPORT=/tmp/evals-proxy.json \
     flutter test test/evals/assistant_tool_evals_test.dart
   ```
3. Compará la tasa de aprobación con la última corrida directa (tiene que ser la misma: el proxy no cambia el body salvo `max_completion_tokens`, `n`, `store`).
4. `select * from ai_turn_usage order by created_at desc limit 20;` muestra tokens y costo por turno.

### Medir latencia

```sh
# el prompt real (el hash tiene que estar en la allowlist)
flutter test test/security/system_prompt_allowlist_test.dart   # verifica el hash
# volcar el prompt: ver `AssistantOpenAiService.systemPromptFor(AssistantCatalog.build())`
cd supabase/functions && PROMPT_FILE=/ruta/system_prompt.txt N=40 deno run -A scripts/latency_probe.ts
```

Con `OPENAI_API_KEY` inválida OpenAI contesta 401 tras un viaje completo por la red, así que no se gasta nada. El script imprime: directo, por el proxy, la diferencia por pares y el trabajo propio del proxy (hasta justo antes de llamar a OpenAI).

## Pasos de despliegue (en orden)

> Ninguno de estos pasos se ejecutó. Los hacés vos.

1. **Proyecto remoto de desarrollo** (lo creás vos): `supabase link --project-ref <dev>` → `supabase db push` → `supabase secrets set OPENAI_API_KEY=<dev> FINNHUB_API_KEY=<dev> …` → `supabase functions deploy ai-chat finnhub revenuecat-webhook`.
2. **Volver a medir la latencia contra ese proyecto** (el número local no incluye arranque en frío ni la distancia de red a la región): `API_URL=https://<dev>.supabase.co SERVICE_ROLE_KEY=… ANON_KEY=… ALLOW_REMOTE=1` + `scripts/latency_probe.ts`. Hacé una corrida después de 10+ minutos sin tráfico (arranque en frío) y otra en caliente. Si el trabajo propio del proxy supera ~300 ms p50 en caliente, revisar región del proyecto vs usuarios antes de seguir.
3. Evals contra el proyecto de dev (mismos pasos que en local, con `EVAL_PROXY_URL=https://<dev>.supabase.co/functions/v1/ai-chat`).
4. **Producción, servidor**: `supabase db push` (migraciones `20260930120000_ai_proxy.sql` y `20260930130000_app_config.sql`) → secrets → deploy de las tres funciones. Esto no rompe la versión publicada: sigue llamando a OpenAI directo.
   - Las tres funciones quedan con la verificación de JWT del gateway apagada (`supabase/config.toml`): el webhook usa su propio header y `ai-chat`/`finnhub` validan el JWT adentro (401). Verificalo en el dashboard.
   - Desplegá `revenuecat-webhook` recién con `REVENUECAT_SECRET_API_KEY` cargado (sin él responde 503 a todo; RevenueCat reintenta, pero los planes no se sincronizan).
   - En RevenueCat → Webhooks, el header `Authorization` tiene que ser `Bearer <REVENUECAT_WEBHOOK_SECRET>` (la misma comparación que hacía la función anterior, así que si ya estaba configurado no cambia nada). Sin ese secret la función rechaza todo (500) a propósito.
5. **Publicar la app nueva** (esta rama). Cada cambio de prompt o de catálogo cambia el hash: corré `UPDATE_PROMPT_ALLOWLIST=1 flutter test test/security/system_prompt_allowlist_test.dart` y desplegá `ai-chat` **antes** de publicar. Los hashes viejos se dejan mientras haya usuarios en esa versión.
6. **Forzar la actualización** cuando la versión nueva esté aprobada en ambas tiendas:
   ```sql
   update public.app_config
      set value = '{"android": <build nuevo>, "ios": <build nuevo>,
                    "android_store_url": "https://play.google.com/store/apps/details?id=<id>",
                    "ios_store_url": "https://apps.apple.com/app/id<id>"}'::jsonb,
          updated_at = now()
    where key = 'min_supported_build';
   ```
   Solo lo respetan las versiones que ya traen la pantalla (esta en adelante). Ver "Usuarios que no actualizan".
7. **Rotar las keys** (las de la app se consideran comprometidas): crear una key nueva de OpenAI (proyecto separado, límite de gasto) y de Finnhub → `supabase secrets set` → `supabase functions deploy` no hace falta (los secrets se leen en cada invocación, pero redeployar no hace daño) → **revocar las viejas** en OpenAI y Finnhub.
8. **Verificar**:
   - Un turno real desde la app: `select * from ai_turn_usage order by created_at desc limit 5;` (tokens, costo, `charged_at`).
   - Cuota: el contador del header baja 1 por pregunta.
   - OpenAI Usage: el tráfico sale del proyecto/key nueva; la vieja, en cero.
   - Webhook: una compra sandbox deja una fila `synced:<tier>` en `subscription_sync_log`.
   - `revoke execute on function public.consume_ai_quota(int) from authenticated;` una vez que no quede nadie en la versión vieja (hoy la versión vieja la usa para descontarse la cuota).

## Usuarios que no actualizan

- La versión publicada hoy no tiene la pantalla de versión mínima: el paso 6 no la afecta.
- Cuando se revoque la key vieja (paso 7), Porty deja de responder en esas versiones: verán "La API key de OpenAI no es válida…" (mensaje viejo). El resto de la app sigue funcionando; Finnhub (calendario, noticias) queda vacío.
- Recomendación: esperar a que la versión nueva tenga la mayoría de las sesiones (o 1–2 semanas) antes de revocar, salvo evidencia de abuso de la key — en ese caso revocar ya: el costo de dejarla viva es ilimitado.
- Desde esta versión en adelante, subir `min_supported_build` alcanza para forzar la actualización.

## Monitoreo

```sql
-- Costo y consultas por plan y mes (p50/p90/p99 por usuario)
select * from ai_usage_monthly_stats order by month desc, tier;

-- Usuarios que más gastan este mes
select user_id, tier, count(*) turnos, sum(cost_usd) usd
  from ai_turn_usage
 where created_at >= date_trunc('month', now())
 group by 1, 2 order by usd desc limit 20;

-- Rechazos del webhook o RevenueCat caído
select outcome, count(*) from subscription_sync_log
 where created_at > now() - interval '1 day' group by 1;
```

- Caché de Finnhub: los logs de la función `finnhub` tienen una línea `{"fn":"finnhub","path":…,"cache":"hit|miss|stale|error"}` por pedido. Tasa de acierto = hit / (hit + miss). `stale`/`error` sostenidos = Finnhub limitando.
- Alertas sugeridas: gasto diario de OpenAI por encima de lo esperado (límite duro en el proyecto de OpenAI), `revenuecat_unavailable` > 0 por más de 1 h, 5xx de `ai-chat`.

## Vuelta atrás

- La app nueva depende del proxy: si `ai-chat` falla, la solución es arreglarlo o redeployar la versión anterior de la función, no volver a meter la key en la app.
- Aflojar límites sin deploy: `plan_limits` (cuotas) y `model_prices` (modelos).
