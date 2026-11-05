# Backend: Supabase, migraciones y edge functions

## Contenido
- Migraciones
- Edge functions
- Proxies y secretos
- Qué está desplegado (no suponer)

## Migraciones (`supabase/migrations/`)

**Regla de oro: nunca modificar un archivo existente.** `db push` no re-aplica una versión ya aplicada, así que un cambio en un archivo viejo no llega nunca a dev ni a prod. Todo cambio va en una migración nueva (`create or replace`, `on conflict do nothing`, `if not exists`).

- Nombre: `YYYYMMDDHHMMSS_snake_case.sql`. Varias el mismo día: sumar `000100` (ej. `20261016000100_...`, `20261016000200_...`).
- Encabezado: comentario en español que apunta al plan en `docs/superpowers/plans/`.
- Idempotente: `create table if not exists`, `drop policy if exists` antes de `create policy`.
- RLS siempre: `enable row level security` + policy "own" (`auth.uid() = user_id`), después `revoke all` y grants explícitos a `authenticated` y `service_role`.
- Límites por plan: tabla `plan_limits` + triggers que lanzan errores tipados (ej. `watchlist_limit_reached`). Deben reflejar `PlanMatrix` en el cliente.
- Tests SQL: `supabase/tests/<x>_db_test.sql` (transacción con rollback que imprime `<X>_DB_TEST_OK`).
- **No correr `supabase db push`** ni desplegar: lo hace el usuario. Avisar qué migración queda pendiente.

## Edge functions (`supabase/functions/<kebab-name>/`)

- `index.ts` solo conecta `defaultDeps()` → `handle(req, deps)`; su comentario de cabecera dice el comando de deploy y los secretos que necesita.
- La lógica en `handler.ts` (+ `store.ts`, `mapping.ts`, etc.). Lo compartido en `supabase/functions/_shared/`.
- Todas tienen `verify_jwt = false` en `supabase/config.toml` y validan el JWT adentro.
- Inyección de dependencias (`deps`: fetch, env, db) para poder testear con fakes.
- Tests Deno en `supabase/functions/tests/<name>_test.ts` (ver skill **porty-testing**).
- No editar un handler mientras corre `supabase functions serve` con una eval en curso.

## Proxies y secretos

| Servicio | Cómo lo llama la app |
|---|---|
| OpenAI | `ai-chat` vía `AiProxyClient` (`lib/features/genui_core/tool_calling/ai_proxy_client.dart`) |
| Finnhub | `finnhub` vía `FinnhubHttpClient` |
| Yahoo | `yahoo` vía `YahooProxyClient` |
| Otras (binance-sync, etoro-sync…) | `PortyEdgeClient` |

- El proxy `ai-chat` solo acepta system prompts cuyo SHA-256 esté en `supabase/functions/ai-chat/allowed_system_prompts.json` (informe semanal: `allowed_report_prompts.json`). Cambiar prompt o catálogo → regenerar el hash (skill **porty-assistant**) y avisar que hay que desplegar `ai-chat` antes de publicar la app.
- Nunca poner en `lib/` ni en assets: `OPENAI_API_KEY`, `FINNHUB_API_KEY`, `sk-...`, `SERVICE_ROLE_KEY`, `api.openai.com`, `finnhub.io`.

## Qué está desplegado

No suponer. Para saber si algo existe en dev: `app_config` es de lectura pública y las RPC sin sesión devuelven `permission denied` si existen. Preguntar al usuario antes de cualquier deploy, rotación de keys o `db push`.
