# Runbook: otros brókers por SnapTrade (solo lectura)

Estado al 2026-10-31: **implementado y probado en local** (tests de Deno con SnapTrade falso, test SQL contra Postgres con todas las migraciones y tests de Flutter). **Nada desplegado, ninguna clave de SnapTrade cargada.** Sin `SNAPTRADE_CLIENT_ID` y `SNAPTRADE_CONSUMER_KEY`, la función responde `503 snaptrade_not_configured` y la app muestra "Esta conexión todavía no está disponible".

Contexto: SnapTrade es un agregador. Con una sola integración, Porty lee posiciones de brókers que no conecta directo (Interactive Brokers, Schwab, Webull…). eToro y Binance siguen con su conexión directa (no se pagan por usuario).

## 0. Antes de desplegar (bloqueante)

1. **Mandar el mail a SnapTrade** (`docs/superpowers/research/2026-10-31-snaptrade-contact-email.md`) y tener respuesta sobre:
   - precio por usuario (Daily ~US$1/mes) y si se cobra un usuario sin conexiones o borrado en el mes;
   - si `customRedirect` acepta `porty-snaptrade://callback` (si no, hace falta una página web intermedia que redirija);
   - si residentes de Uruguay y Argentina pueden conectar sus cuentas.
2. **Crear la cuenta y el client ID** en https://dashboard.snaptrade.com con el plan **Pay as you go / Daily**. El plan va por clave de API: no se puede mezclar Daily y Real-time en la misma.
3. **Política de privacidad**: agregar SnapTrade como proveedor que procesa datos de las cuentas conectadas.

## 1. Planes

| | Free | Premium | Gold |
|---|---|---|---|
| Conectar por SnapTrade | No (paywall) | **1 bróker** | **Todos** |
| "Pedir datos al bróker ahora" | — | — | Sí, cuando se habilite (ver §4) |

- En la app: `PlanFeature.brokerSync` (Premium), `multiBrokerSync` y `brokerManualRefresh` (Gold), en `lib/domain/subscription/plan_matrix.dart`.
- En el servidor: `planConfig` en `supabase/functions/snaptrade-sync/mapping.ts`. **El servidor es el que manda.**
- Premium con un bróker ya conectado: `/connect` responde `409 snaptrade_connection_limit` y la app muestra el paywall de Gold. Si igual tiene más de uno en SnapTrade (por ejemplo, bajó de Gold), se importa el más viejo y los demás aparecen como "No incluido".
- Bajar a Free: no sincroniza más (`snaptrade_plan_required`), pero **desconectar sigue funcionando**, para que deje de cobrarse.

## 2. Arquitectura

| | App | Servidor |
|---|---|---|
| Conectar | Ajustes → Cuentas conectadas → Otros brókers → "Conectar un bróker". Abre el Connection Portal en el navegador del sistema (`flutter_web_auth_2`, esquema `porty-snaptrade`) | `POST snaptrade-sync/connect {darkMode, reconnect?}`: la primera vez registra un usuario en SnapTrade con un **id al azar** (SnapTrade nunca ve el id de Porty) y guarda `{user_id, user_secret}` en Vault. Devuelve la URL del portal, siempre con **`connectionType: read`** |
| Al volver del portal | Sincroniza forzado y recarga la Home | `POST snaptrade-sync/sync {force: true}` |
| Sincronizar | Al abrir o volver a la app, si lo último tiene más de 1 h, y con "Actualizar" | `POST snaptrade-sync/sync`: como mucho una cada 5 min, lease por usuario, `snaptrade_apply_sync` atómico |
| Quitar un bróker | "Quitar" en la fila del bróker | `POST snaptrade-sync/remove {authorizationId}`: borra la conexión en SnapTrade y vuelve a sincronizar |
| Reconectar uno caído | "Reconectar" en la fila | `/connect {reconnect: id}` |
| Desconectar todo | Hoja "¿Qué hacemos con lo importado?" | `POST snaptrade-sync/disconnect {keepAsManual}`: **borra el usuario en SnapTrade** (deja de cobrarse; si SnapTrade no responde, no desconecta y devuelve 503), borra el secreto de Vault y convierte en manuales o borra las filas `snaptrade` |

- Posiciones en `positions` con `source='snaptrade'`, `external_id = <cuenta>:<ticker>` y `broker_price`. El trigger `_etoro_rows_read_only` las deja de solo lectura para la app.
- **Qué se importa:** acciones, ADR, ETF, fondos cerrados, fondos comunes y cripto (el ticker de cripto pasa a `BTC-USD`). No: efectivo y equivalentes (`cash`), opciones, futuros, CFD, bonos (`unsupported`), cortos (`short`) y lo que no tiene precio (`no_price`).
- **Precio de compra:** el `cost_basis` del bróker. Si no lo informa, el precio del momento, y la app lo avisa (`estimatedCost`). La fecha de compra es la primera vez que Porty vio la posición.
- **No se importan por acá:** eToro y Binance (`direct_connection`, se conectan directo) ni una conexión con permiso de operar (`trade_permissions`; Porty nunca la pide).
- Firma de los pedidos: HMAC-SHA256 de `{content, path, query}` con la consumer key, igual que el SDK oficial (`snaptrade-typescript-sdk` 13.1.14). El test compara contra vectores sacados del SDK.

Secrets de `snaptrade-sync`:

| Secret | |
|---|---|
| `SNAPTRADE_CLIENT_ID` | obligatorio |
| `SNAPTRADE_CONSUMER_KEY` | obligatorio |
| `SNAPTRADE_APP_REDIRECT` | opcional, default `porty-snaptrade://callback` |
| `SNAPTRADE_MANUAL_REFRESH` | `on` para habilitar "Pedir datos al bróker ahora" (Gold). Default apagado |
| `SNAPTRADE_REFRESH_PER_DAY` | cupo diario por usuario, default 2 |
| `SNAPTRADE_API_URL` | opcional, default `https://api.snaptrade.com` |

### Desde el chat

`propose_broker_action` con `broker: snaptrade` muestra una card para confirmar y hace lo mismo que la pantalla:

- `connect`: abre el portal de solo lectura. Premium que ya tiene un bróker → `locked` (Gold) en la tool, y la app vuelve a mirar el plan al confirmar (paywall de Gold, sin abrir el portal).
- `sync` y `disconnect` (pregunta si conservar lo importado).
- eToro y Binance siguen sin poder conectarse desde el chat (`connect_in_app`): piden OAuth o una clave.

## 3. Desplegar

```bash
supabase db push            # 20261031000000_snaptrade_sync.sql
supabase secrets set SNAPTRADE_CLIENT_ID=... SNAPTRADE_CONSUMER_KEY=...
supabase functions deploy snaptrade-sync
```

La app necesita un build nuevo (pantalla, Ajustes y el esquema `porty-snaptrade` en Android). En iOS no hace falta registrar el esquema: `ASWebAuthenticationSession` lo toma de `callbackUrlScheme`.

**Apagar de golpe:** `supabase secrets unset SNAPTRADE_CONSUMER_KEY`. Conectar y sincronizar pasan a "no disponible"; lo importado queda como está.

## 4. "Pedir datos al bróker ahora" (Gold)

SnapTrade cobra **cada** llamada a `POST /authorizations/{id}/refresh` en el plan Daily. Por eso está apagado en dos lugares:

1. Servidor: `SNAPTRADE_MANUAL_REFRESH=on`, con cupo diario (`snaptrade_take_refresh`).
2. App: `snaptradeManualRefreshEnabled` en `lib/features/snaptrade/view/snaptrade_screen.dart` (hoy `false`).

Prenderlo cuando SnapTrade confirme el costo por llamada.

## 5. Probar

1. Con el client ID de prueba, conectar una cuenta *paper* de Alpaca (o cualquier bróker de prueba que ofrezca el portal).
2. Premium: conectar un bróker → aparece en Inicio con la marca "Bróker". "Conectar otro bróker" → paywall de Gold.
3. Gold: conectar un segundo bróker → se importan los dos.
4. Cambiar la contraseña en el bróker → la fila pide "Reconectar"; lo importado sigue en pantalla.
5. Desconectar con "Conservarlas como manuales" → se pueden editar, y el usuario ya no aparece en el dashboard de SnapTrade.

Tests:

```bash
cd supabase/functions && deno test --allow-env tests/snaptrade_sync_test.ts
psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/snaptrade_sync_db_test.sql
flutter test test/features/snaptrade
RUN_SCREENSHOTS=1 SCREENSHOTS_OUT=/tmp/shots flutter test test/screenshots/snaptrade_screenshots_test.dart
```

## 6. Seguridad y datos

- **Secreto del usuario:** cifrado en Vault (`snaptrade_users` guarda solo el puntero). Nunca vuelve a la app ni va a los logs.
- **Solo lectura:** el portal se abre siempre con `connectionType: read`, y si alguna conexión vuelve con `type` distinto de `read`, no se importa.
- **Costo:** se paga por usuario de SnapTrade. El usuario se crea recién cuando toca "Conectar" y se borra al desconectar. Si un usuario abre el portal y no conecta nada, queda `pending`: confirmar con SnapTrade si eso se cobra (pregunta 3 del mail).
