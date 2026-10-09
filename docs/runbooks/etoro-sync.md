# Runbook: conexión con eToro (solo lectura)

Estado al 2026-10-09: **implementado y probado en local. Nada desplegado, ningún secreto cargado y ningún cliente OAuth registrado.**

Investigación y decisiones: `docs/superpowers/research/2026-10-08-etoro-integration.md`.

## 0. Antes de desplegar (bloqueante)

1. **Autorización de eToro.** Los términos (Builders' Economy, 17-feb-2026, Parte I §1.2 y Parte V §1.5) limitan el uso a la propia cuenta salvo autorización escrita. Mandar el mail de `docs/superpowers/research/2026-10-08-etoro-contact-email.md` y esperar la respuesta, sobre todo para:
   - el uso comercial;
   - el almacenamiento de datos;
   - el envío de posiciones a OpenAI (decisión 8);
   - si alcanza con el refresh token o hace falta un *non-interactive token* para sincronizar.
2. **Revisión legal** de los puntos abiertos de la investigación (sección "Términos").
3. **Política de privacidad** actualizada en `portfolioai.app/privacy` (sección 7 de este runbook) y formularios de las tiendas: Google Play Data safety y App Store Privacy, en ambos con "Financial info".

## 1. Arquitectura

| | App | Servidor |
|---|---|---|
| Conectar | Ajustes → eToro (o la Home vacía, o el onboarding) → `POST etoro-sync/connect/start` → abre `authorizeUrl` en el navegador del sistema (`flutter_web_auth_2`: ASWebAuthenticationSession / Custom Tabs, sin WebView) | Genera `state`, `nonce` y PKCE S256 y los guarda en `etoro_oauth_states`. eToro vuelve a `GET etoro-sync/callback`, que intercambia el código, valida el ID token (RS256/JWKS, iss, aud, nonce), **rechaza y revoca si hay cualquier scope de escritura**, guarda los tokens en Vault, importa y redirige a `porty-etoro://callback?status=ok` (sin tokens en el deep link) |
| Sincronizar | Al abrir la app o volver a ella (si lo último tiene más de 15 min), con pull-to-refresh en Inicio y con "Actualizar ahora" | `POST etoro-sync/sync`: como mucho una cada 5 min (si no, devuelve la última), lease por usuario, refresco con rotación guardada antes de usar el token, un solo reintento ante 401, y `etoro_apply_sync` atómico |
| Leer estado | `select` de `etoro_connections` (RLS: la suya) | — |
| Desconectar | Hoja "¿Qué hacemos con lo importado?" | `POST etoro-sync/disconnect {keepAsManual}`: revoca en eToro (si falla, sigue igual), borra el secreto de Vault y convierte en manuales o borra las filas `etoro` |

- Las posiciones importadas viven en `positions` y `closed_positions` con `source='etoro'`.
- El trigger `_etoro_rows_read_only` impide que la app (roles anon/authenticated) las inserte, edite o borre.
- La app también lo bloquea antes, con el error `position_read_only`.
- `deleteByTicker` solo borra las manuales.

Secrets de `etoro-sync`:

| Secret | Valor |
|---|---|
| `ETORO_CLIENT_ID` | client id del registro OAuth en eToro |
| `ETORO_CLIENT_SECRET` | client secret: eToro lo muestra **una sola vez** |
| `ETORO_REDIRECT_URI` | `https://<project-ref>.supabase.co/functions/v1/etoro-sync/callback`, idéntica a la registrada |
| `ETORO_APP_REDIRECT` | opcional, por defecto `porty-etoro://callback` |
| `ETORO_ENVIRONMENT` | **solo staging**: `demo` usa los endpoints demo y el scope `etoro-public:demo:read`. En producción no se define (o se pone `real`) |

Sin `ETORO_CLIENT_ID`, `ETORO_CLIENT_SECRET` o `ETORO_REDIRECT_URI`, la función responde `503 etoro_not_configured` y la app muestra "no disponible": eso sirve de interruptor de apagado.

## 2. Registrar el cliente OAuth en eToro

En el *self-service application dashboard* de builders.etoro.com (con la cuenta de eToro de Porty), o por API con `POST /api/v1/sso/applications`:

- **Nombre:** Porty. **Descripción:** sincronización de cartera de solo lectura.
- **Redirect URI (exacta, HTTPS):** `https://<project-ref>.supabase.co/functions/v1/etoro-sync/callback`. Una por entorno (staging y prod).
- **Scopes:** `openid` y `etoro-public:real:read`. En staging se agrega `etoro-public:demo:read`. **Ningún `:write`.**
- **Autenticación del cliente:** `client_secret_basic` (cliente confidencial). PKCE S256 siempre.
- Guardar el `clientSecret` en el gestor de secretos al crearlo. Para rotarlo: `POST /api/v1/sso/applications/{clientId}/client-secret`. El anterior deja de valer en el acto, así que hay que cargar el nuevo en Supabase en la misma ventana.

## 3. Base de datos

1. **Comparar el esquema remoto** de `positions` y `closed_positions` con el que asume la migración: `id uuid`, `user_id`, `ticker`, `quantity`, `purchase_price`, `purchase_date`, y para las cerradas `avg_purchase_price`, `close_price`, `close_date` y `closed_at`.

   ```sh
   supabase db dump --schema public -f /tmp/remote_public.sql   # o el panel
   ```

   En el remoto, la migración no recrea las tablas (`if not exists`): solo agrega columnas (`source`, `external_id`, `synced_at`, `realized_pnl`), constraints y triggers, y deja las policies que ya existen. Si `id` no es `uuid`, avisar antes de seguir: `etoro_apply_sync` castea a `uuid`.
2. Confirmar que **Vault** está habilitado (`supabase_vault`, viene por defecto en los proyectos de Supabase):

   ```sql
   select extname from pg_extension where extname = 'supabase_vault';
   ```
3. Aplicar en **staging** y correr el test de la base:

   ```sh
   supabase db push --linked
   psql "$STAGING_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/etoro_sync_db_test.sql   # termina con ETORO_DB_TEST_OK y hace rollback
   ```
4. Recién después, producción (`supabase db push`).

## 4. Edge function

```sh
supabase secrets set --env-file supabase/functions/.env.etoro   # archivo fuera de git
supabase functions deploy etoro-sync --no-verify-jwt
```

- `--no-verify-jwt` hace falta porque el callback llega desde el navegador sin JWT de Supabase. Ya está en `supabase/config.toml`.
- Las rutas `connect/start`, `sync` y `disconnect` validan el JWT ellas mismas, igual que `finnhub`.

Verificación rápida (no toca eToro):

```sh
curl -s -X POST https://<ref>.supabase.co/functions/v1/etoro-sync/sync   # → 401 unauthorized
```

## 5. App

- La dependencia nueva es `flutter_web_auth_2`.
- **Android:** `CallbackActivity` con el esquema `porty-etoro` en `AndroidManifest.xml` (ya está).
- **iOS:** no hace falta configuración, porque ASWebAuthenticationSession recibe el esquema directamente.
- Se usa `preferEphemeral: true`: la sesión de eToro no queda guardada en Safari.
- La conexión con eToro se ofrece en Premium y Gold (`PlanFeature.brokerSync`). El servidor también lo valida (`etoro_plan_required`).

## 6. Prueba de punta a punta (staging, cuenta demo)

Requiere el cliente OAuth registrado (paso 2), la función en staging con `ETORO_ENVIRONMENT=demo` y un build de la app apuntando a staging.

1. Free → Ajustes → eToro → "Conectar eToro" abre el paywall y no hace ningún pedido.
2. Premium → "Conectar eToro" → se abre el navegador del sistema en `www.etoro.com/sso` → login con la **cuenta demo** → la pantalla de consentimiento muestra solo lectura → vuelve a la app con "Importamos N posiciones" y lo que no se importó, explicado.
3. En Inicio, las posiciones aparecen con la marca "eToro", sin deslizar para borrar. El detalle dice "Se actualiza desde eToro" con la fecha y no tiene "Cerrar".
4. Si había una posición manual del mismo ticker, aparece en "¿Ya las tenías cargadas?". Probar las dos opciones.
5. Pull-to-refresh dos veces seguidas: la segunda devuelve la última sin pedir a eToro (logs: `"outcome":"throttled"`).
6. Revocar el acceso de Porty desde eToro → abrir la app pasados 15 min → aparece el aviso "Reconectá tu cuenta" en Inicio y las posiciones siguen. Reconectar → vuelve a `connected`.
7. Desconectar con "Conservarlas como manuales" → se pueden editar. Volver a conectar y desconectar con "Borrarlas" → solo se van las de eToro.
8. Revisar los logs de la función: solo líneas `{"fn":"etoro-sync","op":…}`, sin tokens, códigos ni ids.
9. Probar en modo claro y oscuro, con reduce motion y con la letra al máximo.

Antes de producción: sacar `ETORO_ENVIRONMENT` y registrar la redirect URI de prod.

## 7. Cambios en la política de privacidad (texto a revisar por legal)

- **Qué datos:** si el usuario conecta eToro, Porty recibe de eToro sus posiciones abiertas, su historial de operaciones cerradas y un identificador seudónimo de la cuenta. eToro no le da a Porty nombre, email ni otros datos personales.
- **Para qué:** mostrar la cartera en Porty y, si el usuario usa el asistente, responder preguntas sobre su propia cartera.
- **Base legal:** el consentimiento explícito al conectar. Se retira desconectando.
- **Acceso de solo lectura:** Porty no puede comprar, vender, transferir ni modificar nada en la cuenta de eToro.
- **Credenciales:** los tokens de eToro se guardan cifrados en el servidor (Supabase Vault). No se guardan en el teléfono ni se usan para otra cosa.
- **Proveedores:** Supabase (almacenamiento) y OpenAI (el asistente procesa la cartera para responder al mismo usuario). Sujeto a la respuesta de eToro sobre este punto.
- **Retención:** al desconectar se revoca el acceso y se borran los tokens en el momento. Las posiciones se conservan como manuales o se borran, según elija el usuario. Al borrar la cuenta de Porty se borra todo.
- **Derechos:** desconectar desde Porty o desde eToro en cualquier momento.

## 8. Operación

- **Logs:** `fn=etoro-sync`, con `op` igual a `connect_start`, `callback`, `sync` o `disconnect` y su `outcome`.
- **Señales a vigilar:**
  - suba de `etoro_unavailable` o `etoro_rate_limited`;
  - cualquier `write_scope` en callback (indicaría un cambio en eToro);
  - `config` en callback (client secret vencido o rotado).
- **Límites:** 60 GET/min por usuario del lado de eToro. Cada sincronización hace unas 4 a 5 llamadas, y la metadata de instrumentos se cachea 24 h en `etoro_instruments`.
- **Apagar de golpe:** borrar `ETORO_CLIENT_SECRET` (`supabase secrets unset ETORO_CLIENT_SECRET`). Conectar y sincronizar pasan a fallar con "no disponible"; lo ya importado queda como está.
- **Credenciales comprometidas:** rotar el client secret y avisar a eToro dentro de las **24 h** (términos, Parte II §1).
- **Rollback de la migración:** no hay `down`. Para volver atrás:
  1. desconectar a todos con `select etoro_disconnect(user_id, true) from etoro_connections where status <> 'disconnected';`, que convierte lo importado en manual y borra los tokens;
  2. recién después, borrar las tablas `etoro_*`.

## 9. Tests

```sh
# Lógica de la edge function (sin red ni base)
cd supabase/functions && deno test --allow-env tests/etoro_mapping_test.ts tests/etoro_sync_test.ts

# Integración con el stack local (Postgres + PostgREST + Auth + Vault reales; eToro falso)
supabase start && cd supabase/functions && deno task test   # incluye tests/etoro_sync_integration_test.ts

# Base de datos: RLS, trigger de solo lectura, Vault, apply/disconnect
psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/etoro_sync_db_test.sql

# App
flutter test test/features/etoro test/infraestructure/repositories/etoro_read_only_test.dart \
  test/domain/entities/position_source_test.dart test/features/assistant/tools/etoro_positions_tools_test.dart
```
