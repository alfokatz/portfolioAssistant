# Notificaciones push y alertas de precio

**Fecha:** 2026-10-10 · **Estado:** plan, sin implementar · **Reemplaza a:** `docs/backlog/notificaciones-y-alertas-de-precio.md` (queda como antecedente) y el "Push del sábado" pendiente del informe semanal.

## Resumen

Porty empieza a hablarle al usuario cuando no tiene la app abierta. El objetivo es doble: que vuelva a la app en los momentos en que le sirve (retención) y darle algo que hoy no tiene (valor). Las dos cosas se cuidan con la misma regla: **cada notificación tiene que ser algo que el usuario agradece haber recibido.** Una sola de más y apaga todas, y en iOS eso casi nunca tiene vuelta atrás.

v1 trae cuatro tipos, que salen de datos que ya tenemos:

1. **Alertas de precio** que arma el usuario ("avisame si VOO pasa $750"). Premium ya las promete en el paywall y hoy no existen.
2. **Movimientos fuertes de la cartera**: una posición con peso que sube o baja mucho en el día, con un "Preguntale a Porty por qué".
3. **Tu semana está lista**: el informe semanal, los sábados.
4. **Avisos de servicio**: la conexión con eToro se cortó y hay que reconectarla.

Y en una fase siguiente (Gold): **earnings** de sus acciones (mañana reporta / ya reportó).

---

## 1. Principios (salen de PRODUCT.md)

PRODUCT.md define a Porty como *quiet, precise, trustworthy*, para un inversor casual, "no trader UX". Para las notificaciones eso quiere decir:

| Principio | Regla concreta |
|---|---|
| **Pocas y buenas** | Tope de **3 notificaciones automáticas por día** por usuario. Las alertas de precio que armó él no cuentan (las pidió), pero sí pasan por el filtro de duplicados |
| **Agrupar, no repetir** | Si se mueven 3 posiciones, va **una** notificación ("3 de tus acciones se mueven fuerte hoy"), no tres. Cada ticker avisa como mucho una vez por día y por dirección |
| **Respetar el descanso** | Horario de silencio por defecto 22:00–08:00 **en la hora local del usuario**. Lo que cae adentro se descarta (si es de mercado) o se corre a las 08:00 (si es el informe) |
| **Sin tono de casino** | Nada de "🚀", "¡Ahora!", "no te lo pierdas". Copy neutro: dato + contexto. Ej.: "NVDA baja 7,2% hoy. Es tu posición más grande (24%)." |
| **Sin consejos** | Nunca "comprá", "vendé", "es buen momento". Mismo criterio que el validador del informe semanal (`analysis_prose_check.dart`) |
| **Privacidad en la pantalla bloqueada** | Por defecto solo **porcentajes y tickers, nunca montos en $**. Un ajuste "Mostrar montos" lo habilita |
| **Cada notificación lleva a algo** | Abre una pantalla concreta (la posición, el informe, la lista de alertas, el chat con una pregunta cargada), nunca la Home a secas |
| **El permiso se pide cuando aporta valor** | Nunca al abrir la app por primera vez. Ver §6 |

---

## 2. Catálogo de notificaciones

### v1

| Tipo | Disparador | Ejemplo de copy | Abre | Plan |
|---|---|---|---|---|
| `price_alert` | El precio cruza el objetivo del usuario | "VOO pasó $750 (ahora $751,20). Tu alerta quedó cumplida." | Detalle de la posición o del ticker | Premium y Gold (ver decisión D1) |
| `big_move` | Una posición con peso ≥ 3% se mueve ≥ umbral en el día (§4.3) | "NVDA baja 7,2% hoy. Pesa 24% en tu cartera." | Chat con "¿Por qué se mueve NVDA hoy?" cargada | Todos (el "por qué" con noticias es Gold, como hoy en el chat) |
| `big_move_digest` | 2 o más posiciones disparan `big_move` en la misma corrida | "3 de tus acciones se mueven fuerte hoy: NVDA −7%, AMD −6%, TSM −5%." | Home con la pestaña de posiciones | Todos |
| `portfolio_move` | La cartera entera se mueve ≥ 3% en el día | "Tu cartera baja 3,4% hoy. El S&P 500 baja 2,1%." | Home | Todos |
| `weekly_report` | Sábado 09:00 hora local, si tiene posiciones | "Tu semana en Porty está lista." | `/weekly-report` | Todos (el contenido ya se gatea en el informe) |
| `etoro_reconnect` | `etoro-sync` recibe un refresh token inválido | "Se cortó la conexión con eToro. Reconectala para que tu cartera siga al día." | Pantalla de eToro | Quien tenga eToro conectado |

### Fase siguiente (Gold)

| Tipo | Disparador | Ejemplo | Fuente |
|---|---|---|---|
| `earnings_tomorrow` | Una acción de la cartera reporta mañana | "AAPL presenta resultados mañana después del cierre." | Finnhub `/calendar/earnings` (ya proxeado) |
| `earnings_result` | Salió el resultado | "AAPL presentó resultados: ganancia por acción por encima de lo esperado." | Finnhub `/stock/earnings` (ya proxeado) |

### Ideas para v2 (a priorizar con datos de v1)

| Idea | Valor | Costo / riesgo |
|---|---|---|
| **Noticias materiales** de una posición (fusión, guidance, demanda grande) | Alto | Alto riesgo de ruido. Necesita portar `NewsRelevanceRanker` al servidor y un filtro de "material" muy estricto. Mejor arrancar solo con noticias que coinciden con un `big_move` |
| **Super investors tocan una acción tuya** (13D/G, compra de un Form 4) | Alto, diferencial | Bajo: `investor-pulse` ya lo calcula. Gold |
| **Hitos de posición**: máximo de 52 semanas, +50% desde la compra, vuelve a cero después de estar en pérdida | Medio-alto, momentos positivos | Bajo. Una por posición y por hito, nunca repetida |
| **Metas**: llegaste al 50% de tu meta de ahorro | Alto para el casual | Bajo: las metas ya existen (`save_goal`) |
| **Resumen del mes** (primer día hábil) | Medio | Bajo: reusa el cálculo del informe semanal |
| **Concentración**: "tu mayor posición ya pesa 38% (era 31%)" | Alto y educativo | Bajo. Máximo una por mes |
| **Insiders de tus empresas** (directivos que compran) | Medio | Medio: Finnhub insider transactions o EDGAR |
| **Tus consultas se renovaron** (Free, a principio de mes) | Bajo-medio, reactivación | Muy bajo. Riesgo de parecer marketing; probar con cuidado |
| **Dividendos** cobrados o por venir | Medio | No hay fuente gratis |

Lo que **no** haría nunca: notificaciones de "hace días que no entrás", promos de planes por push, o movimientos de tickers que el usuario no tiene ni sigue.

---

## 3. Restricciones que salen del código (2026-10-10)

| Hecho | Dónde | Consecuencia |
|---|---|---|
| **Firebase no está configurado**: `firebase_remote_config` está en el pubspec pero nadie llama `Firebase.initializeApp`, y no hay `google-services.json` ni `GoogleService-Info.plist` | `app_update_gate.dart:18`, `remote_config_asset_loader.dart` | Hay que crear el proyecto de Firebase solo para FCM. Al inicializarlo, revisar que `RemoteConfigAssetLoader` no cambie de comportamiento |
| **No hay cron** ni `pg_cron`/`pg_net` en las migraciones | `supabase/migrations/` | Primera tarea programada del proyecto: habilitar las extensiones en una migración |
| iOS sin entitlements ni `UIBackgroundModes` | `ios/Runner/` | Capability "Push Notifications" + `remote-notification` + clave APNs (.p8) en Firebase |
| Las posiciones viven en Supabase (`positions`, con `source` manual/eToro), y el servidor ya las lee | `etoro-sync/store.ts:256` | El servidor puede evaluar movimientos de la cartera sin el teléfono. Igual que en el informe: hacer `supabase db pull` para tener su DDL en el repo |
| El plan del usuario está en el servidor (`user_subscriptions`) | `20260611000000_subscription_tiers.sql` | El gating de las alertas se valida del lado del servidor, no solo en la app |
| **Los precios hoy se piden desde el cliente** (Yahoo `v8/chart`) | `yahoo_quote_remote_data_source.dart` | Hace falta una fuente de precios del lado del servidor, en lote (§4.2) |
| El proxy de Yahoo ya maneja cookie + crumb y una caché compartida | `supabase/functions/yahoo/handler.ts` | Se reusa la sesión para `v7/finance/quote?symbols=...` (muchos tickers por pedido) |
| El patrón "interruptor en `app_config`" ya existe | `20261002130000_weekly_report_flag.sql` | Interruptor general de push y uno por tipo |
| "El modelo propone, la app ejecuta" | `docs/superpowers/plans/2026-10-08-acciones-de-porty.md` | La tool de Porty para crear alertas sigue ese patrón (card + Confirmar) |
| `plan_feature_price_alerts` se vende en Premium como `extraMarketingKey` | `plan_matrix.dart:123` | Pasa a ser una `PlanFeature.priceAlerts` real, con gating |
| No se guarda la zona horaria del usuario en ningún lado | — | Se guarda por dispositivo al registrar el token (§4.1) |

---

## 4. Arquitectura

```
                   ┌───────────── pg_cron ─────────────┐
                   │ cada 5 min (mercado)  · cada hora  │
                   ▼                                    ▼
             market-watch                         daily-jobs
   (precios en lote → alertas,          (informe del sábado, earnings,
    movimientos fuertes)                  según la hora local de cada uno)
                   │                                    │
                   └──────────► notification_outbox ◄───┘   ◄── etoro-sync (reconectar)
                                        │
                                        ▼
                                 notify-dispatch
          preferencias · horario de silencio · tope diario · duplicados · plan
          copy en es/en · FCM HTTP v1 · limpia tokens muertos · notification_log
                                        │
                                        ▼
                         FCM ──► APNs (iOS) / Android
                                        │
                                        ▼
               app: firebase_messaging → toca la notificación → go_router (deep link)
```

**Por qué un outbox:** los productores (mercado, informe, eToro) solo dicen *qué pasó*. Todas las reglas de "¿se lo mando?" viven en un solo lugar (`notify-dispatch`), así el tope diario y el horario de silencio valen para todos los tipos, y se puede reintentar un envío sin volver a evaluar el mercado.

**Por qué FCM y no APNs directo u OneSignal:** FCM manda a iOS y Android con una sola API y es gratis; APNs directo duplica el trabajo para Android; OneSignal suma un proveedor y le da los datos de los usuarios a un tercero. FCM solo necesita `firebase_core` + `firebase_messaging` y una service account en los secrets de Supabase.

### 4.1 Base de datos (migraciones nuevas)

**`push_devices`**: un token por dispositivo.

| Columna | Notas |
|---|---|
| `id`, `user_id` (FK a `auth.users`, on delete cascade) | |
| `token` text **unique** | Si el token cambia de usuario (otra cuenta en el mismo teléfono), se reasigna |
| `platform` (`ios`/`android`), `locale` (`es`/`en`), `timezone` (IANA, ej. `America/Argentina/Buenos_Aires`) | Locale y zona salen del teléfono; se actualizan en cada apertura |
| `app_build`, `last_seen_at`, `created_at` | Para limpiar dispositivos viejos (> 60 días sin abrir) |

RLS: cada usuario ve y borra solo sus filas. Alta y actualización por RPC `register_push_device(token, platform, locale, timezone, build)`; baja por `unregister_push_device(token)` al cerrar sesión.

**`notification_preferences`**: una fila por usuario (se crea con valores por defecto).

`enabled`, `price_alerts`, `big_moves`, `portfolio_moves`, `weekly_report`, `earnings`, `service` (todos `true`), `big_move_sensitivity` (`low`/`normal`/`high`, por defecto `normal`), `quiet_start` (22:00), `quiet_end` (08:00), `show_amounts` (`false`).

**`price_alerts`**

| Columna | Notas |
|---|---|
| `id`, `user_id`, `symbol` | Símbolo normalizado (el mismo que usa la app) |
| `condition` | `above`, `below`, `pct_up`, `pct_down` (porcentaje contra `reference_price`) |
| `target` numeric, `reference_price` numeric | Para `above/below`, `target` es el precio. Para `pct_*`, el porcentaje |
| `repeat` | `once` (por defecto: se cumple y queda cumplida) o `daily` (se rearma al día siguiente, con histéresis) |
| `status` | `active`, `triggered`, `paused` |
| `last_price`, `last_checked_at`, `triggered_at`, `triggered_price` | |
| `created_at`, `source` (`app`/`porty`) | |

RLS por usuario. Un trigger `before insert` controla el tope del plan contra `user_subscriptions` (D1) y devuelve un error tipado (`alert_limit_reached`, `plan_required`) que la app traduce a paywall. Índice por `(status, symbol)` para la corrida del mercado.

**`notification_outbox`**: `id`, `user_id`, `kind`, `dedupe_key`, `priority`, `data` jsonb, `not_before` (para correr al fin del silencio), `status` (`pending`/`sent`/`skipped`/`failed`), `skip_reason`, `created_at`. `unique (user_id, dedupe_key)`: ej. `big_move:NVDA:2026-10-10:down`, `price_alert:<id>`, `weekly_report:2026-10-05`. Insertar dos veces lo mismo no hace nada.

**`notification_log`**: lo enviado (`user_id`, `kind`, `sent_at`, `device_count`, `opened_at`). Lo usan el tope diario y las métricas. Se purga a los 90 días.

**`market_quotes`**: última cotización por símbolo (`price`, `prev_close`, `change_pct`, `market_state`, `fetched_at`). Solo service role.

**`app_config`**: fila `push` con `{"enabled": false, "kinds": {"price_alert": true, ...}}`. Arranca apagada, como el informe.

**Extensiones:** `pg_cron` y `pg_net`, y los `cron.schedule(...)` que llaman a las funciones con un header `x-cron-secret` (secret en Vault, no en la migración).

### 4.2 Edge functions

**`market-watch`** (cron cada 5 min, lunes a viernes de 09:25 a 16:10 ET; cada 15 min el resto del tiempo solo para cripto si D4 lo incluye)

1. Junta los símbolos a mirar: los de `price_alerts` activas ∪ los de posiciones abiertas de usuarios con `big_moves` o `portfolio_moves` prendidos.
2. Pide los precios **en lote**: Yahoo `v7/finance/quote` con la sesión que ya arma el proxy (pedidos de ~50 símbolos). Si falla, Finnhub `/quote` de a uno con el rate limit actual, solo para los símbolos con alertas activas. Guarda en `market_quotes`.
3. **Alertas de precio:** dispara si el precio **cruzó** el objetivo desde la última lectura (`last_price` del otro lado, o la primera lectura ya del lado del objetivo). `once` pasa a `triggered`; `daily` se rearma al otro día y solo si el precio volvió al menos 1% del otro lado (histéresis, así no avisa diez veces por un precio que oscila).
4. **Movimientos fuertes** (§4.3): calcula por usuario con las cantidades de `positions` y las cotizaciones.
5. Escribe en `notification_outbox` y llama a `notify-dispatch`.

**`daily-jobs`** (cron cada hora, en punto): busca usuarios cuya hora local (por `push_devices.timezone`) sea la de cada tarea.
- Sábado 09:00 → `weekly_report` si tiene posiciones y el informe está prendido. La notificación no trae contenido: el informe se sigue generando al abrir la app, como hoy, así no hace falta generarlo para todos en el servidor.
- (Fase Gold) 19:00 → `earnings_tomorrow`; a la mañana siguiente, `earnings_result`.

**`notify-dispatch`** (la llaman las otras funciones y un cron cada 5 min para lo que quedó con `not_before`)

Para cada fila `pending`, en orden de prioridad:
1. ¿Push prendido en `app_config` y para ese tipo? ¿El usuario lo tiene prendido?
2. ¿Su plan lo permite? (`price_alert`: Premium/Gold; `earnings_*`: Gold.)
3. ¿Está en horario de silencio? Los de mercado se descartan (`skip_reason = quiet_hours`): un "NVDA baja 7%" a las 8 de la mañana siguiente ya es viejo. El informe se corre al fin del silencio.
4. ¿Pasó el tope diario de automáticas? → `skipped`, salvo `price_alert` y `service`.
5. Arma el texto en el idioma del dispositivo (plantillas en `notify-dispatch/templates.ts`, es/en, con formato de números de cada idioma; sin montos si `show_amounts` es `false`).
6. Manda por FCM HTTP v1 a todos los dispositivos del usuario. Token `UNREGISTERED`/`INVALID_ARGUMENT` → borra el dispositivo.
7. Escribe `notification_log`.

El payload de datos lleva `kind`, `route` (ej. `/position/NVDA`, `/weekly-report`, `/alerts`, `/assistant?q=...`) y `notification_id` para registrar la apertura.

**`etoro-sync`** (cambio chico): cuando el refresh token es inválido, además de lo que hace hoy, inserta `etoro_reconnect` en el outbox (dedupe por día).

### 4.3 Movimientos fuertes: los umbrales

El inversor casual no quiere enterarse de cada 2%. Umbral de variación diaria contra el cierre anterior:

| Instrumento | Sensibilidad baja | Normal (defecto) | Alta |
|---|---|---|---|
| Acción | 8% | 5% | 3% |
| ETF | 5% | 3% | 2% |
| Cripto (si D4) | 12% | 8% | 5% |
| Cartera entera | 4% | 3% | 2% |

- Solo posiciones que pesen **≥ 3%** de la cartera. Una posición del 0,5% que sube 15% no le cambia el día a nadie.
- Una vez por ticker, día y dirección. Puede volver a avisar **una** vez si duplica el umbral (de −5% a −10%).
- La primera corrida del día empieza 30 minutos después de la apertura, para no avisar por el salto de apertura que después se corrige.
- Si en la misma corrida hay `portfolio_move` y `big_move`, va una sola notificación que menciona las dos cosas.

Los números se ajustan con los datos de v1 (§9): si la tasa de "apagó movimientos fuertes" pasa del 5%, son demasiadas.

### 4.4 App

Nueva feature `lib/features/notifications/`:

| Pieza | Qué hace |
|---|---|
| `services/push_service.dart` | Envuelve `firebase_messaging`: init, permiso, token y su refresco, `onMessage` (en primer plano muestra un aviso propio dentro de la app, no el banner del sistema), `onMessageOpenedApp` y `getInitialMessage` → `go_router` |
| `data/push_device_repository.dart` | `register_push_device` al iniciar sesión, en cada apertura (actualiza zona, idioma, build) y al refrescarse el token. `unregister_push_device` al cerrar sesión |
| `data/notification_preferences_repository.dart` | Lee y guarda `notification_preferences` |
| `data/price_alerts_repository.dart` | CRUD de `price_alerts`, traduce los errores tipados (`alert_limit_reached`, `plan_required`) |
| `providers/` | Riverpod como el resto (`hooks_riverpod`) |
| `view/notification_settings_screen.dart` | Interruptor general, uno por tipo, sensibilidad de movimientos, horario de silencio, "Mostrar montos". Si el permiso del sistema está negado, una fila que lleva a los Ajustes del teléfono |
| `view/price_alerts_screen.dart` (`/alerts`) | Alertas activas y cumplidas, rearmar, pausar, borrar |
| `view/create_price_alert_sheet.dart` | Hoja inferior: precio actual arriba, "Avisame si sube a / baja a / se mueve X%", sugerencias rápidas (±5%, ±10%, máximo de 52 semanas). Valida que el objetivo no esté ya cumplido |
| `view/push_permission_prompt.dart` | Pantalla previa al permiso del sistema (§6) |

Cambios en lo existente:
- **Ajustes:** vuelven las filas "Notificaciones" y "Alertas de precio" (las que se sacaron el 2026-10-07), esta vez con algo detrás.
- **Detalle de posición** y **detalle de ticker**: acción "Crear alerta" (ícono de campana); si ya hay alertas, muestra cuántas.
- **`PlanMatrix`:** nueva `PlanFeature.priceAlerts` en Premium (sale `plan_feature_price_alerts` de `extraMarketingKeys` y entra a `highlights`). Tope de alertas por plan en `PlanSpec`, espejo del servidor.
- **Router:** `/alerts`, y aceptar `/assistant?q=` desde una notificación (ya existe `HomeProvider.openAssistant(initialQuestion:)`).
- **Cierre de sesión / borrar cuenta:** desregistrar el token. Con el `on delete cascade`, borrar la cuenta limpia todo.
- **Porty:** tool `propose_price_alert` siguiendo "el modelo propone, la app ejecuta": devuelve una propuesta, la card `QaPriceAlertProposal` la muestra editable y Confirmar la crea sin pasar por el modelo. Más `list_price_alerts` para "¿qué alertas tengo?". Va con el gating de `PlanFeature.priceAlerts` vía `AssistantToolContext.lockedFeature`. Cambia el system prompt → hash nuevo en `allowed_system_prompts.json` y desplegar `ai-chat` antes que la app.
- **Traducciones** es/en para todo lo nuevo, incluido el copy de la pantalla previa al permiso.
- **Android:** permiso `POST_NOTIFICATIONS` (13+), canales: "Alertas de precio" (alta importancia), "Tu cartera", "Informes", "Cuenta". El usuario puede silenciar cada canal desde el sistema.
- **iOS:** capability Push Notifications + Background Modes (`remote-notification`), `Runner.entitlements`. Las alertas de precio con `interruption-level: time-sensitive` (necesita el entitlement), el resto `active`. `thread-id` por tipo para que se agrupen en el centro de notificaciones.

---

## 5. Planes y límites

| | Free | Premium | Gold |
|---|---|---|---|
| Alertas de precio activas | 0 (D1) | 20 | 50 |
| Movimientos fuertes y de la cartera | ✓ | ✓ | ✓ + "por qué" con noticias en el chat |
| Tu semana está lista | ✓ | ✓ | ✓ |
| Earnings de tus acciones | — | — | ✓ |
| Avisos de servicio (eToro) | ✓ | ✓ | ✓ |

Movimientos fuertes para todos porque son lo que más retiene y no cuestan casi nada por usuario. Además, en Free son una puerta al chat ("¿por qué baja?"), que es donde aparece el upgrade.

Si alguien baja de Premium a Free, sus alertas pasan a `paused` (no se borran) y la lista muestra "Tus alertas están en pausa. Volvelas a activar con Premium". Lo hace el webhook de RevenueCat al cambiar el plan.

---

## 6. Permiso: cuándo y cómo se pide

iOS deja mostrar el diálogo del sistema **una sola vez**. Si el usuario dice que no, recuperarlo exige que vaya a Ajustes. Por eso antes va una pantalla propia, y el diálogo del sistema solo aparece si toca "Activar".

Momentos (el primero que ocurra):
1. **Al crear la primera alerta de precio.** Es el momento de más intención: sin permiso la alerta no sirve.
2. **Al ver el primer informe semanal:** "¿Te avisamos los sábados cuando esté listo?"
3. **Al conectar eToro:** "Te avisamos si se corta la conexión o si tu cartera se mueve fuerte."
4. **Al terminar el onboarding, si tiene ≥ 3 posiciones:** "Porty puede avisarte cuando algo importante pasa con tu cartera". Este va como decisión D5; puede adelantar el pedido en lugar de esperar un momento con intención.

Si dice "Ahora no" en la pantalla propia, no se le vuelve a preguntar por 14 días ni más de 3 veces en total. En Android < 13 no hay diálogo: queda prendido y se manejan las preferencias.

---

## 7. Fases

| Fase | Contenido | Se puede probar con |
|---|---|---|
| **F0 · Setup** (fuera del código) | Proyecto de Firebase (solo FCM), apps iOS/Android registradas, clave APNs .p8 subida, service account en `supabase secrets` (`FCM_SERVICE_ACCOUNT`), `CRON_SECRET` en Vault. Pedir el entitlement de time-sensitive. Decidir D1–D6 | — |
| **F1 · Infraestructura** | Migraciones (`push_devices`, `notification_preferences`, `notification_outbox`, `notification_log`, `app_config.push`, `pg_cron`/`pg_net`). `notify-dispatch` con FCM, plantillas, silencio, tope y duplicados. App: `firebase_core`/`firebase_messaging`/`flutter_local_notifications`, `PushService`, registro del token, deep links, pantalla de preferencias, pantalla previa al permiso. En debug, "Enviarme una de prueba" en Ajustes | Notificación de prueba de punta a punta en un iPhone y un Android |
| **F2 · Alertas de precio** | `price_alerts` + trigger de topes, `market_quotes`, `market-watch` (solo la parte de alertas), cron. App: `PlanFeature.priceAlerts`, hoja de crear, lista `/alerts`, acción en el detalle, paywall. Webhook de RevenueCat → `paused`. **Con esto se cumple lo que Premium ya promete** | Alerta a un precio apenas arriba del actual en un ticker que se mueve |
| **F3 · Informe y eToro** | `daily-jobs` con el sábado; `etoro-sync` escribe `etoro_reconnect`. Lo más barato y de valor seguro | Correr `daily-jobs` a mano con una hora simulada |
| **F4 · Movimientos fuertes** | `big_move`, `big_move_digest`, `portfolio_move` en `market-watch` con los umbrales de §4.3. Deep link al chat con la pregunta | Tests de Deno con cotizaciones armadas; en vivo, sensibilidad alta |
| **F5 · Porty crea alertas** | `propose_price_alert`, `list_price_alerts`, card de confirmación, hash del prompt | Evals del chat: "avisame si Apple baja de 200" |
| **F6 · Earnings (Gold)** | `earnings_tomorrow` y `earnings_result` en `daily-jobs` | Semana de resultados |
| **F7 · Runbook y despliegue** | `docs/runbooks/push-notifications.md` (como el del informe): orden de despliegue, prender/apagar, checklist en el teléfono, consultas de monitoreo | — |

F1 + F2 es lo mínimo publicable. F3 se puede hacer en paralelo a F2.

### Orden de despliegue (mismo criterio que el informe)
1. Migraciones (`supabase db push`), con `app_config.push` apagado.
2. Secrets y funciones (`notify-dispatch`, `market-watch`, `daily-jobs`, `etoro-sync`, y `ai-chat` si va F5).
3. Publicar la app. Las versiones viejas no registran token, así que no reciben nada: no hay riesgo.
4. Prender `app_config.push` primero para las cuentas del equipo (lista de `user_id` en el mismo config), después para todos.

**Apagado de emergencia:** `update app_config set value = jsonb_set(value, '{enabled}', 'false') where key = 'push'`. `notify-dispatch` deja de enviar al instante, y lo pendiente queda en el outbox como `skipped`.

---

## 8. Tests

- **Deno** (`supabase/functions/tests/`): cruce de alertas (incluida la histéresis de `daily`), umbrales y peso mínimo, agrupado, silencio con varias zonas horarias (incluido el cambio de horario), tope diario, duplicados, plan, plantillas es/en sin montos, manejo de tokens inválidos con FCM falso.
- **SQL** (`supabase/tests/`): RLS de las tablas nuevas, tope de alertas por plan, `register_push_device` cuando el token cambia de usuario.
- **Flutter:** `PushService` con mensajería falsa (deep links de cada tipo, app cerrada y abierta), hoja de crear alerta (validaciones, objetivo ya cumplido), gating y paywall, reglas de cuándo pedir el permiso.
- **En el teléfono:** checklist en el runbook. Las push reales en iOS se prueban en un iPhone (o en el simulador con `xcrun simctl push` solo para el deep link).

---

## 9. Métricas

| Métrica | De dónde | Para qué |
|---|---|---|
| Tasa de permiso concedido, por momento en que se pidió (§6) | Evento en la app | Elegir el mejor momento |
| Tasa de apertura por tipo | `notification_log.opened_at` | Cuáles aportan valor |
| **Tasa de apagado por tipo** (preferencia apagada o permiso revocado en los 7 días siguientes a recibirla) | `notification_preferences` + registro del token | La señal de ruido. Si un tipo pasa del 5%, se ajusta o se saca |
| Alertas creadas por usuario Premium; % de Premium con ≥ 1 alerta | `price_alerts` | Si la feature que se vende se usa |
| Conversiones a Premium que salen del paywall de alertas | `PaywallSourceLog` (hoy sin destino: conectarlo) | Valor comercial |
| Retención D7/D30 con push y sin push | Analytics | El objetivo de fondo |
| Movimientos fuertes que terminan en una pregunta a Porty | `route` + turno del chat | Si el "¿por qué?" funciona |

---

## 10. Decisiones abiertas

| # | Decisión | Recomendación |
|---|---|---|
| **D1** | ¿Free tiene alertas de precio? | **1 alerta activa en Free.** Es el gancho para que conozca la feature y le muestre el permiso; la segunda abre el paywall. Si se prefiere mantenerlo como exclusivo de Premium, 0 |
| **D2** | ¿Movimientos fuertes para todos los planes? | **Sí** (§5) |
| **D3** | Fuente de precios del servidor | Yahoo `v7/quote` en lote para arrancar, con Finnhub `/quote` de respaldo. **Antes del lanzamiento comercial** hace falta una fuente con licencia (Finnhub pago, Polygon, Twelve Data): el runbook del informe ya marca que los planes gratis no son para uso comercial, y una alerta de precio que falla porque Yahoo cortó es justo lo que rompe la confianza |
| **D4** | ¿Cripto en v1? (eToro las trae) | Solo si hay usuarios de eToro con cripto en DEV. Si no, v2: obliga a correr el cron 24/7 |
| **D5** | ¿Pedir el permiso al terminar el onboarding? | Arrancar **sin** ese momento y medir; agregarlo si la tasa de permiso queda baja |
| **D6** | ¿La notificación de alerta cumplida dice el precio exacto? | Sí. El precio no es un monto del usuario, así que no choca con `show_amounts`. Aclarar en la hoja que puede llegar con hasta ~5 min de demora |
