# Auditoría de conversión free → Premium/Gold

**Fecha:** 2026-11-02 · **Autor:** responsable de monetización · **Estado:** propuesta (sin cambios de código)
**Pregunta de negocio:** "¿Qué deberíamos construir este mes para conseguir más usuarios que paguen?"

> **Sobre los números.** No hay datos de conversión medidos: no se registran las aperturas de paywall por origen (`PaywallSourceLog` solo vive en memoria y en `debugPrint`), no hay evento de compra con origen y `user_subscriptions` no guarda historial (porty-data-analyst, 2026-11-02; detalle en `docs/business/metrics/2026-11-02-embudo-a-pago.md`). Todo impacto que aparece acá es una **hipótesis con supuestos explícitos**. El costo por turno de IA está instrumentado (`ai_turn_usage.cost_usd`) y la estimación vigente es **~US$0,004–0,007 por turno**. Los precios de referencia (Premium US$10, Gold US$15 por mes) salen de `2026-09-30-diferenciacion-planes.md`: los reales los fija la tienda.

---

## 1. Cómo monetiza Porty hoy

| | Free | Premium | Gold |
|---|---|---|---|
| Qué responde | "¿Cómo está mi cartera?" | "¿Cómo está el mercado?" | "¿Qué significa y por qué?" |
| Consultas/mes (tope diario) | 20 (sin tope diario) | 500 (60/día) | 1000 (100/día) |
| Posiciones / alertas / watchlist | 10 / 1 / 0 | sin tope / 20 / 30 | sin tope / 50 / 100 |
| Degustaciones | 1 análisis Gold por semana, 1 informe semanal completo (una sola vez) | ídem | — |
| Productos en tienda | — | `portfolio_premium_monthly` | `portfolio_gold_monthly` |

Fuentes: `lib/domain/subscription/plan_matrix.dart`, `supabase/migrations/20260930120000_ai_proxy.sql` (`plan_limits`), `supabase/migrations/20261002120000_weekly_reports.sql`, `lib/features/subscription/config/subscription_catalog.dart`.

- **No hay trial ni plan anual.** Solo hay productos mensuales. El webhook (`supabase/functions/revenuecat-webhook/handler.ts`) ya recalcula el plan desde el `CustomerInfo` e incluye entitlements promocionales, así que el bloqueo técnico que tenía la prueba promocional del doc del 30/09 **ya está resuelto**.
- **Compras:** RevenueCat. Los precios vienen localizados de la tienda (`storeProduct.priceString`) y "Restaurar compras" está visible en el paywall. Bien.

### Dónde aparece el paywall y qué pasa

| Disparador | Comportamiento | Paywall (título) |
|---|---|---|
| Free pregunta por un ticker que no tiene (`marketDataLocked`) | **Se corta el turno** (`AssistantTurnPolicy.paywallFor`): la respuesta desaparece y se abre la hoja | "Datos de mercado no incluidos en tu plan" |
| Simulaciones, metas, plan de cartera (`modeLocked`) | **Se corta el turno** | "Modo no disponible en tu plan" |
| Datos Gold (análisis, noticias, earnings, fundamentals) | El turno sigue y se agregan `QaGoldTeaser` / `QaGoldLock` (uno por card), que se tocan para abrir el paywall con preview | "El análisis completo, con Gold" |
| Cuota agotada | Paywall al enviar; aviso visual con el 10% restante (2 de 20) | "Consultas agotadas" |
| Settings "Mejorar plan", tope de 10 posiciones, importar extracto, plan de cartera | Hoja directa con `modeLocked` | "Modo no disponible en tu plan" |
| Alertas, watchlist, brókers, benchmark de home, informe semanal | Hoja directa con su motivo | Varía |

---

## 2. Diagnóstico

### 2.1 La escalera está invertida: la puerta de entrada tiene el muro más duro
Gold muestra valor antes de cobrar: tiene teaser dentro de la respuesta, preview en el paywall, un análisis gratis por semana y un informe de degustación. **Premium, que es el primer escalón y el más barato, no muestra nada.** La pregunta más natural en un chat de inversión ("¿qué opinás de NVDA?", "¿cómo viene el S&P?") corta el turno y abre una hoja que dice "Datos de mercado no incluidos en tu plan". El usuario pagaría por algo que nunca vio. Esto choca con el principio de "mostrar valor antes de pedir pago" y es, a mi juicio, la mayor fuga de conversión.

### 2.2 La diferencia entre planes es clara en el papel, pero el paywall la cuenta mal
- Cada card del paywall abre con "500 / 1000 consultas por mes". Eso presenta a Gold como "el doble de consultas" y no como "el porqué". El propio doc del 30/09 recomendaba no vender el número.
- El medidor de uso ("3/20 consultas este mes") se ve en **todos** los paywalls, incluso cuando el motivo es un análisis Gold. En ese contexto es ruido.
- Ante motivos de nivel Premium (mercado, tope de posiciones, brókers), la hoja muestra Gold primero con el badge "Recomendado". Puede funcionar como ancla de precio o puede confundir a quien solo quería un precio. **Sin datos no se puede saber: hay que testearlo**, no suponerlo.
- **Copy heredado.** `modeLocked` dice "Modo no disponible en tu plan… desbloquear modos del asistente", pero los modos ya no existen. Es el texto del punto de entrada más intencional (Settings → "Mejorar plan") y también el del tope de 10 posiciones. `settings_upgrade_coming_soon` todavía dice "suscripciones Pro".

### 2.3 Free da valor, pero no muestra lo que viene después
Free tiene su cartera, 20 consultas, 1 alerta y las degustaciones de Gold. Alcanza para engancharse. Lo que deja con ganas de más hoy es Gold (por las degustaciones), no Premium. Free no prueba nunca "cualquier ticker", simulaciones ni metas.

### 2.4 Trial: no hay
Nadie puede usar Premium o Gold completo antes de pagar. Con el webhook ya arreglado, una prueba promocional (sin tarjeta) es de esfuerzo bajo.

### 2.5 ¿Las 20 consultas por mes son un buen disparador?
Sirven como **señal de intención** (quien llega a 20 es un usuario enganchado), pero no como disparador principal:
- Llega tarde y le llega a pocos (hipótesis: menos del 15% de Free llega a 20; hay que medirlo en `ai_usage_monthly`).
- El paywall de cuota está escrito como un muro ("Alcanzaste el límite") y no dice cuándo se renueva la cuota. Quien llega a 20 el día 10 queda sin Porty tres semanas: hay riesgo de perder retención Free.
- Costo: un Free que usa las 20 consultas cuesta ~US$0,08–0,14 por mes. **No hace falta bajar el límite.** Tampoco subirlo antes de medir.

### 2.6 Medición: hoy no se puede saber qué paywall vende
Las aperturas no se persisten, varias llamadas a `SubscriptionPaywallSheet.show` no pasan `source` (las del chat por motivo, Settings, tope de posiciones, watchlist) y RevenueCat no recibe el origen. **Cualquier experimento de este mes sería a ciegas si no se arregla esto primero.**

### 2.7 Riesgo de tienda (para porty-compliance)
El paywall muestra precio por mes, pero **no muestra los términos de renovación automática ni links a Términos y Privacidad** junto al botón de compra. Apple 3.1.2 y la guía de suscripciones lo exigen en el flujo de compra. Es un riesgo de rechazo en review, independiente de la conversión.

---

## 3. Propuestas (ordenadas por impacto/esfuerzo)

### P1. Medir y corregir el paywall: eventos, origen, copy y términos
**Esfuerzo:** ~1,5–2 días · **Impacto:** habilita todo lo demás; el copy suma un poco de conversión.

**Qué cambia:**
- Tabla `paywall_events (user_id, source, reason, tier, action: open|purchase|restore|dismiss, product, created_at)` con una RPC. `PaywallSourceLog.record` escribe ahí y `source` pasa a ser **obligatorio** en `SubscriptionPaywallSheet.show`.
- Antes de comprar, `Purchases.setAttributes({'paywall_source': …})`. Así RevenueCat atribuye cada compra a su origen sin infraestructura nueva.
- `PaywallReason` nuevos para reemplazar el `modeLocked` genérico: `plans` (neutral, para Settings: "Elegí tu plan"), `positionLimit`, `simulations`, `goals`, `allocationPlan`. Cada uno con título en la voz de Porty, que diga qué gana el usuario y no qué le falta.
- El medidor de uso se muestra solo cuando el motivo es la cuota. La línea "N consultas por mes" baja a texto secundario ("Uso justo: N consultas por mes").
- Debajo de los botones: "Se renueva cada mes a {precio}. Cancelás cuando quieras desde {App Store / Google Play}." y links a Términos y Privacidad. **Ese texto pasa por porty-compliance.**

**Para quién:** todos los que ven un paywall.
**Riesgo de churn:** nulo.
**Cómo se testea:** tests de widget del paywall (cada motivo con su título; términos y Restaurar siempre visibles) y un test de que ninguna llamada omite `source`.
**Cómo se revierte:** el copy son claves de traducción y la tabla es aditiva.

### P2. Degustación de Premium: el turno sigue y se ve el dato real
**Esfuerzo:** ~3–4 días · **Impacto:** el más alto de esta lista sobre free → Premium.

**Qué cambia:**
- Free recibe **3 consultas de mercado por mes** (tickers que no tiene, gráficos, comparaciones) con datos reales. Se reutiliza el mecanismo de cortesía de `ctx.gate` (`courtesyTicker`) y un contador en servidor igual al de `weekly_free_analysis`.
- La card lleva un caption chico: "Consulta de mercado gratis · te quedan 2 este mes".
- Agotadas las degustaciones, **el turno de mercado deja de cortarse**: Porty responde lo que el plan permite (concepto, relación con su cartera) y la app agrega un `QaPremiumTeaser` (gemelo de `QaGoldTeaser`, uno por respuesta) que abre el paywall con `source: 'chat_market_teaser'` y un preview del tipo de card que vería.
- En `PlanMatrix`: `PlanSpec.marketDataTastesPerMonth` (Free 3, el resto 0 o sin efecto), espejado en `plan_limits`.

**Para quién:** Free.
**Impacto esperado (hipótesis):** si hoy convierte ~X% de quienes ven el paywall de mercado, mostrar el valor antes podría llevarlo a 1,3–2×X. Se valida con P1.
**Margen:** 3 turnos × ~US$0,006 ≈ US$0,02 por Free por mes. Despreciable.
**Riesgo:** algún Free se conforma con 3 por mes; por eso el número es chico y se testea.
**Cómo se testea:** A/B por hash de `user_id` con Firebase Remote Config (`premium_taste_enabled`, 50/50 entre Free nuevos). Métrica principal: compras de Premium o Gold atribuidas a menos de 30 días (`paywall_events` + RevenueCat). Guardrail: retención D7/D30 Free.
**Cómo se revierte:** se apaga el flag y se vuelve al corte actual.

### P3. Prueba de 7 días sin tarjeta (entitlement promocional) en el momento "ajá"
**Esfuerzo:** ~3 días (el webhook ya está listo) · **Impacto:** alto en free → pago, sobre todo Gold.

**Qué cambia:**
- Edge function `grant-trial` (idempotente, tabla `trial_grants`) que otorga Gold por 7 días por la API de RevenueCat, con tope de 100 consultas durante la prueba.
- Se ofrece **una sola vez**, después de que el usuario cargó su cartera y recibió su tercera respuesta: ahí Gold puede analizar sus propias acciones.
- Se ofrece también al llegar a la cuota de Free si todavía no la usó.
- Settings muestra "Gold de regalo · quedan N días". El día 6 aparece un aviso en la app. Al vencer no hay pantalla bloqueante: vuelven los teasers.
- **No es un trial de tienda:** no hay cobro automático ni tarjeta y el copy lo dice sin ambigüedad ("7 días de Gold de regalo. No se cobra nada al terminar.").

**Para quién:** Free sin pruebas previas.
**Margen:** peor caso 100 × US$0,007 ≈ US$0,70 por prueba; típico ~US$0,20.
**Riesgos:** cuentas múltiples (acotado por email verificado y por el tope); expectativa de "gratis para siempre" (se mitiga con copy claro).
**Cómo se testea:** A/B de tres brazos (`trial_offer_variant`: sin prueba / al terminar el onboarding / tras la tercera respuesta; ver sección 6). Métrica: tasa de pago a 30 días por usuario expuesto, no por prueba iniciada.
**Cómo se revierte:** se apaga el flag. Las pruebas ya otorgadas vencen solas o se revocan por la API.

### P4. Plan anual y orden de planes según el motivo
**Esfuerzo:** ~2–3 días más la revisión de tiendas · **Impacto:** medio en ARPU y churn; bajo en conversión.

**Qué cambia:**
- Productos anuales: 10× el mensual ("2 meses gratis"). El ahorro se calcula con el `StoreProduct` real, no hardcodeado. Selector Mensual/Anual en el paywall.
- Experimento de orden: ante motivos de nivel Premium, **Premium primero y destacado, Gold como "Para entender el porqué"**; ante motivos Gold, solo Gold (como hoy).

**Para quién:** todos los que ven el paywall.
**Riesgo:** ofrecer Premium primero puede bajar la mezcla de Gold. Por eso es un A/B con ARPU por expuesto como métrica principal, no conversión pura.
**Cómo se testea:** con dos offerings en RevenueCat y la variante de orden por Remote Config.
**Cómo se revierte:** se vuelve al offering `default` y al orden actual.

### P5. Reencuadrar el disparador de cuota
**Esfuerzo:** ~1 día · **Impacto:** bajo-medio; protege la retención Free.

**Qué cambia:**
- A las 15/20 consultas, **una línea discreta en el chat** (no un modal, una sola vez por mes): "Te quedan 5 consultas este mes. Con Premium tenés 500."
- En 0, el paywall se titula "Seguí con Porty este mes", dice cuándo se renueva la cuota ("Tus consultas vuelven el 1 de diciembre") y ofrece la prueba de P3 si corresponde.
- El límite de 20 no cambia.

**Cómo se testea:** con `paywall_events` (`source: quota_soft` / `quota_zero`). Guardrail: retención Free del mes siguiente.
**Cómo se revierte:** el copy son claves de traducción y la línea va con un flag.

---

## 4. Recomendación para este mes
1. **P1** (semana 1): sin medición, nada de lo demás se puede evaluar. Incluye el arreglo de términos que pide la tienda.
2. **P2 y P3 en paralelo** (semanas 2–3), como A/B separados con flags independientes. Son las dos palancas de "mostrar valor antes de pedir pago".
3. **P5** junto con P3 (comparten el paywall de cuota).
4. **P4**: el usuario crea los productos anuales esta semana (la revisión de tiendas tarda) y el código se prepara en paralelo. Sube de prioridad por las referencias de mercado (sección 6).

Fuera de alcance por ahora: subir o bajar las cuotas y cambiar el precio de Gold. Primero hacen falta 60 días de `ai_usage_monthly_stats` y `paywall_events`.

## 5. Lo que hace el usuario (no los devs)
- Para P4: crear `portfolio_premium_annual` y `portfolio_gold_annual` en App Store Connect (mismo grupo) y Google Play (base plan anual), asociarlos a los entitlements `premium`/`gold` y agregarlos al offering (más un offering alternativo para el A/B).
- Para P3: crear la secret key de RevenueCat con permiso de entitlements promocionales y cargarla en los secrets de Supabase.
- Aprobar el copy de renovación y de la prueba con porty-compliance y los cambios de plan con porty-product-owner.

## 6. Referencias de mercado
Fuente: porty-market-researcher. El detalle y los links están en `docs/business/research/2026-11-02-que-paga-el-inversor-retail.md`. Varios precios vienen de terceros porque las páginas oficiales no se pudieron abrir: hay que verificarlos antes de usarlos como ancla.

| App | Tiers pagos | Precio | Trial |
|---|---|---|---|
| Snowball | 3 | USD 7,99 / 14,99 / 24,99 por mes, o 79,99 / 149,99 / 249,99 por año. Free con 10 holdings | — |
| getquin | 2 | ~89,99 € / ~149,99 € por año | 7 días |
| Delta (eToro) | 2 | PRO ~USD 59–100 por año según la región. Free con 10 activos | sin dato |
| Copilot Money | 1 | USD 13 por mes / 95 por año, sin free | 1 mes |
| Seeking Alpha | 1+ | Premium USD 299 por año | 7 días o primer mes a USD 4,95 |
| Robinhood Gold (IA Cortex) | 1 | USD 5 por mes / 50 por año | — |

Benchmarks (RevenueCat SOSA 2026 y Adapty 2026, citados por terceros):
- Trial a pago: ~25,6% global. Las apps con IA convierten mejor el trial (8,5% vs 5,6%) pero retienen peor al año (21,1% vs 30,7%).
- El 89,4% de los trials empieza el día 0. Install a pago: 1,78% con trial en el onboarding vs 0,89% con trial dentro de la app.
- Los trials largos (17–32 días) convierten más que los de menos de 4 días (42,5% vs 25,5%).
- Finanzas (metodología dudosa): mediana USD 8,99 por mes y ~50% elige el plan anual.

**Qué cambia en las propuestas:**
- **P3:** el dato de Adapty (el trial en el onboarding convierte ~2× más que dentro de la app) contradice ofrecer la prueba recién en el momento "ajá". El A/B pasa a tener **tres brazos**: sin prueba / prueba al terminar el onboarding (con la cartera ya cargada) / prueba tras la tercera respuesta. Se mantienen los 7 días; probar 14 días queda para una segunda iteración, porque las pruebas largas convierten más pero cuestan más IA.
- **P4 sube de prioridad.** Todos los comparables tienen plan anual y en finanzas cerca de la mitad lo elige. Porty no lo tiene. Conviene que el usuario cree los productos anuales en las tiendas ya, para que P4 no quede trabada por la revisión.
- **Precio:** Premium US$10 y Gold US$15 están dentro del rango (Snowball 7,99–24,99; getquin ~7,5–12,5 € por mes en el anual). No hay motivo para moverlos ahora.
- **Retención:** las apps con IA retienen peor al año. Gold necesita valor recurrente (informe semanal, avisos), no solo valor bajo demanda. Esto refuerza priorizar el anual.
- **Competencia local:** desde el 27/08/2026, IOL deja conectar la cuenta a ChatGPT/Claude gratis por MCP. La diferenciación de Porty tiene que estar en lo que un chat genérico no da (cards con datos verificados, informe semanal, metas, plan de cartera), y eso es lo que debería mostrar el paywall.
