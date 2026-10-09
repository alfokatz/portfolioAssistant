# Integración con eToro (solo lectura): investigación — FASE 1

**Fecha:** 2026-10-08
**Estado:** decisiones tomadas (ver abajo). Prueba demo real y respuesta de eToro pendientes. No hay código de producción.
**Alcance:** solo lectura. Porty no compra, no vende ni modifica nada en eToro.

## Decisiones (2026-10-08, Alfonso)

| # | Tema | Decisión |
|---|---|---|
| 1 | Contacto con eToro | Sí. Lo firma **Alfonso Katzenstein, Founder de Porty**. Borrador en `2026-10-08-etoro-contact-email.md`. |
| 2 | Plan B (claves pegadas) | **Descartado.** Solo OAuth. |
| 3 | CFD comprados sin apalancamiento | **Aparte**, no como posición. |
| 4 | Cripto | **Aparte** en la primera versión. |
| 5 | P&L de cerradas | Se guarda la **ganancia neta de eToro** (`netProfit`). Si falta, la calcula Porty. Hace falta un campo opcional nuevo en `closed_positions`/`ClosedPosition` (por ejemplo, `realized_pnl`). |
| 6 | Copy trading / Smart Portfolios | **No se muestran** por ahora. Supuesto: en la pantalla de resultado igual figuran como "no importado: copy trading", para que el usuario sepa por qué faltan. |
| 7 | Plan | **Premium y Gold.** En Free se ve el paywall. |
| 8 | Asistente | **Sí:** las posiciones de eToro entran al snapshot del asistente (OpenAI), como las manuales. Le preguntamos a eToro explícitamente en el contacto (§3, punto 4) y lo declaramos en la política de privacidad. |
| 9 | Prueba demo | Pendiente de red o de que Alfonso corra el script (ver §5). |

---

## FASE 2: estado (2026-10-09)

Implementada y probada en local, sin commits ni deploys. Despliegue, prueba de punta a punta y
pendientes: `docs/runbooks/etoro-sync.md`.

Cambios respecto del diseño de §6:
- Identidad por `sub` (pairwise), como pide la doc oficial, no por `gcid`.
- Scopes `openid` + `etoro-public:real:read`, sin `offline_access`.
- Revocación en `/api/sso/v1/token/revoke`.
- Historial: primera importación de 5 años; si eToro rechaza la ventana, se reintenta con el último año.
- Mapeo por **bolsa** (no por sufijo): `DASH.US` → `DASH` y `BRK.B` queda igual.
- `ETORO_ENVIRONMENT=demo` para probar en staging con una cuenta de dinero virtual.

Pendientes conocidos:
- **Ticker sin cotización en Porty** (por ejemplo, un símbolo de Nasdaq poco común): hoy se importa igual. La Home lo valúa al precio de compra, como ya pasa con un ticker manual sin cotización. Falta validar la cotización al importar y mandarlo a "no importado".
- **Token no interactivo (NIT):** si eToro exige NIT para sincronizar sin el usuario presente, hay que sumar ese paso después del callback (ver "Impacto en el diseño").

## Verificación con fuentes oficiales (2026-10-08, con red habilitada)

Con los dominios habilitados leí las fuentes primarias: el discovery OIDC, *SSO with OAuth 2.0*,
*Partner integration flow*, *Authentication*, *Rate Limits*, la **spec en vivo
`/api-reference/openapi.json` v1.387.0**, la página de *App Registration* y el **PDF completo de los
términos**. **Esta sección manda sobre lo que diga el resto del documento.** Las secciones 0 a 3
quedan como registro de la investigación sin red.

### OAuth: lo oficial

| Tema | Dato oficial | Fuente |
|---|---|---|
| Endpoints | Autorización `https://www.etoro.com/sso` · token `https://www.etoro.com/api/sso/v1/token` · **revocación `https://www.etoro.com/api/sso/v1/token/revoke`** · userinfo `…/api/sso/v1/userinfo` · JWKS `…/.well-known/jwks.json` · registro `…/api/sso/v1/register`. **Las URLs que traías estaban bien**; las del plugin de Cursor (`/sso/oidc/token`, `/sso/v1/revoke`) no coinciden con el discovery. | `https://www.etoro.com/.well-known/openid-configuration` (consultado en vivo) |
| Flujo | Solo `response_type=code`, **PKCE S256 obligatorio para todos los clientes**, incluidos los confidenciales. `state` y `nonce` obligatorios. Las redirect URIs se comparan de forma exacta, en HTTPS y apuntando al backend. | sso-oauth |
| Cliente | Confidencial, autenticado con `client_secret_basic` o `private_key_jwt`. El `clientSecret` se muestra **una sola vez**; al rotarlo, el anterior deja de valer en el acto. | sso-oauth |
| **Registro** | **Autoservicio**: *"Register through the eToro Builders portal, or programmatically with `POST /api/v1/sso/applications`"*. Builders: *"Use the self-service application dashboard to sign in with eToro, configure redirect URIs and scopes, and generate an OAuth client"*. Igual hay revisión: *"Your request enters a review queue. eToro may ask clarifying questions about security, data use, or UX"*. Lo que no está en autoservicio va por los formularios de partner. | sso-oauth, builders.etoro.com/app-registration |
| Scopes | El catálogo que el cliente puede pedir sale de `GET /api/v1/sso/scopes` y **se asigna por partner**. *"Request the narrowest set"*. | sso-oauth, partners |
| **Tokens** | Access token **~1 hora** (`expires_in: 3600`), se refresca con `grant_type=refresh_token`. Refresh token **"long-lived"**, guardado cifrado, uno por usuario y cliente, y revocado cuando el usuario desconecta. | sso-oauth §Token lifecycle |
| **Trabajo sin el usuario presente** | *"An access token is bound to the user's interactive session. For backend work performed while the user is not present, a long-lived non-interactive token is issued instead."* El NIT se crea con `POST /api/v1/sub-accounts/etoro-trading/user-tokens` (scopes elegibles, `expiresAt`, `ipsWhitelist`), se usa como `x-user-key` junto a la `x-api-key` **de la aplicación**, y se revoca con `DELETE …/user-tokens/{id}`. eToro menciona como ejemplo explícito *"portfolio synchronization"*. *"Confirm with your eToro contact which non-interactive token provisioning path applies to your integration."* | partners/integration |
| Identidad | La clave es el **`sub` (pairwise)**: no tiene datos personales y es estable para nuestro cliente. eToro **no entrega datos personales** (email, nombre…) sin una aprobación aparte. *"No PII joins"*. | sso-oauth §Identity |
| Checklist de producción | PKCE en todo, `state` + `nonce`, redirección HTTPS exacta, validación completa del ID token, secretos y refresh tokens en un almacén de secretos (*"never in a log line, never in an error payload"*), revocación conectada al offboarding, `x-request-id` en cada llamada y nada de datos personales en logs ni analytics. | sso-oauth §Security checklist |

### Scopes exactos por endpoint (spec en vivo v1.387.0)

Basta con **uno** de los scopes listados (semántica OR):

| Endpoint | Scopes que alcanzan (en negrita el que pediríamos) |
|---|---|
| `GET /api/v1/me` | **`real:read`**, `demo:read`, `real:write`, `demo:write`, `user-info:read` |
| `GET /api/v1/trading/info/real/pnl` y `/portfolio` | **`real:read`**, `real:write`, `trade.real:read`, `trade.real:write` |
| `GET /api/v1/trading/info/trade/history` | **`real:read`**, `real:write`, `trade.real:read`, `trade.real:write` |
| `GET /api/v1/trading/info/aggregate-portfolio` | **`trade.real:read`**, `trade.real:write` (no acepta `real:read`) |
| `GET /api/v1/market-data/instruments`, `/instrument-types` | cualquier token válido |
| Demo: `demo/pnl`, `trade/demo/history` | `demo:read`, `trade.demo:read` (y sus `:write`). `demo/aggregate-portfolio` solo acepta `trade.demo:read`. |

→ **Para Porty alcanza con `openid` + `etoro-public:real:read`.** No hace falta el agregado, y
ninguno de esos scopes permite operar. Si eToro solo nos diera un NIT, se pediría con
`etoro-public:trade.real:read` únicamente.

### Rate limits (oficial)

- Se miden por user key, en ventana móvil de 1 minuto. 429 con backoff.
- `pnl`, `portfolio` y `aggregate-portfolio` comparten **60/min**.
- `trade/history` y `/me` van por la cuota compartida por defecto: **60/min**. El 20/min de "User
  Trade Info" se refiere a la info de trading de *otros* perfiles, no a nuestro historial.
- `market-data/instruments` tiene **120/min**, compartidos con rates y candles.
- **Historial:** cada pedido puede mirar **menos de 1 año** hacia atrás (*"maximum 1 year minus 1
  day"*). Para más, se pagina en ventanas anuales moviendo `minDate`. La respuesta sigue **sin
  `settlementTypeID` ni `mirrorID`**: no se puede distinguir CFD de activo real en las cerradas.
- El endpoint demo de historial existe y acepta `demo:read`. La advertencia del plugin
  (`InsufficientPermissions`) se confirma o se descarta con la prueba real.

### Claves de API (plan B, descartado)

Confirmado en la página oficial: *"Select 'Read' if you only need to access your portfolio data.
Select 'Write' if you need to execute trades"*, con lista de IPs y vencimiento opcionales.

### Términos: texto completo, con cláusulas

"eToro Builders' Economy — Public API & eToro App Store — Terms of Use", BETA, 17-feb-2026,
eToro Group Trading Ltd. (PDF de 15 páginas, leído completo). Lo relevante:

| Cláusula | Texto (extracto) |
|---|---|
| Preámbulo | La Public API provee *"controlled access to users' eToro accounts"*. eToro puede *"cancel or limit the availability … to any user, area, or jurisdiction at any time"*. |
| **Parte I §1.2 Permitted Use** | *"…to access and manage your own eToro trading account, develop and test tools for personal use in connection with your account, and, where expressly authorized, publish tools through the App Store for use by other eToro users, but excluding any commercial redistribution of eToro data or use on behalf of third parties…"* · *"Any other use is prohibited unless expressly authorised in writing by eToro."* |
| Parte I §1.3 | El desarrollador es responsable de cumplir *"data-privacy laws (GDPR, CCPA, and equivalents)"* y la legislación de IA. |
| Parte I §1.5 | Producto **beta**: puede cambiar o desaparecer sin aviso. |
| **Parte II §1 Access and Credentials** | *"To use the Public API you need to apply … which may be granted, denied, or revoked at any time."* Las credenciales son confidenciales: *"must not share, sell, or transfer them"*. Si hay un compromiso, se avisa en **24 h** y se rotan. |
| Parte II §2.1–2.4 | Respetar rate limits. **§2.4(c):** no *"pre-fetches, bulk-requests, or systematically caches Licensed Content beyond what is reasonably required for the Permitted Use"*. |
| Parte II §2.6 | Ante un problema de seguridad: *"immediately notify eToro and cease connecting to the Public API until permitted to reconnect"*. |
| **Parte II §3 Licensed Content** | Se define como *"certain data … including charts, volumes, sentiments, news, and related information"*. Prohíbe usarlo para *"any commercial purpose, redistribution, onward transmission, publication…"* más allá del uso permitido. *"eToro's marks must accompany all displays of Licensed Content."* Hay que borrarlo dentro de **24 h** si eToro lo pide. |
| Parte IV §2.2 | Que un Publisher cobre requiere el *"prior consent"* de eToro y transparencia total del precio. (Aplica a las Listed Tools del App Store.) |
| Parte IV §3.2 | Las Listed Tools tienen licencia *"personal, non-commercial use"*. (Aplica al App Store, no a una app externa.) |
| Parte IV §3.6 / §6.6 | Las herramientas pueden tratar datos del usuario según la política del Publisher. Si una herramienta se retira, se da **30 días** de transición, y sigue la responsabilidad por *"User Data already collected"*. |
| **Parte V §1.5** | No usar la Builders' Economy *"for or on behalf of any third party except as permitted for Listed Tools"*. |
| **Parte V §1.7** | No usar *"Licensed Content or AI-generated outputs to train, fine-tune, or **ground** any model, or to develop competing products"*. |
| **Parte V §1.8** | No *"scrape, bulk-download, cache, redistribute, sell, sublicence, or create separate databases from Licensed Content … or any other data beyond the Permitted Use"*. |
| Parte V §1.9 / §1.11 | Nada de publicidad ni perfilado con Licensed Content. No tratar *"sensitive data without eToro's written permission"*. |
| Parte V §3.2 | El desarrollador garantiza que el uso y la *comercialización* de sus herramientas cumple con la ley, incluida la de protección de datos. |
| Parte V §4.3 / §5 | La responsabilidad total de eToro tiene un **tope de USD 1.000**, y el desarrollador **indemniza** a eToro, incluso por *"data breach"*. |
| Parte V §6.1–6.3 | eToro puede cortar el acceso, con 14 días de aviso salvo por "Critical Reasons", o de inmediato. Al terminar hay que borrar el Licensed Content y las credenciales. |
| Parte V §8–9 | Sin cesión sin consentimiento. **Ley y jurisdicción de las Islas Vírgenes Británicas.** |

**Lo que hay que llevar a revisión legal** (no saco conclusiones):

1. **Tensión entre los términos y la documentación técnica.** La documentación de OAuth está pensada
   para *"an application that signs other eToro users in and acts on their behalf"* (cita *"a
   portfolio dashboard"* como ejemplo) y el registro es autoservicio. Los términos, en cambio,
   limitan el uso permitido a la propia cuenta y prohíben el uso *"on behalf of any third party
   except as permitted for Listed Tools"* (V §1.5), salvo autorización escrita (I §1.2). Hay que
   confirmar con eToro si registrar un cliente OAuth equivale a esa autorización, o si hace falta
   algo más.
2. **¿Las posiciones del usuario son "Licensed Content"?** La definición habla de *"charts, volumes,
   sentiments, news, and related information"*. Si incluye las posiciones, guardarlas en nuestra base
   (V §1.8) y pasárselas a OpenAI (V §1.7 *"ground any model"*, y la "onward transmission" de II §3)
   queda en zona gris. Esto **afecta directamente la decisión 8** (el asistente).
3. **Cobrar:** el consentimiento previo de IV §2.2 está escrito para Listed Tools. No está claro si
   aplica a una app externa con suscripción.
4. **Marcas:** II §3 exige mostrar las marcas de eToro junto al Licensed Content. Si aplica, la UI
   debería decir "Datos de eToro" o similar.
5. ¿Las cuentas de la UE o el Reino Unido agregan obligaciones (I §1.3: GDPR)? Aplica la ley de las
   Islas Vírgenes Británicas.

### Impacto en el diseño (§6)

- **Identidad:** guardar `etoro_sub` (pairwise) como clave de asociación, como manda la documentación
  oficial. `gcid` y `realCid` vía `/me` solo si hacen falta, sin datos personales.
- **Scopes pedidos:** `openid etoro-public:real:read`, sin `offline_access` (el ejemplo oficial no lo
  usa y el refresh token viene igual; se confirma en el registro).
- **Revocación:** `POST https://www.etoro.com/api/sso/v1/token/revoke`, según RFC 7009.
- **Sincronizar al abrir la app o con pull-to-refresh, ¿cuenta como "usuario presente"?** El usuario
  está en Porty, pero no en una sesión interactiva de eToro. Si el refresh token alcanza para eso,
  el diseño de §6 sirve como está. Si eToro exige un NIT, se agrega un paso después del callback:
  crear un NIT con solo `trade.real:read`, con `expiresAt`, sin lista de IPs (Supabase no tiene IP
  fija), guardarlo en Vault y sincronizar con `x-api-key` de la app + NIT. La rotación y el
  `DELETE` del NIT pasan a ser parte de "desconectar". **Pregunta para eToro, agregada al mail.**
- **Historial:** pedir en ventanas de menos de un año. Primera importación: ventanas hacia atrás hasta
  que no haya más datos; después, incremental.
- **Validación del ID token:** firma RS256 contra JWKS por `kid`, `iss`, `aud`, `exp` y `nonce`. La
  edge function usa `jose`, como recomienda eToro.

## Prueba en vivo (2026-10-09, cuenta REAL, clave Read)

No se pudo crear una clave Demo: eToro no lo permitió en la cuenta de Alfonso. Con su autorización
explícita se usó una clave **Real con permiso Read** y vencimiento corto. Fueron solo GETs: 9
llamadas, sin ningún 429. La salida cruda quedó fuera del repo y se borró. Acá van solo
resultados agregados, sin tickers ni montos del usuario.

**Resultados**

| Qué | Resultado |
|---|---|
| `GET /api/v1/me` con el par de claves | **403 `InsufficientPermissions`**. Con claves de usuario no sirve para identidad ni scopes; con OAuth hay que confirmarlo. El script ya no depende de él. |
| `GET /trading/info/real/pnl` | 200. **26 posiciones**, 0 mirrors. |
| `GET /trading/info/aggregate-portfolio` | 200 con el par de claves. `accountCurrency = USD`. |
| `GET /market-data/instruments`, `/exchanges`, `/instrument-types` | 200. Instrumentos resueltos: 13/13 de las abiertas, más 5 de las cerradas. |
| Clasificación | **25 se importan** (acciones y ETFs, todas `REAL_ASSET`, leverage 1, compradas, en Nasdaq/NYSE), **1 aparte** (ver el bug de abajo), 0 saltadas. Hay varios lotes del mismo ETF (hasta 11), y las 26 posiciones tienen fracciones. Fechas de compra entre 2024 y 2026. |
| Precio | En las 26, `openRate` coincide con `amount/units` (diferencia < 1 %). Para acciones de EE.UU., **`openRate` es el precio de compra en USD**: confirmado. |
| `GET /trading/info/trade/history` | 200. Con `minDate` de un año: 4 cerradas. **Con `minDate` de dos años: 6, incluidas 2 de hace más de un año.** El límite de "< 1 año" no se aplicó en esta prueba, pero igual vamos a pedir en ventanas para seguir la documentación. Todas traen `netProfit` y `fees`, `leverage=1`, `parentPositionId=0`. Hubo **2 cierres parciales** del mismo instrumento el mismo día: son filas separadas. |

**Bugs del mapeo que encontró la prueba (para la FASE 2)**

1. **No se puede decidir "fuera de EE.UU." por el punto en el símbolo.** Una acción de Nasdaq viene
   como `XXXX.US`, con sufijo, y quedó mal clasificada como "aparte". Además, `BRK.B`, de NYSE
   (aparece en el historial), habría caído en la misma regla. **Regla correcta:** decidir por
   `exchangeID`/`exchangeDescription` (Nasdaq, NYSE…), sacar el sufijo `.US` del símbolo y dejar las
   clases de acciones (`.B`) como las maneja Porty (Yahoo `BRK-B`).
2. **Hay que resolver la metadata de los instrumentos del historial**, no solo de las posiciones
   abiertas. Corregido en el script.
3. Hay que validar, al mapear, que **cada ticker importado tenga cotización en Finnhub/Yahoo**. En la
   prueba apareció un símbolo de Nasdaq poco común. Si no cotiza, va a "aparte" con el motivo
   "Porty no tiene precio para este activo".

**Sin cubrir en esta cuenta:** CFD, apalancadas, cortas, copy trading y cripto (no había ninguna).
Esos casos siguen cubiertos solo por el fixture sintético y por la spec.

## 0. Cómo se hizo y qué tan confiable es cada dato

El entorno donde trabajé **bloquea los dominios de eToro** (`www.etoro.com`, `api-portal.etoro.com`,
`builders.etoro.com`, `public-api.etoro.com`): la política de red respondió 403 a todos. No pude
abrir las páginas oficiales ni hacer la prueba real con la cuenta demo (ver §5). Fuentes que usé,
de más a menos confiable:

| Marca | Fuente | Qué es |
|---|---|---|
| **[OAS]** | OpenAPI oficial `eToro Api v1.244.0` (servidor `https://public-api.etoro.com`), copia publicada por API Evangelist el 2026-10-04 en [github.com/api-evangelist/etoro](https://github.com/api-evangelist/etoro) (`openapi/_original/openapi.json`) | Es el archivo de eToro, sin modificar, pero es una copia de terceros. Las descripciones de los campos son de eToro. |
| **[PLG]** | Plugin oficial de eToro para Cursor, [github.com/eToroBuilders/etoro-cursor-plugin](https://github.com/eToroBuilders/etoro-cursor-plugin) (autor `apisupport@etoro.com`, último commit 2026-05-06) | Reglas y guías que eToro escribió para desarrolladores: OAuth, identidad, rate limits, semántica de los campos. |
| **[SNIP]** | Fragmentos de páginas oficiales (api-portal, builders, PDF de términos) que devolvió el buscador | Texto oficial, pero **parcial**: no leí las páginas completas. |
| **[3P]** | Proyectos de terceros (PRs de `cursor/plugins`, conectores MCP en GitHub) | Pruebas reales que hizo otra gente, sin aval de eToro. |

**Todo lo que diga [SNIP] o [3P] hay que confirmarlo** en las páginas oficiales antes de la FASE 2.
Para eso, el entorno tiene que permitir esos dominios, o lo revisás vos desde tu navegador.

### Correcciones a lo que traías

1. **Las posiciones de Porty no están solo en el dispositivo.** Hoy `PositionRepositoryImpl` usa
   `PositionSupabaseDataSource` (tabla `positions` en Supabase,
   `lib/infraestructure/data_sources/supabase/position_supabase_data_source.dart`), y lo mismo
   pasa con las cerradas (`closed_positions`). `PositionModel`/Hive siguen en el código pero ninguna
   ruta los usa. Esto cambia el diseño para mejor: la edge function puede escribir las posiciones de
   eToro directamente en la base, y la seguridad a nivel de fila (RLS) puede hacerlas de solo
   lectura (§6). La tabla `positions` no está en `supabase/migrations/`, así que se creó a mano en
   el proyecto remoto. Antes de la FASE 2 hay que traer su esquema a una migración.
2. **El portfolio agregado para cuenta real sí existe:** `GET /api/v1/trading/info/aggregate-portfolio` [OAS].
3. **Las URLs de OAuth no coinciden con las tuyas.** El plugin oficial usa
   `https://www.etoro.com/sso/oauth2/authorize` (en otro lugar dice `https://www.etoro.com/sso/`)
   para autorizar, `https://www.etoro.com/sso/oidc/token` para el token y
   `https://www.etoro.com/sso/v1/revoke` para revocar [PLG]. Un tercero vio el registro dinámico en
   `https://www.etoro.com/api/sso/v1/register` [3P]. La `…/api/sso/v1/token` que mencionás puede
   existir también. Se resuelve leyendo el `/.well-known/openid-configuration` del SSO cuando haya red.
4. **Scope del endpoint demo agregado:** en la spec, los scopes `etoro-public:trade.demo:read` y
   `trade.real:*` aparecen solo para los *user tokens* de agent-portfolios [OAS]. Para OAuth, la spec
   y `/api/v1/me` muestran `etoro-public:real:read`, `etoro-public:demo:read`,
   `etoro-public:real:write`, `etoro-public:demo:write`, `etoro-public:user-info:read` y
   `etoro-public:money.balance:read` [OAS]. En la copia de la spec que leí se perdió el mapeo exacto
   de scope por endpoint en los endpoints de trading (dicen `bearerAuth` sin lista).

---

## 1. Autenticación

### 1.1 Dos métodos que no se pueden mezclar [OAS][PLG]

- `Authorization: Bearer <access_token>` (OAuth), **o**
- `x-api-key` + `x-user-key`.

Si mandás los dos, la API rechaza el pedido. Todas las llamadas llevan `x-request-id` (un UUID v4
nuevo en cada pedido) [PLG].

### 1.2 OAuth: ¿una app de terceros puede registrarse?

**Sí, pero pasando por eToro.** Lo que encontré:

- **Registro con revisión.** La página *App Registration & Integration Access* dice que el registro
  se pide para *"production-grade integration, identity flows for third-party users, SSO-style OAuth,
  or partner-level access"* y que *"aligns your client with eToro's security review, redirect URI
  allowlists, and program terms"*. Piden URIs de redirección exactas en HTTPS, nombre y descripción
  de la app, un contacto técnico, los scopes y productos de API que vas a usar, y material de prueba
  (URL de staging o video) [SNIP: builders.etoro.com/app-registration]. Otra página oficial dice:
  *"For OAuth-based authentication (used in partner and enterprise integrations), please contact the
  eToro partnerships team"* [SNIP: builders.etoro.com/learn/authentication-and-api-keys].
  **No encontré plazos publicados para la revisión.**
- **Registro dinámico de clientes (DCR).** Existe y otros lo usan: el servidor MCP oficial de eToro
  (`mcp.public-api.etoro.com`) registra clientes públicos sin `client_secret` (`token_endpoint_auth_method:
  none`), con PKCE S256, y les da scopes `etoro-public:*`. Prueba del 2026-09-22 en
  [cursor/plugins#410](https://github.com/cursor/plugins/pull/410) [3P]. **Pero las URIs de
  redirección tienen lista blanca:** el 2026-09-29, `https://www.cursor.com/bot/mcp/oauth/callback` y
  `grokbot://mcp/oauth/callback` dieron `400 invalid_redirect_uri` y quedaron esperando que eToro las
  habilite ([cursor/plugins#461](https://github.com/cursor/plugins/pull/461)) [3P]. Conclusión: en la
  práctica, eToro tiene que habilitar la redirección de Porty, y usar el DCR "por la puerta de
  atrás" para una app comercial chocaría con los términos (§3). **No es un camino válido sin el
  OK de eToro.**

### 1.3 PKCE para móvil: sí

*"PKCE is recommended for all clients and required for public clients (SPA / mobile)"* [PLG,
skill `implementing-etoro-sso`]. En el diseño propuesto (§6), el intercambio del código lo hace el
servidor, así que Porty sería un cliente confidencial con PKCE además del `client_secret`.

### 1.4 Duración de los tokens

- **Access token:** no hay duración publicada. El plugin dice `expires_in: (varies)`, el token es un
  JWT de unas 2130 letras [PLG] y una guía de builders dice *"access tokens are short-lived"* [SNIP].
  Se lee de `expires_in` en cada respuesta.
- **Refresh token:** se pide con el scope `offline_access` [PLG]. **Rota en cada refresco:** *"Every
  successful refresh … returns a NEW refresh token; the previous one is immediately invalidated"*.
  Si no se guarda el nuevo, el próximo refresco da `400 invalid_grant` [PLG, regla `etoro-sso-identity` §4].
  **No hay duración publicada.** Además, eToro puede revocarlo por su cuenta en cualquier momento
  (política de sesión, rotación interna, sospecha de abuso) [PLG, skill `handling-etoro-session-expiry`].
- **Revocación:** `POST https://www.etoro.com/sso/v1/revoke`, que da 400 si el token ya estaba
  revocado, así que hay que tratarla como "si sale, bien" [PLG].
- **Identidad:** no usar el `sub` del id_token, porque cambia según el cliente OAuth. Usar `gcid` de
  `GET /api/v1/me`, que además devuelve `realCid`, `demoCid` y **los scopes que tiene el token** [OAS][PLG].

### 1.5 ¿Se pueden pedir solo scopes de lectura?

**Sí, técnicamente.** Los scopes de lectura y de escritura son distintos (`etoro-public:real:read`
y `etoro-public:real:write`), y el scope lo pide la app en la URL de autorización. Como los scopes
efectivos vuelven en `/api/v1/me`, Porty puede **comprobar después de cada conexión que el token no
trae ningún `:write`**. Si trae uno, revoca el token y aborta. El script de §5 ya hace esta
comprobación. Lo que no pude confirmar: si eToro le muestra al usuario solo los scopes pedidos o
si, en algún programa, entrega scopes de más (el DCR de terceros recibió `etoro-public:*`).
Lo preguntaríamos en el registro.

### 1.6 Plan B: el usuario pega sus claves

- **Hay claves de solo lectura.** En *Settings → Trading → API Key Management* el usuario elige el
  entorno (Real o Demo; cada clave sirve para uno solo), el permiso (**Read** o **Write**), una lista
  de IPs opcional y un vencimiento opcional. Lo confirma por SMS y la *User Key* se muestra una sola
  vez. Requiere cuenta verificada (KYC) [SNIP: api-portal.etoro.com/core/getting-started/authentication,
  *"Read if you only need to access your portfolio data, and Write if you need to execute trades"*;
  coincide con [3P]: pdhimate/etoro-mcp-connector, slemos/etoro-mcp-server].
- Porty podría **rechazar claves con permiso de escritura** comprobándolo en `/api/v1/me` (un tercero
  ya lo hace) [3P].
- La lista de IPs no ayuda con Supabase, porque las edge functions salen por IPs variables.
- **Riesgos que hacen que no lo recomiende sin el OK de eToro:**
  1. Los términos dicen que las credenciales son confidenciales y que *no* se pueden compartir ni
     transferir (§3). Que el usuario pegue sus claves en Porty probablemente choca con eso, **del lado
     del usuario**.
  2. Los términos excluyen del uso permitido *"use on behalf of third parties"* (§3).
  3. Si un usuario se equivoca y pega una clave Write, Porty la rechaza, pero esa clave igual viajó
     y pasó por nuestro servidor.
  4. El plugin oficial describe `x-api-key` como *"partner key"* y `x-user-key` como *"per user key"*
     [PLG]. Puede existir un modelo de partner donde Porty tenga su propia `x-api-key` y el usuario
     solo aporte la suya. No está documentado públicamente y habría que preguntarlo.

**En claro:** las claves de solo lectura existen, así que el riesgo de trading se puede eliminar.
Lo que queda en duda es si los términos permiten que el usuario se las dé a Porty.

---

## 2. Endpoints para cuenta REAL

Base: `https://public-api.etoro.com`. **Rate limit:** 60 GET por minuto por usuario, en ventana móvil
de 1 minuto. Es una cuota compartida entre todos los endpoints que no tienen límite propio. Si se
pasa, devuelve 429 con `Retry-After` y `X-RateLimit-*` [SNIP: api-portal …/rate-limits, *"60
requests per 60 seconds … default shared quota"*; [3P] mirror rate-limits.yml]. Las escrituras
tienen 20 por minuto, lo que no nos afecta. Ojo: la guía de builders pone "user trade info" en la
categoría de 20 por minuto, lo que contradice lo anterior [SNIP]. Hasta confirmarlo, planificamos
con 20 por minuto para el historial.

| Necesidad | Endpoint | Notas |
|---|---|---|
| Identidad + scopes | `GET /api/v1/me` | `gcid`, `realCid`, `demoCid`, `scopes[]` [OAS] |
| **Posiciones individuales** (una por lote) | `GET /api/v1/trading/info/real/pnl` → `clientPortfolio.positions[]` | La fuente principal. Trae `positionID`, `instrumentID`, `openDateTime`, `openRate` (**en la moneda del activo**), `units`, `amount` (USD), `leverage`, `isBuy`, `mirrorID`, **`settlementTypeID` (0 CFD, 1 Real Asset, 2 SWAP, 3 Crypto MarginTrade, 4 Future)**, `initialUnits`, `isPartiallyAltered`, `openConversionRate` y `unrealizedPnL{…}` [OAS]. La respuesta se cachea unos 10 s [PLG]. Las posiciones de copy aparecen **dos veces**: en `positions[]` con `mirrorID>0` y en `mirrors[].positions[]`. Se usa solo una de las dos [PLG]. |
| Posiciones agregadas por activo | `GET /api/v1/trading/info/aggregate-portfolio` (`instrumentIds`, `mirrorIds`, `conversionMode`) | `accountCurrency`, `accountTotals{availableCash, balance, totalValue…}`, `instrumentAggregates[]{instrumentId, assetCurrency, netUnits, avgOpenRate, avgLeverage…}`, `mirrors[]` [OAS]. **No trae fecha de compra ni tipo de liquidación**, así que no sirve para el mapeo por lote. Sirve para el chequeo de totales y la moneda de la cuenta. |
| Alternativa "todo en uno" | `GET /api/v1/trading/info/portfolio` | Lo mismo que `pnl`, sin el P&L [OAS]. |
| **Historial de cerradas** | `GET /api/v1/trading/info/trade/history?minDate=YYYY-MM-DD&page=&pageSize=` | Devuelve una lista con `positionId`, `instrumentId`, `isBuy`, `leverage`, `openRate`, `openTimestamp`, `closeRate`, `closeTimestamp`, `units`, `investment`, `initialInvestment`, `fees`, `netProfit`, `parentPositionId` y `socialTradeId` [OAS]. **No trae `settlementTypeID` ni `mirrorID`.** El plugin dice que con credenciales demo devuelve `InsufficientPermissions` [PLG]. La guía de builders usa otra ruta, `/trading/info/real/history` con `limit/startDate/endDate`, y hay que confirmar cuál está vigente [SNIP]. |
| Cash y moneda | `aggregate-portfolio.accountCurrency` y `accountTotals.accountAvailableCash`; `clientPortfolio.credit` (USD); `GET /api/v1/balances` (scope `etoro-public:money.balance:read`, `displayCurrency`) | [OAS] |
| **instrumentId → símbolo/nombre/tipo/exchange** | `GET /api/v1/market-data/instruments?instrumentIds=1,2,3` | Devuelve `instrumentDisplayDatas[]{instrumentID, instrumentDisplayName, symbolFull, instrumentTypeID, exchangeID, priceSource, images[]…}` [OAS]. Hay que pedirlos **en lotes de 25 a 50**: si mandás más, da 413/414. La lista va con **coma literal**, no `%2C` [PLG]. |
| Catálogos | `GET /api/v1/market-data/instrument-types`, `GET /api/v1/market-data/exchanges` | Se cachean globalmente por 24 h o más [PLG] |

**Costo por sincronización** (un usuario con N instrumentos): `me` + `pnl` + `ceil(N/50)` de
metadata (de caché, casi siempre) + `history` (1 a 2 páginas) = **unas 4 a 5 llamadas**. Queda muy
por debajo de 60 por minuto.

---

## 3. Términos

Documento: **"eToro Builders' Economy — Public API & eToro App Store — Terms of Use"**, BETA, fecha
17-Feb-2026, firmado por eToro Group Trading Ltd.
(<https://www.etoro.com/wp-content/uploads/2026/03/Master_eToro_Builders_Economy_Terms_17-Feb-2026-clean_R.pdf>).
Hay además una *Risk Disclosure* (<https://www.etoro.com/wp-content/uploads/2026/03/eToro-App-Store-Risk-Disclosure.pdf>).

> ⚠️ **No pude leer el PDF completo**: el dominio está bloqueado acá. Lo que sigue son
> **fragmentos textuales que devolvió el buscador**, sin número de cláusula. Alguien tiene que leer
> el documento entero y ubicar cada cláusula. No saco conclusiones legales.

**Lo que dice (textual, en inglés):**

| Tema | Texto encontrado |
|---|---|
| Uso permitido | El uso permitido se limita a gestionar *la propia* cuenta de eToro y armar herramientas personales. Publicar para otros usuarios de eToro vía App Store solo *"where expressly authorized"*. Excluye *"any commercial redistribution of eToro data or use on behalf of third parties or other uses prohibited under this Agreement"*. |
| Uso de herramientas | *"use any tool made available to you solely for the Permitted Use and in accordance with all applicable laws, regulations, and any applicable third-party tools terms"*. Cualquier otro uso requiere autorización escrita de eToro. |
| Sujeción | El uso permitido queda sujeto a *"the General Terms and Conditions of the relevant regulated eToro entity governing your Trading Account"*. |
| Credenciales | Las *Access Credentials* son confidenciales: *must not share, sell, or transfer them*. Si se comprometen, hay que avisar a eToro dentro de *"twenty-four (24) hours"* y rotarlas. |
| Al terminar | Hay que borrar *"all API keys, documentation, and derivative materials"*, entre otras cosas. |
| Propiedad | *"eToro and its licensors retain all rights in and to … the Public API, the Licensed Information and related data."* |
| Cobro (App Store) | eToro *"may, at its sole discretion"* permitir que los *Publishers* cobren por las *Listed Tools*. Cualquier cobro está *"subject to eToro's prior consent and must be fully disclosed to users before purchase; Hidden pricing is prohibited"*. |
| Publishers | Garantizan que la herramienta *"will not violate any third-party rights (including intellectual property, privacy, and publicity rights)"*. |
| Revocación | eToro puede *"remove your application from the App Store or revoke your API access at any time — including for regulatory reasons or breaches of the App Store Terms — without liability to you"*. Eso puede dejar la app sin funcionar *"for all its users"* (Risk Disclosure). |
| Privacidad | Las apps de terceros se rigen por *la política de privacidad del desarrollador*, no por la de eToro (Risk Disclosure). La política de eToro no cubre apps de quienes no son empleados de eToro. |
| No asesoramiento | Las herramientas no son asesoramiento de inversión ni gestión de cartera (MiFID II, US Securities Exchange Act, entre otros). |
| Seguridad (guía, no contrato) | *"your backend stores refresh tokens securely"*; no meter claves en el código ni en git [SNIP builders]. |

**Lo que no queda claro y alguien que sepa tiene que revisar:**

1. Si Porty, una app **comercial**, **externa al App Store de eToro** y con usuarios que **no son el
   desarrollador**, entra en el "uso permitido" o necesita la autorización expresa o escrita que
   mencionan los términos (por ejemplo, un acuerdo de partner).
2. Si cobrar una suscripción de Porty que incluya la función de eToro cuenta como un *fee* que
   requiere el consentimiento previo de eToro, aunque no estemos en su App Store.
3. Si guardar en nuestra base las posiciones y el historial que vienen de eToro (y mostrarlos en
   Porty) es *redistribución*, o si es uso legítimo en nombre del propio usuario.
4. **Si mandar esas posiciones a OpenAI**, como hace hoy el asistente con el portfolio, choca con
   *"commercial redistribution of eToro data"* o *"on behalf of third parties"*. Este punto es nuevo
   y concreto, porque el asistente de Porty ya hace eso con las posiciones manuales.
5. Si que el usuario nos dé sus claves (plan B) viola su deber de no compartir credenciales.
6. Qué retención y borrado de datos se exigen cuando el usuario desconecta o cuando termina el
   acuerdo con eToro.
7. Obligaciones de seguridad concretas para un partner OAuth (más allá del aviso de 24 h).
8. Ley aplicable y la entidad regulada que corresponde según el país del usuario.

---

## 4. Mapeo al modelo de Porty

Porty hoy: `Position{ticker, quantity, purchasePrice, purchaseDate}` (cada fila es un lote) y
`ClosedPosition{ticker, quantity, avgPurchasePrice, closePrice, closeDate}`. Todo en USD, y las
cotizaciones vienen de Finnhub/Yahoo con tickers de EE.UU. `toYahooFinanceSymbol` cambia `.` por
`-`, así que `BP.L` se convertiría en `BP-L`, que es un ticker incorrecto.

**Mapeo directo** (fuente: `pnl.positions[]`): `ticker = symbolFull`, `quantity = units`,
`purchasePrice = openRate`, `purchaseDate = openDateTime`, más `source='etoro'` y
`external_id = positionID`.

**Regla general:** solo se importa como posición normal lo que Porty puede representar **sin
deformarlo**. Lo demás se muestra aparte o no se importa, siempre con un aviso al usuario.

| Tipo en eToro | Cómo se detecta | Propuesta |
|---|---|---|
| Acción/ETF de EE.UU., sin apalancamiento, comprada (activo real) | `settlementTypeID=1`, `leverage=1`, `isBuy`, `mirrorID=0`, tipo Stocks/ETF, exchange de EE.UU. | **Importar directo.** |
| Fracciones | `units` con decimales | **Importar directo** (`quantity` ya es `double`). |
| Varias compras del mismo activo | una fila por `positionID` | **Un lote de Porty por posición de eToro**, con su fecha y precio. No se promedian. Se resuelve solo. |
| Cerrada parcialmente | `isPartiallyAltered`, `units < initialUnits` | Se importa lo que queda abierto (`units`). La parte vendida aparece en el historial. |
| CFD sin apalancamiento y comprado | `settlementTypeID=0`, `leverage=1`, `isBuy` | **Aparte** ("Tenés X en CFD: no es propiedad del activo"). El precio y la cantidad son reales, pero no es tenencia. Si querés que cuente como posición, es una decisión tuya. |
| Apalancada | `leverage>1` | **No importar.** Aviso: "Las posiciones apalancadas no se pueden mostrar bien en Porty". `amount/units` es margen y no precio [PLG]. |
| En corto | `isBuy=false` | **No importar.** Mismo aviso. |
| Copy trading / Smart Portfolios | `mirrorID>0` (y `mirrors[]`) | **Aparte.** Un bloque "Copy: @trader / Smart Portfolio" con el valor y el P&L del mirror. No se mezcla con la cartera propia, porque Porty no gestiona esas decisiones y `positions[]` + `mirrors[]` las duplicarían [PLG]. Los Smart Portfolios también son mirrors. |
| Cripto | tipo Crypto. Con `settlementTypeID=1` es real; con 0 o 3 es CFD o margin | **Aparte en v1.** Porty no cotiza cripto hoy. Se puede activar más adelante mapeando `BTC → BTC-USD` en Yahoo (decisión tuya). |
| Materias primas, índices, divisas | tipos Commodities/Indices/Currencies (en eToro son CFD) | **No importar** (o listarlas aparte solo como información). |
| Acción no listada en EE.UU. (`BP.L`, `SAP.DE`, variantes `.RTH`/`.EUR`) | sufijo en `symbolFull` / `exchangeID` | **Aparte en v1.** `openRate` viene en moneda local (en peniques para LSE) [PLG], y Porty no tiene monedas ni tickers de fuera de EE.UU. Lo correcto es filtrar por `exchangeID`. El sufijo sirve como respaldo. |
| Moneda de la cuenta ≠ USD | `aggregate.accountCurrency` | **No afecta** a las acciones de EE.UU.: `openRate` está en la moneda del activo (USD) y `units` no depende de la cuenta. Solo afecta al cash y a los totales, que Porty hoy no muestra. Se avisa una vez: "Tu cuenta de eToro está en EUR; Porty muestra todo en USD". |
| Cash | `accountAvailableCash` / `credit` | **No se importa en v1** (Porty no tiene el concepto). Opcional: una tarjeta informativa "Efectivo en eToro". |
| Órdenes pendientes | `orders[]`, `ordersForOpen[]` | No se importan. |

**Cerradas** (fuente: `trade/history`): `ticker` (vía metadata), `quantity = units`,
`avgPurchasePrice = openRate`, `closePrice = closeRate`, `closeDate = closeTimestamp`, más
`external_id = positionId`. Problemas:

- El historial **no dice si la operación fue CFD o activo real**, ni si venía de un mirror. Solo se
  puede filtrar por `leverage=1`, `isBuy=true`, `parentPositionId=0` (no copiada) y el tipo de
  instrumento. Para acciones de EE.UU. sin apalancamiento, el precio y la cantidad son correctos aunque
  haya sido CFD, pero esto **hay que validarlo con datos reales**.
- Porty calcula el P&L como `(close − open) × qty`, mientras que `netProfit` de eToro descuenta
  comisiones y dividendos. Van a diferir un poco. Opciones: (a) mostrar el de Porty con la nota
  "sin comisiones", o (b) agregar `realizedPnlOverride` al modelo. Decisión tuya.
- ¿Desde cuándo? `minDate` es obligatorio. Propuesta: todo el historial en la primera importación
  (paginado) y después, en cada sincronización, desde la última fecha de cierre importada.
- Si con la cuenta demo el endpoint devuelve `InsufficientPermissions` [PLG], **las cerradas no se
  pueden verificar sin una cuenta real**.

---

## 5. Prueba con cuenta DEMO

**Estado: bloqueada por la red del entorno.** `public-api.etoro.com` da 403 en el proxy de salida.
El script está listo y validado sin red.

- Script: `docs/superpowers/research/2026-10-08-etoro-probe/etoro_demo_probe.py`. Usa solo la librería
  estándar de Python y se puede borrar después.
  - Solo puede hacer GET: no existe ningún método para otro verbo.
  - Llama a `/api/v1/me` y **corta (exit 2) si la clave tiene cualquier scope `:write` o de la cuenta
    real**. Probado.
  - Después llama a `demo/pnl`, `demo/aggregate-portfolio`, `market-data/instruments` (en lotes de
    50), `instrument-types` y `trade/demo/history`. Clasifica cada posición (importar, aparte o saltar,
    con el motivo) y arma el `Position` de Porty.
  - La salida va anonimizada: no incluye CIDs ni usernames, y reemplaza `positionID` por un hash con sal.
  - Las claves se leen solo de `ETORO_API_KEY` / `ETORO_USER_KEY` y nunca se imprimen.
- Validado con los ejemplos oficiales de la spec y con un fixture sintético de 11 posiciones
  (`synthetic/bundle.json` → `synthetic/output.json`):

```
import   AAPL  stock_or_etf_real_unleveraged  {ticker: AAPL, quantity: 10,    purchasePrice: 180.0,  purchaseDate: 2025-03-10T14:31:00Z, source: etoro}
import   AAPL  stock_or_etf_real_unleveraged  {ticker: AAPL, quantity: 5,     purchasePrice: 210.0,  purchaseDate: 2026-01-05T15:00:00Z, source: etoro}
import   SPY   stock_or_etf_real_unleveraged  {ticker: SPY,  quantity: 0.137, purchasePrice: 510.25, purchaseDate: 2026-04-01T13:30:00Z, source: etoro}
separate TSLA  not_owned_cfd
separate BTC   crypto_pending_decision
separate BP.L  non_us_listing
separate MSFT  copy_trading
separate GOLD  not_owned_cfd
skip     TSLA  leveraged
skip     AAPL  short
skip     EURUSD leveraged
history  403 InsufficientPermissions (simulado, según la advertencia del plugin)
```

**Para correrlo de verdad hace falta una de estas dos cosas:**

1. Habilitar en la configuración del entorno (Network access → Allowed domains) los dominios
   `public-api.etoro.com`, y de paso `www.etoro.com`, `api-portal.etoro.com` y `builders.etoro.com`
   para leer la documentación y los términos. Después me pasás las claves; **o**
2. Correrlo vos en tu máquina:
   `ETORO_API_KEY=… ETORO_USER_KEY=… python3 -I etoro_demo_probe.py --live` y pegarme la salida,
   que ya sale anonimizada.

Claves a generar: entorno **Demo**, permiso **Read**, con vencimiento corto (por ejemplo, 7 días).
Borralas al terminar.

---

## 6. Arquitectura propuesta (solo diseño)

```
App (Flutter) ──JWT──▶ edge fn `etoro-sync` ──Bearer──▶ public-api.etoro.com
      ▲   ▲                  │   ▲                      www.etoro.com/sso (token/refresh/revoke)
      │   └─ deep link ◀─────┘   │
      │      (sin tokens)        └── Vault (tokens cifrados) + tablas etoro_*
      └── lee `positions` (source='manual'|'etoro') como hoy
```

### 6.1 Almacenamiento

- **Tokens:** en **Supabase Vault** (`vault.create_secret` / `vault.update_secret`), un secreto por
  usuario que guarda `{access_token, refresh_token, expires_at}`. Solo se accede con funciones
  `security definer`, con `EXECUTE` dado únicamente a `service_role`. Los roles `anon` y
  `authenticated` no tienen acceso a `vault.decrypted_secrets`. **Los tokens no llegan nunca al
  dispositivo ni a los logs**: el logger de la función tapa `Authorization`, `code`, `refresh_token`
  y `x-user-key`.
- **`etoro_connections`** (una fila por usuario): `user_id` (PK), `gcid`, `real_cid`, `status`
  (`connected | syncing | reconnect_required | disconnected`), `granted_scopes text[]`,
  `account_currency`, `vault_secret_id`, `connected_at`, `last_sync_at`, `last_sync_status`,
  `last_error_type`, `skipped_summary jsonb` (lo que no se importó y por qué). RLS: el usuario solo
  puede leer su fila. No puede escribirla.
- **`etoro_oauth_states`** (vida corta, 10 min): `state`, `user_id`, `code_verifier` y `created_at`.
  El PKCE vive en el servidor.
- **`etoro_instruments`** (caché global, TTL de 24 h): `instrument_id`, `symbol_full`, `name`,
  `type_id`, `exchange_id` y `updated_at`.
- **`positions` / `closed_positions`:** columnas nuevas `source text not null default 'manual'
  check (source in ('manual','etoro'))`, `external_id text`, `synced_at timestamptz` y
  `unique (user_id, source, external_id)`. **La RLS hace el "solo lectura":** las políticas de
  insert, update y delete del usuario exigen `source = 'manual'`, así que nadie puede editar ni
  cerrar una posición de eToro desde la app, aunque la UI fallara. Solo la edge function (con
  service role) escribe filas con `source = 'etoro'`.

### 6.2 Edge function `etoro-sync`

Sigue el patrón actual (`_shared/common.ts`, `Deps` inyectables y tests sin red).

| Ruta | Qué hace |
|---|---|
| `POST /connect/start` | Requiere JWT y plan habilitado. Genera `state` y `code_verifier`, los guarda y devuelve la URL de autorización con `scope=openid offline_access etoro-public:real:read` (más `etoro-public:user-info:read` si `/me` lo pide). |
| `GET /callback` | Es la URL HTTPS registrada en eToro: `https://<proyecto>.supabase.co/functions/v1/etoro-sync/callback`. Valida `state`, intercambia el código (form-urlencoded) y llama a `/me`. **Si `scopes` trae algo `:write`, revoca el token y termina con `error=write_scope`.** Si no, guarda en Vault, hace la primera sincronización y responde **302 al deep link** `porty://etoro/connected?result=ok\|error&reason=…`. Ni tokens ni códigos van en el deep link. |
| `POST /sync` | Requiere JWT. Aplica un throttle en el servidor (mínimo 5 min entre sincronizaciones; si no pasó el tiempo, devuelve el último resultado guardado). Refresca el token si `expires_at` está a menos de 60 s, con **un solo refresco por intento**. Llama a `pnl` → metadata (de caché) → `history` incremental. Mapea y hace *upsert* de las filas `etoro` por `external_id`; **borra las filas `etoro` que ya no vienen** (posiciones cerradas en eToro) y suma las cerradas nuevas. Devuelve `{imported, separate[], skipped[], possibleDuplicates[], lastSyncAt}`. |
| `GET /status` | Estado de la conexión para la UI. |
| `POST /disconnect {keepAsManual}` | Revoca en eToro (si falla, sigue igual), borra el secreto de Vault y marca `disconnected`. Si `keepAsManual`, hace `update positions set source='manual', external_id=null`. Si no, borra las filas `etoro`. |

**Carrera al refrescar:** como el refresh token rota, dos sincronizaciones simultáneas (dos
dispositivos, o abrir la app y pull-to-refresh) podrían invalidarse entre sí y mostrar un
`invalid_grant` falso. Para evitarlo, se toma un lock por usuario (`select … for update` sobre
`etoro_connections`, o `pg_advisory_xact_lock`) y se lee el secreto **dentro** del lock. El token
nuevo se persiste antes de soltarlo.

**Errores tipados** para la app: `etoro_reconnect_required` (`invalid_grant` o 401 después del
refresco), `etoro_rate_limited` (429, con `retryAfter`), `etoro_unavailable` (5xx o timeout),
`etoro_write_scope_rejected` y `etoro_plan_required`.

### 6.3 Convivencia con las posiciones manuales

- Las de eToro se ven igual que las manuales, con una marca discreta "eToro". No tienen editar,
  cerrar ni borrar (también bloqueado por RLS), y el detalle dice "Se actualiza desde eToro · última
  sincronización: …".
- Las manuales no cambian.
- **Duplicados** (el usuario ya había cargado AAPL a mano y también la tiene en eToro): **no se
  fusiona ni se borra nada automáticamente.** En la pantalla de resultado aparece un bloque "Posibles
  duplicados: AAPL, MSFT. ¿Las cargadas a mano son las mismas que tenés en eToro?", con una acción
  por ticker: "Borrar las manuales de AAPL" o "Son distintas, dejar ambas". Lo detectamos por ticker,
  no por cantidad. Hasta que el usuario decida, los totales cuentan las dos (es lo que el usuario
  cargó) y la tarjeta de la posición muestra un aviso discreto.

### 6.4 Cuándo se sincroniza

- Al conectar (dentro del callback).
- Al abrir la app o volver a primer plano, si `last_sync_at` tiene más de **15 min**.
- Con pull-to-refresh en Home, con el throttle del servidor de 5 min. Si no pasó el tiempo, se
  muestra "Actualizado hace 2 min" y se devuelve lo guardado.
- Sin cron en segundo plano en v1. Con 4 a 5 llamadas por sincronización contra un límite de 60 por
  minuto por usuario, sobra margen.

### 6.5 Token vencido o revocado desde eToro

Se intenta un refresco. Si da `invalid_grant`, el estado pasa a `reconnect_required`, **no se borra
nada** y la app sigue funcionando con los datos de la última sincronización. Se muestra un banner
"Reconectá tu cuenta de eToro" con un solo botón que vuelve a abrir el flujo OAuth, sin "Reintentar"
[PLG, `handling-etoro-session-expiry`]. Al reconectar se escribe sobre la misma fila (por `gcid`).
Si el `gcid` nuevo no coincide con el anterior (otra cuenta de eToro), se avisa al usuario y se
reemplazan las filas `etoro`.

### 6.6 Qué plan incluye esto (propuesta: decidís vos)

**Premium y Gold.** El Free tiene un límite de 10 posiciones, y una cartera importada lo pasa
fácil. Además, sincronizar tiene un costo de servidor y de cumplimiento. En Free se ve "Conectar
eToro" con el paywall. Alternativa: solo Gold, si querés que sea un diferencial fuerte. **Ojo:** si
los términos exigen el consentimiento de eToro para cobrar (§3, punto 2), esto depende de esa
respuesta.

### 6.7 Cambios en la política de privacidad (`portfolioai.app/privacy`)

- **Datos nuevos:** identificadores de eToro (`gcid` y `realCid`), posiciones e historial de
  operaciones traídos de eToro, la moneda de la cuenta y los scopes concedidos. Los tokens OAuth se
  guardan cifrados y no se usan para operar.
- **Finalidad y base legal:** mostrar la cartera en Porty, con el consentimiento explícito del usuario
  al conectar. Explicar que el acceso es **solo de lectura** y que Porty no puede operar.
- **Encargados:** Supabase (alojamiento y Vault). **OpenAI**, si las posiciones importadas se usan en
  el asistente (ver §3, punto 4). eToro como fuente de los datos.
- **Retención:** los tokens se borran al desconectar. Las posiciones se borran o se convierten en
  manuales según elija el usuario. Las cuentas inactivas se purgan después de N meses.
- **Derechos:** desconectar en cualquier momento desde Porty y también desde eToro, y borrar la cuenta.
- **Seguridad:** cifrado en reposo, sin tokens en el dispositivo, y aviso de incidentes (eToro pide
  24 h para credenciales comprometidas).
- Aclarar que eToro no es responsable de Porty y que Porty no es asesoramiento (en línea con la
  Risk Disclosure de eToro).

---

## 7. Riesgos y preguntas abiertas

**Riesgos**

1. **Términos y autorización (bloqueante).** El "uso permitido" no parece cubrir una app comercial
   externa sin autorización expresa de eToro. Sin un acuerdo, eToro puede cortar el acceso a todos
   los usuarios de golpe.
2. **Datos de eToro en OpenAI** (asistente): puede chocar con "redistribución" o con el uso "on behalf
   of third parties".
3. **Plazos de eToro desconocidos:** el programa está en beta y no tiene SLA de revisión publicado.
4. **Redirección para móvil:** eToro rechazó un esquema propio (`grokbot://`) en el DCR. Nuestro
   diseño usa un callback HTTPS de Supabase, que lo evita, pero tiene que estar en su lista blanca.
5. **Historial ambiguo:** no se distingue CFD de activo real, y quizá no se puede probar con demo.
6. **Rotación del refresh token:** si la persistencia no es atómica, los usuarios quedan
   desconectados al azar. Está mitigado con el lock de §6.2.
7. **Cambios en la API:** la spec está en `v1.244`, con rutas que se contradicen entre builders y
   api-portal y campos marcados como "Obsolete".
8. **Expectativa del usuario:** muchas carteras de eToro son mayormente CFD o copy. Para ellas,
   "Importamos 2 de 15" puede decepcionar. La pantalla de resultado tiene que explicar bien qué se
   dejó afuera y por qué.

**Preguntas para vos**

1. ¿Avanzamos con el contacto formal con eToro (partnerships / `apisupport@etoro.com`) para registrar
   Porty como cliente OAuth y pedir la autorización de uso comercial? ¿Quién lo firma?
2. Mientras tanto, ¿descartamos del todo el plan B (claves pegadas), o lo querés como beta cerrada solo
   si eToro lo aprueba por escrito?
3. CFD largos sin apalancamiento: ¿aparte (mi propuesta) o importados con una marca "CFD"?
4. Cripto real: ¿aparte en v1 o activamos `BTC → BTC-USD` en Yahoo?
5. Cerradas: ¿P&L de Porty sin comisiones, o agregamos el `netProfit` de eToro al modelo?
6. Copy trading / Smart Portfolios: ¿un bloque aparte con el valor del mirror, o no mostrarlos?
7. Plan: ¿Premium y Gold, o solo Gold?
8. ¿Las posiciones de eToro entran al asistente (OpenAI)? Lo recomiendo **solo** después de que eToro
   lo confirme.
9. ¿Habilitás los dominios de eToro en el entorno, o corrés vos el script con la clave demo?

---

## Resumen (cierre de la FASE 1)

- **¿Es viable con OAuth de solo lectura?** **Técnicamente sí.** eToro tiene OAuth con
  authorization code + PKCE, refresh tokens con rotación, scopes de lectura separados de los de
  escritura (`etoro-public:real:read`), un endpoint `/api/v1/me` para verificar los scopes concedidos,
  y endpoints de cuenta real para posiciones por lote (`/trading/info/real/pnl`, con
  `settlementTypeID` para separar CFD de activo real), agregado, historial y metadata de
  instrumentos. Todo entra holgado en 60 req/min.
- **Lo que no se puede saltear:** registrar Porty como cliente OAuth con eToro (revisión de seguridad,
  lista blanca de redirecciones, scopes) y, sobre todo, una **autorización expresa de uso comercial
  para terceros**. Los términos (beta, 17-feb-2026) limitan el uso permitido a la propia cuenta,
  excluyen el uso "on behalf of third parties" y la redistribución comercial, y piden consentimiento
  para cobrar. **No hay plazos publicados.** Lo realista es tomarlo como una gestión de semanas, sin
  fecha garantizada, que empieza con el contacto a partnerships.
- **Plan B (claves):** existen claves **Read**, así que el riesgo de trading se elimina rechazando las
  claves con permiso de escritura. Pero darle las claves a Porty probablemente choca con el deber del
  usuario de no compartir credenciales. **No lo recomiendo sin el OK escrito de eToro.**
- **Necesito de vos:** las decisiones 1 a 9 de §7, y red hacia `public-api.etoro.com` (o que corras el
  script) para hacer la prueba demo real.
