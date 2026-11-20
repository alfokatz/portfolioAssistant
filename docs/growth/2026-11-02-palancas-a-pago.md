# Palancas de activación, retención y referidos que llevan a pago (noviembre 2026)

**Fecha:** 2026-11-02 · **Autor:** growth · **Estado:** propuesta (nada implementado, nada activado)
**Pregunta:** "¿Qué deberíamos construir este mes para conseguir más usuarios que paguen?"
**Insumo de otros:** `porty-data-analyst` (embudo real, pedido el 2026-11-02), `porty-monetization` (precio, anual, prueba). Este doc es la parte de producto/growth; la síntesis la hace `porty-product-owner`.

> Todo lo de abajo sale de leer el código del repo. Donde dice **hipótesis**, falta el dato de `product_funnel` para confirmarlo.
>
> **Estado de los datos (respuesta de `porty-data-analyst`, 2026-11-02):** no hay números medidos. `product_funnel` existe desde el 2026-10-26 (~1 semana de datos; las altas anteriores aparecen en null) y el SQL para correrla está en `docs/business/metrics/2026-11-02-embudo-a-pago.md`. Paywall visto y compras por source **no se pueden medir hoy**: `PaywallSourceLog` vive en memoria, no hay evento de compra y `user_subscriptions` no guarda historial. Si informe y push están prendidos en prod lo dice `select key, value from app_config;`, que tiene que correr el usuario.

---

## 1. Resumen

- El **aha ya está bien resuelto y es gratis**: onboarding de 2 pantallas → "Traé tu cartera" → diagnóstico automático (`portfolio_diagnosis`) sin modelo ni cuota. Con archivo, captura o eToro, el time-to-aha es de minutos.
- **El problema está entre el aha y el pago**, y hoy **no se puede medir**: `PaywallSourceLog` solo guarda en memoria (`lib/features/subscription/services/paywall_source_log.dart`), no hay evento de paywall visto ni de compra en `product_events`.
- **El camino más visible del onboarding termina en un callejón** para Free: "Conectá tu bróker" (primera opción, con logos de eToro y Binance) lleva a Binance u "Otro bróker" (SnapTrade), que en Free muestran solo "Ver planes" + "Conectar ... es de Premium". Sin salida a la importación gratis desde esa pantalla, y antes de haber visto ningún valor.
- **El hábito existe en código pero no llega al usuario Free**: el informe semanal da una sola degustación completa; el push del sábado depende de la configuración de Firebase (F0), que no está en el repo (no hay `google-services.json` ni `GoogleService-Info.plist`).
- **Referidos: cero en la app.** No hay share, ni `share_plus`, ni código de referido. Lo único es el `ref_code` de la waitlist de la landing (`supabase/migrations/20261013000000_landing_waitlist.sql`).

**Etapa a atacar este mes: Activación → primer pago** (el tramo aha → paywall → compra). Retención (informe semanal) va segunda porque alimenta la misma conversión a 2–4 semanas. Referidos queda tercero: con el volumen actual un loop rinde poco, pero dejamos diseñado el artefacto compartible para que esté cuando haya tráfico.

---

## 2. Recorrido del usuario nuevo (lo que hay hoy)

### 2.1 Onboarding y carga de cartera

| Paso | Dónde | Plan | Observación |
|---|---|---|---|
| Bienvenida (quién es Porty) | `presentation/flows/onboarding/ui/pages/onboarding_welcome_page.dart` | Todos | 1 pantalla |
| "Traé tu cartera", 4 caminos | `onboarding_bring_portfolio_page.dart` | Todos | Orden: bróker, archivo/captura, contarle a Porty, a mano |
| Conectá tu bróker → eToro | `features/etoro/` | Free: **1 importación gratis** (`free_import_at`), después Premium | Bien resuelto |
| Conectá tu bróker → Binance | `features/binance/view/binance_screen.dart` | **Premium** | Free ve "Ver planes" y nada más |
| Conectá tu bróker → Otro (SnapTrade) | `features/snaptrade/view/snaptrade_screen.dart` | **Premium** (1), Gold (varios) | Free ve "Ver planes" y nada más |
| Archivo o captura | `features/statement_import/` | Gratis en CSV; PDF/captura gasta 1 consulta | Tope Free: 10 posiciones |
| Contarle a Porty / a mano | `assistant`, `manual_positions` | Todos | |

**Qué pasa si no conecta bróker:** si elige archivo, captura, texto o manual, llega al diagnóstico igual. El problema es quien elige "Conectá tu bróker" y su bróker no es eToro: el link "¿No está tu bróker? Subí un extracto o una captura" vive en la pantalla de la lista (`connect_broker_screen.dart`), pero **no en las pantallas bloqueadas de Binance y SnapTrade**, que es donde el usuario Free se frena. **Hipótesis:** es la mayor fuga entre `onboarding_finished{exit: connectBroker}` y `portfolio_loaded`.

### 2.2 Aha moment

- `PortfolioDiagnosisScreen` se abre sola apenas la cartera tiene posiciones. Muestra hasta 3 hallazgos (solapamiento ETF/acción, sector "adentro" de los fondos, concentración, costo de fondos, contra el S&P 500, mejor/peor) y 2 preguntas para seguir en el chat.
- Eventos: `portfolio_loaded{method,count}`, `diagnosis_seen{findings,positions}`, `diagnosis_question{kind}`, `first_chat_answer`. Vista `product_funnel` con minutos desde el alta.
- **Lo que falta después del aha:**
  - No hay puente al pago en el pico de interés. El diagnóstico termina en "Ir a mi cartera".
  - No se pide permiso de push acá (sí en informe, eToro, asistente y alertas), aunque es el momento en que Porty acaba de demostrar que sirve.
  - Las preguntas sugeridas gastan consultas de las 20 mensuales de Free. Algunas ("¿Por qué {ticker} viene tan mal?", "¿Qué explica la suba de…?") probablemente piden noticias, que son Gold. **Hipótesis a verificar:** la primera respuesta del chat a veces choca con un límite de plan, en el peor momento.

### 2.3 Hábito y retención

| Pieza | Qué trae de vuelta | Free | Qué falta |
|---|---|---|---|
| Informe semanal (`weekly_report`) | Tarjeta en Home el sábado; push sábado 9:00 vía `daily-jobs` | **1 informe completo de regalo**, después números + "Lo que explica tu semana está en Gold" | Una sola vez no alcanza para formar el hábito; sin push, solo lo ve quien abre la app |
| Push (`notifications`) | Alertas de precio, movimientos fuertes, informe, earnings | 1 alerta de precio | F0 (Firebase/APNs) sin hacer en el repo; interruptor `app_config.push` arranca apagado |
| Porty inbox (`porty_inbox`) | Hasta 3 insights en la Home (concentración, alerta cerca, pérdida fuerte, metas, plan) | Sí (los de cartera) | Solo se ve si abrís la app; no tiene salida a push |
| Metas (`goals`) | Progreso, "te falta poco", atraso | **No** (Premium) | No hay momento de logro ("cumpliste tu meta") ni nada para mostrar |
| Watchlist | Precios de lo que no tenés | **No** (tope 0) | |
| Investor pulse | Super investors en el informe | Dentro del informe | |

**Lectura:** el único gancho recurrente de Free es el informe semanal, y se le corta a la segunda semana. Free no tiene metas, ni watchlist, y tiene 1 alerta. Free tiene poco que lo traiga de vuelta, y quien no vuelve no paga.

### 2.4 Ingresos (visto desde growth)

- Paywalls con `source` en el código: `etoro_connect`, `weekly_report`, `porty`, `weekly_free_analysis`, `price_alert_limit`, `price_alert_reactivate`, `home_benchmark`. Binance y SnapTrade abren el paywall con `reason` pero **sin source propio**.
- Ninguno queda registrado. **Sin esto no sabemos qué paywall convierte**, y cualquier experimento de este doc sería a ciegas.
- Solo existen productos mensuales (`subscription_catalog.dart`). El precio anual y la prueba Gold son de `porty-monetization`.

---

## 3. Loops compartibles posibles con lo que ya existe

Regla: **lindo, útil y seguro**. Nunca montos reales. Solo porcentajes o logros, con opt-in en cada share y vista previa antes de compartir.

| Artefacto | Fuente | Qué se puede mostrar | Qué NO se muestra |
|---|---|---|---|
| **"Lo que vio Porty en mi cartera"** | `PortfolioDiagnosis` | "Tecnología es el 48 % de mi cartera aunque solo tengo 12 % en acciones tech", "NVDA pesa 9 % contando mis ETFs", "3 posiciones son el 71 %" | `fees.annual` (USD), `vsMarket.diff` (USD). Si se usa vs S&P, solo en puntos porcentuales. Opción de ocultar tickers |
| **"Mi semana"** | `WeeklyPortfolioNumbers` (`portfolioPct`, `sp500Pct`, `contributionPp`) | "+1,8 % esta semana; lo que más empujó: VOO" | `valueStart/End`, `newMoney`, `pnlAbsolute`. En Free, sin S&P (es feature de Premium) |
| **Logro de meta** (más adelante) | `GoalStatus.achieved` | "Llegué a mi meta 'Auto' con Porty", % de avance | Monto objetivo y ahorrado |

Diseño del loop (para el experimento E6):
1. Botón discreto "Compartir" en el diagnóstico y en el informe. Abre una hoja con la imagen (marca Porty, mucho aire, sin cifras en $) y dos toggles: "Mostrar tickers" (apagado por defecto) y "Mostrar comparación con el S&P 500".
2. La imagen lleva una línea con "porty.app" y un link con `utm_source=share&utm_content=<kind>` y el código de referido.
3. El que llega cae en la landing (ya mide `utm_*` y `referred_by` en `waitlist`/`landing_events`) o en la tienda.
4. Cierre del loop: el nuevo usuario hace su propio diagnóstico (gratis) y ve el mismo botón.

Riesgos: un claim de rendimiento ("le gané al S&P") con la marca Porty en una imagen pública. Lo revisa `porty-compliance` antes de construirlo.

---

## 4. Backlog de experimentos

ICE de 1 a 10, score = promedio. Talla de código: S (≤2 días), M (3–5), L (>5). Con el volumen actual, la mayoría se mide como **cohorte antes/después de 2 semanas** y no como A/B. Si `porty-data-analyst` ve volumen suficiente, se hace A/B por `user_id`.

### E0 (prerrequisito, no es experimento): medir paywall y compra

- **Cambio:** que `PaywallSourceLog.record` también escriba `paywall_viewed{source, reason, tier}` en `product_events`; sumar `purchase_completed{tier, source}` al confirmar la compra en RevenueCat, `push_opt_in{source}` y `weekly_report_opened{week, mode: full|teaser|courtesy}`. Darle `source` a los paywalls de Binance (`binance_connect`) y SnapTrade (`snaptrade_connect`). Sumar a `product_funnel` `min_to_first_paywall` y `min_to_purchase`.
- **Código:** S. **ICE:** 9 / 10 / 9 → **9,3**.

### E1: el bróker bloqueado deja de ser un callejón

- **Hipótesis:** si un Free que eligió Binance u "Otro bróker" ve, junto a "Ver planes", una salida gratis ("Mientras tanto, traela con una captura de tu bróker: te muestro lo que veo en segundos"), más usuarios llegan al diagnóstico. Y, habiendo visto valor, más vuelven a pagar por la sincronización automática.
- **Cambio mínimo:** botón secundario en el estado bloqueado de `binance_screen.dart` y `snaptrade_screen.dart` hacia `StatementImportRouter` (captura). Copy en la voz de Porty. "Ver planes" sigue primero.
- **Variante B (si E1 funciona):** primera importación de Binance gratis, igual que eToro (Binance directo no tiene costo por conexión; SnapTrade sí, eso lo decide `porty-monetization`).
- **Métrica:** % de `onboarding_finished{exit: connectBroker}` que llega a `portfolio_loaded` en 24 h. Secundaria: `paywall_viewed{source: binance_connect|snaptrade_connect}` → `purchase_completed` a 14 días.
- **Duración:** 2 semanas. **Código:** S (variante B: M).
- **ICE:** 8 / 7 / 8 → **7,7**.

### E2: puente al pago y pedido de push después del aha

- **Hipótesis:** el final del diagnóstico es el pico de confianza. Una fila tranquila, pegada a lo que trajo, convierte más que los paywalls de bloqueo:
  - si cargó por archivo, captura, texto o a mano: "Para que se actualice sola, conectá tu bróker" (Premium, `source: diagnosis_sync`);
  - para todos: "¿Te aviso el sábado con lo que pasó en tu semana?" → `PushPermissionSheet` (`source: diagnosis`).
- **Cambio mínimo:** 1–2 filas en `portfolio_diagnosis_screen.dart` antes de "Ir a mi cartera". Sin modal, sin urgencia.
- **Métrica:** `paywall_viewed{source: diagnosis_sync}` → `purchase_completed` a 14 días; tasa de `push_opt_in{source: diagnosis}` contra los otros sources.
- **Duración:** 2 semanas. **Código:** S.
- **ICE:** 7 / 6 / 9 → **7,3**.

### E3: tres informes semanales completos antes del teaser

- **Hipótesis:** una sola degustación no forma hábito. Con 3 sábados completos (la semana 4 pasa a teaser), el usuario siente la pérdida y paga Gold. Hoy pierde el informe antes de extrañarlo.
- **Cambio mínimo:** la cortesía la decide el servidor (`claim_weekly_report`, columna `courtesy` en `weekly_reports`). Pasar de "una vez" a "las primeras N semanas desde el alta", con N en `app_config.weekly_report` (reversible sin publicar app). Costo: ~US$0,004 por informe, despreciable.
- **Métrica:** retención W2/W3/W4 (`weekly_report_opened`) y `paywall_viewed{source: weekly_report}` → `purchase_completed{tier: gold}` en la semana 4–5. Contra la cohorte actual (N=1).
- **Duración:** 5 semanas (necesita llegar al teaser). **Código:** M (migración SQL + copy de la cortesía).
- **ICE:** 8 / 6 / 6 → **6,7**.

### E4: push del sábado con el informe (operativo, sin código)

- **Hipótesis:** el informe solo retiene si llega aunque el usuario no abra la app.
- **Cambio:** completar F0 del runbook (`docs/runbooks/push-notifications.md`: Firebase, APNs, **revisar el bundle id de iOS**), prender `app_config.push` primero para `allow_users` y después solo `kinds.weekly_report` + `price_alert`. Movimientos fuertes y earnings quedan apagados al principio para no hacer ruido.
- **Métrica:** `notification_log` (tasa de apertura de `weekly_report`), bajas de `notification_preferences`, retención W2–W4.
- **Código:** nada (lo ejecuta el usuario). **ICE:** 7 / 6 / 7 → **6,7**.

### E5: una meta gratis en Free

- **Hipótesis:** las metas son el motivo más personal para volver ("te falta poco para el auto"), y Free no tiene ninguna. Una meta gratis, como la alerta gratis, crea un vínculo que Premium amplía (más metas, simulaciones).
- **Cambio mínimo:** tope de metas por plan (Free 1) en vez de gating total de `PlanFeature.goals`, con el mismo patrón que `priceAlertLimit`. Requiere el mismo tope en el servidor si `save_goal` lo valida.
- **Métrica:** % de Free con meta activa; retención a 30 días de Free con meta contra sin meta; `paywall_viewed{source: goal_limit}` → compra.
- **Duración:** 4 semanas. **Código:** M.
- **ICE:** 6 / 5 / 6 → **5,7**.

### E6: tarjeta compartible "Lo que vio Porty" (loop de referidos)

- **Hipótesis:** un hallazgo sorprendente y no financiero en $ ("el 48 % de mi cartera es tecnología") es algo que la gente comparte. Trae usuarios parecidos, que activan gratis con el mismo diagnóstico.
- **Cambio mínimo:** imagen renderizada del diagnóstico (solo %), opt-in, vista previa, tickers apagados por defecto, link con `utm_source=share`. Ver §3.
- **Métrica:** `share_created{kind}` / `diagnosis_seen`; altas con `utm_source=share` en `landing_events`/`waitlist`; K = invitados que activan / usuarios que comparten.
- **Duración:** 4 semanas. **Código:** M (render a imagen + `share_plus` + link). **Revisión de `porty-compliance`** antes de construir.
- **ICE:** 6 / 4 / 5 → **5,0**.

### E7: referidos con recompensa (más adelante)

- **Hipótesis:** "Invitá a alguien: los dos tienen un mes de Premium" acelera E6 una vez que el loop orgánico existe.
- **Cambio:** entitlement promocional de RevenueCat (requiere el arreglo del webhook descrito en `docs/superpowers/plans/2026-09-30-diferenciacion-planes.md` §c), código de referido en la app y antiabuso.
- **Código:** L. **Compliance** obligatorio (recompensas). **ICE:** 6 / 4 / 3 → **4,3**.

### Orden

| # | Experimento | ICE | Código | Este mes |
|---|---|---|---|---|
| E0 | Medir paywall y compra | 9,3 | S | **Sí, primero** |
| E1 | Bróker bloqueado con salida | 7,7 | S | **Sí** |
| E2 | Puente al pago + push después del aha | 7,3 | S | **Sí** |
| E3 | 3 informes completos | 6,7 | M | **Sí** (arranca este mes, se lee en diciembre) |
| E4 | Push del sábado | 6,7 | — (ops) | Si el usuario hace F0 |
| E5 | 1 meta gratis | 5,7 | M | Próximo mes |
| E6 | Tarjeta compartible | 5,0 | M | Próximo mes, después de compliance |
| E7 | Referidos con recompensa | 4,3 | L | Cuando E6 muestre K > 0 |

---

## 5. Cómo medimos

- **Métrica norte del mes:** % de altas que pagan dentro de los 14 días (`purchase_completed` / altas de la cohorte), por `load_method` y por `source` del paywall.
- **Embudo:** alta → `onboarding_finished` → `portfolio_loaded` → `diagnosis_seen` → `paywall_viewed` → `purchase_completed`. Retención: `weekly_report_opened` en W2–W4.
- **Guardarraíles:** bajas de notificaciones (`notification_preferences`), reembolsos, reseñas que mencionen "paywall" o "me cobró".

## 6. Límites

Nada de esto manda notificaciones, activa campañas ni gasta plata. Prender push, cambiar `app_config` en prod y cualquier recompensa los aprueba y ejecuta el usuario. Lo que necesita código pasa por `porty-product-owner` → `porty-architect`.
