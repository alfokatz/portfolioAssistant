# Spec: borrado de cuenta en la app

**Fecha:** 2026-11-02 · **Autor:** porty-architect · **Brief:** `docs/product/briefs/2026-11-02-borrado-de-cuenta.md` · **Legal:** `docs/legal/reviews/2026-11-02-paywall-y-nudges.md` (H1, §3, §6) · **Decisión:** `docs/product/decisions.md` (`subscription_events` con `on delete cascade` en este release)

## 1. Objetivo

Desde Ajustes, el usuario borra su cuenta sin salir de la app: ve qué se borra, y si tiene una suscripción activa ve también el aviso de que tiene que cancelarla en la tienda, con el link. Confirma, y una edge function desconecta los brókers, borra su cliente en RevenueCat y borra `auth.users`. El resto de sus datos se va por `cascade` o por un trigger. Después queda afuera de la app; si vuelve con el mismo mail, empieza de cero.

**Listo** = los criterios de la §5 en verde, incluido el test SQL que comprueba que, después del borrado, no queda ninguna fila del usuario en ninguna tabla de `public` ni ningún secreto suyo en Vault.

## 2. Fuera de alcance

- Exportar datos, período de gracia, recuperar la cuenta, encuesta de salida (brief §4).
- Cancelar la suscripción desde la app: es de la tienda.
- La página web de borrado que pide Google Play: la arma el usuario o porty-marketing-lead en la landing. Esta spec no la construye.
- Revocar el token de Sign in with Apple por API (`/auth/revoke`): en el release 1 va el mínimo de TN3194, un toast que guía la revocación manual (ver §6, R3).
- Borrar de los backups de Supabase: va en la política de privacidad (compliance §6.6).
- El asistente: `porty-assistant-dev` **no tiene tareas**. Memorias, temas y uso de IA se van por cascade.

## 3. Contrato de datos

### 3.1 Inventario de tablas con datos del usuario (leído de `supabase/migrations/`, 48 `create table`)

**A. Se borran por `on delete cascade` desde `auth.users`.** La FK está en las migraciones, así que no hace falta código:

| Tabla | Nota |
|---|---|
| `user_subscriptions`, `ai_usage_monthly`, `ai_turn_usage`, `api_rate_limits` | |
| `investor_profiles` (incluye `notes`), `weekly_free_analysis`, `weekly_reports` | |
| `positions`, `closed_positions` | **Ver R1:** en el remoto se crearon antes de la CLI y su FK es desconocida. La migración nueva la asegura. |
| `etoro_connections`, `etoro_oauth_states` | |
| `etoro_tokens`, `binance_keys`, `snaptrade_users` | La fila cae por cascade, pero **el secreto de Vault no**. Lo borra el trigger (B). |
| `binance_connections`, `snaptrade_connections` | |
| `push_devices`, `notification_preferences`, `notification_outbox`, `notification_log` | |
| `price_alerts`, `watchlist_items`, `allocation_plans` | |
| `user_goals`, `goal_contributions` (doble FK: usuario y meta) | |
| `user_memories`, `porty_topics`, `web_search_usage`, `news_context_usage` | |
| `product_events` | |
| `subscription_events` | `cascade` en este release (decisión). Pasa a `set null` cuando se cumplan las 3 condiciones de compliance §3. |

**B. Borrado explícito.** Lo hace el trigger `before delete on auth.users` de la migración nueva:

| Dato | Por qué no alcanza el cascade | Qué se borra |
|---|---|---|
| `vault.secrets` de Binance, eToro y SnapTrade | Las tablas puntero tienen FK, pero `vault.secrets` no | Los ids apuntados por `binance_keys`/`etoro_tokens`/`snaptrade_users` del usuario **y** los nombres `binance_keys_<uid>`, `etoro_tokens_<uid>`, `snaptrade_user_<uid>` (huérfanos de fallas viejas) |
| `subscription_sync_log` | `user_id` es `text` y no tiene FK | `where user_id = old.id::text` |
| `app_config.value->'users'` y `->'allow_users'` | Flags de rollout con uuids, legibles por anon | Saca `old.id::text` de esos arrays, en todas las claves |
| `waitlist` | El email de la landing, sin FK | `where email = lower(old.email)`, **solo si** `old.email_confirmed_at is not null` o el proveedor es OAuth (ver R5) |

**C. No se tocan: no tienen datos del usuario o no se pueden vincular a la cuenta.** `landing_events` (anon_id del navegador), `landing_rate_limits` (hash, transitorio). Caches y catálogos globales: `finnhub_cache`, `yahoo_cache`, `data_source_cache`, `web_search_cache` (por consulta, no por usuario), `investor_pulse_cache`, `market_quotes`, `sec_ticker_cik`, `etoro_instruments`, `super_investors`, `news_source_allowlist`, `upstream_rate_gate`, `plan_limits`, `model_prices` y el resto de `app_config`.

**D. Nuevo, no es dato personal:** `account_deletions_daily`, el contador del brief §3.

**En el dispositivo:** las claves de SharedPreferences que contienen el uid (caché de Home, informe semanal, diagnóstico). Las borra flutter (§4.2).

**Externo:** el usuario de SnapTrade (`DELETE /snapTrade/deleteUser`), los tokens de eToro (revocación RFC 7009, *best effort* como en `etoro-sync /disconnect`) y el cliente de RevenueCat (`DELETE /v1/subscribers/{uid}`). Las claves de Binance no tienen API de revocación: borramos nuestra copia y la clave sigue existiendo en la cuenta de Binance del usuario. Es de solo lectura.

### 3.2 Migración nueva `supabase/migrations/20261102130000_account_deletion.sql`

Idempotente (`if not exists`, `create or replace`, `drop trigger if exists`). Tiene un timestamp posterior a `20261102120200`.

```sql
-- 1. Contador agregado, sin user_id. Solo service role (RLS sin policies).
create table if not exists public.account_deletions_daily (
  day date not null,
  tier text not null check (tier in ('free','premium','gold')),
  deletions int not null default 0,
  primary key (day, tier)
);
-- revoke all from anon, authenticated; grant all to service_role.

-- 2. Trigger: limpieza de lo que el cascade no alcanza + contador.
create or replace function public._account_purge_before_delete()
returns trigger language plpgsql security definer set search_path = public as $$ ... $$;
--   a) delete from vault.secrets where id in (select vault_secret_id from binance_keys|etoro_tokens|snaptrade_users where user_id = old.id)
--      or name in ('binance_keys_'||old.id, 'etoro_tokens_'||old.id, 'snaptrade_user_'||old.id);
--   b) delete from subscription_sync_log where user_id = old.id::text;
--   c) update app_config: quitar old.id::text de value->'users' y value->'allow_users' donde esté (operador ?);
--   d) delete from waitlist where old.email is not null and email = lower(old.email)
--        and (old.email_confirmed_at is not null
--             or coalesce(old.raw_app_meta_data->>'provider', 'email') <> 'email');
--   e) upsert account_deletions_daily ((now() at time zone 'utc')::date,
--        coalesce((select tier from user_subscriptions where user_id = old.id), 'free')) deletions + 1;
--   return old;
drop trigger if exists account_purge_before_delete on auth.users;
create trigger account_purge_before_delete before delete on auth.users
  for each row execute function public._account_purge_before_delete();
-- revoke execute on the function from public, anon, authenticated.

-- 3. Asegurar cascade en positions / closed_positions (remoto pre-CLI, R1).
--    DO block por tabla: si hay una FK user_id → auth.users con confdeltype <> 'c', se borra;
--    si no queda ninguna con 'c', se agrega `<tabla>_user_id_cascade_fkey ... on delete cascade not valid`
--    (`not valid` para no fallar si hay huérfanos viejos; el cascade igual aplica).
```

Por qué un trigger y no un paso de la edge function: es atómico con el borrado de `auth.users`. Si una sincronización en curso guarda un secreto nuevo, su insert en la tabla puntero queda bloqueado por el lock de la fila del usuario y después falla por FK, así que la transacción se deshace junto con el secreto. Además cubre los borrados hechos a mano desde el dashboard (soporte). Mismo patrón que `on_auth_user_created_subscription`.

### 3.3 Edge function `delete-account`

`POST {SUPABASE_URL}/functions/v1/delete-account`. En `config.toml` va con `verify_jwt = false`: valida el JWT ella misma con `deps.authenticate`, igual que `snaptrade-sync`.

**Request**
```http
Authorization: Bearer <JWT del usuario>
apikey: <anon key>
Content-Type: application/json

{ "confirm": true }
```
`confirm` es obligatorio y tiene que ser exactamente `true`. Es una traba contra llamadas por error.

**Pasos, en este orden.** Un paso que ya está hecho es un no-op, y eso hace a la función idempotente:

| # | Paso | Falla → |
|---|---|---|
| 0 | `authenticate` → uid. `rate_limit_hit(uid, 'delete_account', 5)`. Chequeo de entorno: falta `REVENUECAT_SECRET_API_KEY`, o el usuario tiene `snaptrade_users` y falta `SNAPTRADE_CLIENT_ID`/`SNAPTRADE_CONSUMER_KEY` → **corta antes de tocar nada** | 401 / 429 / 500 `misconfigured` |
| 1 | **SnapTrade:** `snaptrade_secret_read(uid)`. Si existe, `SnaptradeClient.deleteUser(snaptradeUserId)` (404 = ok) y enseguida `snaptrade_disconnect(uid, true)` | 502 `upstream_unavailable`, `step: "snaptrade"` |
| 2 | **RevenueCat:** `DELETE {apiBase}/subscribers/{uid}` con `Bearer REVENUECAT_SECRET_API_KEY`. 200 o 404 = ok. 5xx, 429 o red → reintenta con `config.retryDelaysMs` del webhook; si sigue fallando, error. Otro 4xx → error | 502 `upstream_unavailable`, `step: "revenuecat"` |
| 3 | **eToro:** `etoro_tokens_read(uid)`. Si hay tokens y está `ETORO_CLIENT_ID`/`ETORO_CLIENT_SECRET`, `revoke(refresh)` + `revoke(access)` (*best effort*, nunca corta). Después `etoro_disconnect(uid, true)` | 500 `delete_failed`, `step: "etoro"` (solo error de DB) |
| 4 | **Binance:** `binance_disconnect(uid, true)` (borra la clave de Vault) | 500 `delete_failed`, `step: "binance"` |
| 5 | **Auth:** `db.auth.admin.deleteUser(uid)` (borrado duro). Si el usuario no existe, cuenta como ok. Dispara el trigger y los cascades | 500 `delete_failed`, `step: "auth"` |

Los `*_disconnect` van con `keep_as_manual = true`. Si un paso posterior falla, la cartera del usuario sigue entera, como manual. Al final el cascade la borra igual.

Los clientes `SnaptradeClient` y `EtoroClient` se importan de `../snaptrade-sync/snaptrade.ts` y `../etoro-sync/etoro.ts` **sin editarlos**. Cualquier cambio en esos archivos obliga a redesplegar también `delete-account`. Los logs siguen el estilo de los demás: `{fn, op, step, outcome}`, nunca el uid ni tokens.

**Respuestas**
```jsonc
// 200
{ "deleted": true }

// errores: siempre { "error": { type, message, step?, nothingDeleted } }
{ "error": { "type": "upstream_unavailable", "message": "RevenueCat unavailable",
             "step": "revenuecat", "nothingDeleted": false } }
```

| HTTP | `type` | `nothingDeleted` |
|---|---|---|
| 400 | `invalid_request` (falta `confirm: true`) | `true` |
| 401 | `unauthorized` | `true` |
| 405 | `method_not_allowed` | `true` |
| 429 | `rate_limited` | `true` |
| 500 | `misconfigured` | `true` |
| 502 | `upstream_unavailable` (`step`: `snaptrade` \| `revenuecat`) | calculado |
| 500 | `delete_failed` (`step`: `etoro` \| `binance` \| `auth`) | calculado |

`nothingDeleted` es `false` si **en esta llamada** ya se hizo alguna mutación (SnapTrade borrado, RC borrado, un `*_disconnect`). El handler lo lleva en una variable `mutated`. La app elige el texto de error con este campo.

**Idempotencia si se corta a la mitad**

| Se cortó después de… | Estado del usuario | Al reintentar |
|---|---|---|
| 0 | Intacto | Corre todo |
| 1 | SnapTrade desconectado (cartera como manual). Lo demás intacto | 1 es no-op (no hay secreto), sigue en 2 |
| 2 | Además sin cliente en RevenueCat. El SDK lo puede recrear con el mismo uid mientras la sesión siga viva, y es inocuo: el reintento lo vuelve a borrar | 1–2 no-op o rehechos, sigue en 3 |
| 3–4 | Sin ninguna conexión de bróker, cartera intacta como manual | Sigue en 5 |
| 5 (la respuesta se perdió) | Borrado | Con JWT asimétrico (`getClaims` local), el JWT viejo sigue siendo válido: todo es no-op, `deleteUser` responde "no existe" y devuelve 200 `deleted: true`. Con clave legacy devuelve 401 → la app cierra sesión local (§4.2) |

Dos llamadas simultáneas (doble tap) son seguras: todos los pasos son idempotentes. Igual la app deshabilita el botón.

**Presupuesto de tiempo:** menos de 45 s del lado del servidor. La app usa `receiveTimeout` de 60 s.

### 3.4 Cambio en `revenuecat-webhook` (el brief §4.5 está *casi* cumplido)

Hoy, por cada uid, el webhook llama a `GET /v1/subscribers/{uid}` **antes** de descubrir que el usuario está borrado (el 23503 recién aparece en el upsert). Según la doc v1, ese GET **crea el cliente si no existe**: rehace en RevenueCat lo que borramos y rompe la condición 1 de compliance §3. Cambio:

- Antes de `fetchSubscriber`, chequear que el uid exista (`db.auth.admin.getUserById`). Si no existe → `log(outcome: "user_deleted", user_id: null)` y `continue`, sin llamar a RevenueCat.
- El `log` de `user_deleted` (también la rama 23503 que ya existe) guarda `user_id: null`, así no vuelve a vincular el uuid en `subscription_sync_log`.
- `storeEvent` queda igual: ya guarda `user_id: null` ante el 23503.

### 3.5 App: tipos del contrato (para el fake de flutter)

```dart
/// Qué aviso de suscripción mostrar antes de confirmar.
enum DeletionStoreNotice { none, appStore, googlePlay, generic }

sealed class AccountDeletionFailure { const AccountDeletionFailure(); }
final class DeletionNothingDeleted extends AccountDeletionFailure {} // nothingDeleted=true, 429, 500 misconfigured
final class DeletionPartial extends AccountDeletionFailure {}        // nothingDeleted=false, o sin respuesta (status 0 / timeout)
final class DeletionSessionExpired extends AccountDeletionFailure {} // 401
```

Reglas de `DeletionStoreNotice` (compliance §6.1–6.2). Se toman los entitlements **activos** de `Purchases.getCustomerInfo()`, cancelados o no:
- `store` = `appStore` o `macAppStore` → `appStore` ("App Store", `https://apps.apple.com/account/subscriptions`).
- `playStore` → `googlePlay` ("Google Play", `https://play.google.com/store/account/subscriptions`).
- `promotional` → `none`. Cualquier otra tienda → `generic`.
- Sin entitlements activos → `none`.
- RevenueCat sin configurar, falla o tarda más de 3 s → `generic` si el tier del servidor (`subscriptionProvider`, solo lectura) no es free; si no, `none`.

## 4. Tareas por dueño

### 4.1 `porty-backend-dev` (arranca ya, no depende de nadie)

Archivos suyos:
- `supabase/migrations/20261102130000_account_deletion.sql` (nuevo, §3.2)
- `supabase/functions/delete-account/index.ts`, `supabase/functions/delete-account/handler.ts` (nuevos, §3.3). Patrón `Deps` de `_shared/common.ts`.
- `supabase/functions/revenuecat-webhook/handler.ts` (§3.4)
- `supabase/config.toml` (`[functions.delete-account] verify_jwt = false`)
- `supabase/tests/account_deletion_db_test.sql` (nuevo): **el test de "no queda nada"**:
  1. Crea un usuario A y un usuario B (control). A A le carga una fila en **cada** tabla de 3.1-A y 3.1-B, con secretos reales en Vault por las 3 RPC `*_save` y su uuid en `app_config` (`porty_streaming.users`). También una posición `source='etoro'`, para probar que el trigger de solo lectura no bloquea el cascade.
  2. **Guardia de catálogo:** lista por `information_schema` toda tabla de `public` con columna `user_id` y toda FK a `auth.users`. Si aparece una que no está en el inventario del test → `raise exception` (así una tabla nueva sin decidir rompe el test). Toda FK a `auth.users` tiene `confdeltype = 'c'`.
  3. `delete from auth.users where id = A`.
  4. Recorre con `EXECUTE` cada tabla con `user_id` y verifica `count(*) where user_id::text = A = 0`. Sin secretos con los nombres ni los ids de A en `vault.secrets`. A no aparece en ningún array de `app_config` ni en `waitlist`; un usuario C **sin mail confirmado** y con el mail de una fila de `waitlist` no la borra. `account_deletions_daily` sumó 1. Los datos de B siguen intactos.
  5. Imprime `ACCOUNT_DELETION_DB_TEST_OK`, todo en `begin … rollback`.
- `supabase/functions/tests/delete_account_test.ts` (nuevo): contra el stack local con `fetch` falso para SnapTrade, eToro y RevenueCat. Camino feliz (incluye `admin.deleteUser` real y verifica las tablas vacías). Cada fila de la tabla de errores. `nothingDeleted` correcto. Reintento después de cada corte de la tabla de idempotencia. Doble llamada.
- `supabase/functions/tests/revenuecat_webhook_test.ts`: caso "evento de un uid borrado" → 200, **cero llamadas** a `api.revenuecat.com`, `subscription_sync_log.user_id` null.
- `docs/runbooks/account-deletion.md` (nuevo): secretos, deploy, cómo correr los tests y la **consulta de auditoría de solo lectura para producción** (FKs a `auth.users` con su `confdeltype`, y tablas de `public` con `user_id` sin FK). El usuario la corre antes del `db push` (R1).

Cuando la función responda en `supabase start`, avisarle a flutter-dev. No hace `db push` ni deploy.

### 4.2 `porty-flutter-dev` (arranca ya contra un fake del §3.5; integra cuando backend avise)

Feature nueva `lib/features/account_deletion/`, para no tocar `lib/features/subscription/` (en curso por la spec del paywall). Archivos suyos:
- `lib/features/account_deletion/data/account_deletion_repository.dart`: `PortyEdgeClient` con un `Dio` propio (`receiveTimeout` 60 s), `post('delete-account', {'confirm': true})`. Mapea el `EdgeResponse` a `AccountDeletionFailure`. Provider al final.
- `lib/features/account_deletion/data/subscription_store_probe.dart`: envuelve `Purchases.getCustomerInfo` con una costura inyectable y devuelve `DeletionStoreNotice` con las reglas de §3.5. Lee `revenueCatServiceProvider.isConfigured` y `subscriptionProvider` **sin editarlos**.
- `lib/features/account_deletion/domain/account_deletion.dart`: el enum, la failure sealed, y tienda → nombre + URL.
- `lib/features/account_deletion/providers/account_deletion_provider.dart`: `StateNotifier` a mano con `notice`, `deleting` y `failure`.
- `lib/features/account_deletion/view/widgets/delete_account_flow.dart`. El flujo:
  1. Probe del aviso.
  2. `ConfirmSheet` con título y mensaje; si `notice != none`, el aviso **arriba del botón**, con texto de peso normal y el botón-link a la tienda, que abre afuera y no cierra la hoja.
  3. Confirmar → overlay de progreso no descartable.
  4. Si sale bien: borra las claves de SharedPreferences que contienen el uid → `signOutLocal()` → login (igual que `_onSignOut`) → toast `settings_delete_account_done`, o `settings_delete_account_done_apple` si el usuario tenía el proveedor `apple` (`user.appMetadata['providers']`, leído **antes** de borrar). RevenueCat hace `logOut` solo, con `revenueCatAuthSyncProvider`.
  5. `DeletionNothingDeleted` → `settings_delete_account_error`; `DeletionPartial` → `settings_delete_account_error_partial`; `DeletionSessionExpired` → `signOutLocal()` + login + `settings_delete_account_session_expired`.
- `lib/presentation/shared/widgets/confirm_sheet.dart`: parámetro opcional `Widget? notice`, entre el body y el botón. Sin cambios para quien no lo pasa.
- `lib/presentation/flows/settings/ui/settings_screen.dart`: `_onDeleteAccount` delega en el flujo nuevo.
- `lib/config/supabase/supabase_auth_service.dart`: `signOutLocal()` (`SignOutScope.local`). El servidor ya no tiene la sesión, así que no se llama a `unregisterBeforeSignOut`: `push_devices` cae por cascade.
- `assets/translations/es-ES.json` y `en-US.json`: claves de §4.4. Se borra `settings_delete_account_unavailable`. Son las mismas que toca el paywall: van agregadas al final de su bloque, sin reordenar.
- Tests: `test/features/account_deletion/account_deletion_repository_test.dart` (cada status/`type` → failure), `subscription_store_probe_test.dart` (cada regla de §3.5), `delete_account_flow_test.dart` (el aviso aparece antes del botón y con el link correcto; éxito → login + toast (`_done_apple` si el proveedor es `apple`); cada failure → su texto; el botón queda deshabilitado mientras corre).

### 4.3 `porty-assistant-dev`: sin tareas.

### 4.4 Textos (dueño del archivo: flutter-dev; **revisa porty-compliance**)

| Clave | Estado |
|---|---|
| `settings_delete_account_title`, `_message`, `_subscription_warning` ({store}), `_manage_subscription` ({store}), `_error`, `_done` | **Aprobados**, compliance §6. Se copian tal cual |
| `settings_delete_account_error_partial` ({email}) | Texto de compliance §6.4. **Falta el mail de soporte: lo define el usuario y bloquea el release** (también hace falta para la página web de Play). Va como constante en `lib/features/account_deletion/domain/account_deletion.dart` |
| `settings_delete_account_subscription_warning_generic` | **Aprobado** (compliance §6.1): "Si tenés una suscripción activa, borrar tu cuenta no la cancela: cancelala desde la tienda donde la compraste (App Store o Google Play) para que no se te cobre de nuevo." / "If you have an active subscription, deleting your account doesn't cancel it: cancel it in the store where you bought it (App Store or Google Play) so you're not charged again." Nunca con `promotional` |
| `settings_delete_account_session_expired` | **Aprobado, en la versión sin "y no se borró nada"** (compliance §6.1): "Tu sesión venció. Entrá de nuevo para eliminar tu cuenta." / "Your session expired. Sign in again to delete your account." Un 401 también puede llegar después de un borrado que ya terminó (reintento con clave legacy, §3.3), así que no se puede afirmar que no se borró nada |
| `settings_delete_account_done_apple` | **Aprobado** (compliance §6.1, TN3194): "Eliminamos tu cuenta. Para quitarle también el acceso a Porty en Apple, andá a Ajustes > tu nombre > Iniciar sesión con Apple." / "Your account has been deleted. To also remove Porty's access in Apple, go to Settings > your name > Sign in with Apple." Solo para usuarios con proveedor `apple` |
| `settings_delete_account_in_progress` | Nuevo, de UI: "Eliminando tu cuenta…" / "Deleting your account…" |

`settings_delete_account_message` dice "tu cartera, tus conexiones con brókers, tus metas, alertas y planes, y tu historial con Porty". Coincide con 3.1-A/B. `subscription_events` está en cascade, así que no se conserva nada que contradiga el texto (compliance §6.5).

## 5. Criterios de aceptación

1. `psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/account_deletion_db_test.sql` → `ACCOUNT_DELETION_DB_TEST_OK`, con la guardia de catálogo activa.
2. Los otros `supabase/tests/*_db_test.sql` siguen en verde (sobre todo etoro, snaptrade, binance y landing).
3. `deno task test` (en `supabase/functions`) verde, con `delete_account_test.ts` y el caso nuevo de `revenuecat_webhook_test.ts`: cero llamadas a RevenueCat para un uid borrado.
4. `flutter test test/features/account_deletion` verde; `flutter analyze` sin warnings nuevos en lo tocado.
5. Humo manual en staging (qa-engineer), con capturas: cuenta con SnapTrade, eToro y Binance conectados y con un entitlement sandbox → aviso con "App Store" o "Google Play" y el link correcto → borrar → login + toast. En el dashboard de RevenueCat el cliente ya no existe, y en SnapTrade el usuario tampoco. Volver a entrar con el mismo mail → onboarding de cero.
6. Humo de falla: `REVENUECAT_SECRET_API_KEY` inválida en staging → error con `settings_delete_account_error_partial` o `settings_delete_account_error` según `nothingDeleted`, y la cuenta sigue usable.
7. Reviewers: security-reviewer (función, trigger `security definer`, webhook), ui-reviewer (la hoja con el aviso), compliance (los 3 textos marcados).

## 6. Riesgos y decisiones

- **R1. FK de `positions`/`closed_positions` en producción, desconocida.** Las tablas son anteriores a la CLI y el baseline está vacío. Si no tienen FK, el cascade no las borra. Si la tienen sin cascade, `deleteUser` falla. La migración la asegura (`not valid`), pero **antes del `db push` el usuario corre la consulta de auditoría del runbook**, para detectar otras tablas creadas a mano en el remoto.
- **R2. El webhook recrea al cliente en RevenueCat** (3.4). Sin el cambio, la condición 1 de compliance no se cumple. Deploy de `revenuecat-webhook` junto con `delete-account`.
- **R3. Sign in with Apple.** Apple pide revocar los tokens de SIWA al borrar la cuenta. Porty usa OAuth web y no guarda el refresh token de Apple, y `deleteUser` no revoca nada. Según Apple DTS, sin token igual hay que cumplir el borrado. SIWA está prendido en el login (`auth_provider.dart:282`). **Decisión:** en el release 1 va el mínimo de TN3194 que aceptó compliance, el toast `settings_delete_account_done_apple`, sin revocación por API. La otra opción es apagar SIWA para el release 1, y la decide el usuario. Lo ideal (fase 2) agrega una re-autenticación con Apple y un campo opcional `appleAuthorizationCode` en el request, más secretos `APPLE_*`.
- **R4. Orden RevenueCat → brókers.** El brief pone primero los brókers. Muevo eToro y Binance **después** de RevenueCat porque no pueden fallar por red (revocación *best effort* y local), y así un error de RevenueCat deja menos cosas desconectadas. SnapTrade va primero porque es la única llamada externa que bloquea y es lo que se cobra por usuario.
- **R5. `waitlist`.** Se borra por email aunque no tenga vínculo con la cuenta. Compliance no lo veta, con dos condiciones: solo con mail confirmado u OAuth (para que nadie borre el registro de otro creando una cuenta sin confirmar con su mail), y un párrafo nuevo en Privacidad: "Si borrás tu cuenta, también borramos tu registro en la lista de espera."
- **Descartado:** borrado explícito tabla por tabla desde la función (frágil ante tablas nuevas; el cascade + la guardia del test es más seguro). Paso de limpieza de Vault en la función (no es atómico con `auth.users`; ver 3.2). Preflight del aviso en el servidor (un viaje más; el SDK ya trae entitlements de todas las tiendas). Agregar métodos a `revenue_cat_service.dart` (en curso por el paywall).
- **Secretos (el usuario los verifica con `supabase secrets list`; son del proyecto, así que la función nueva ve los que ya existen):** `REVENUECAT_SECRET_API_KEY` (ya está por el webhook; tiene que ser una clave **secreta v1 `sk_…`** con permiso de borrar), `SNAPTRADE_CLIENT_ID`, `SNAPTRADE_CONSUMER_KEY` (ya están por `snaptrade-sync`), `ETORO_CLIENT_ID`, `ETORO_CLIENT_SECRET` (ya están por `etoro-sync`). Opcionales: `SNAPTRADE_API_URL`, `ETORO_ENVIRONMENT`. **No hace falta ninguno nuevo.** Binance no lleva: las claves son por usuario, en Vault.
- **Necesita OK del usuario:** correr la consulta de auditoría en prod; `db push` de `20261102130000`; deploy de `delete-account` y `revenuecat-webhook`; publicar la página web de borrado y cargar su URL en Play Console (Data safety) y App Store Connect; párrafos de Privacidad sobre backups y sobre la lista de espera; **definir el mail de soporte (bloquea)**; mantener SIWA con el toast o apagarlo.
