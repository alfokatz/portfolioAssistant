# Roadmap de producto

## Noviembre 2026: del aha al primer pago

**Fecha:** 2026-11-02 · **Autor:** porty-product-owner · **Pregunta del usuario:** "¿Qué deberíamos construir este mes para conseguir más usuarios que paguen?"

**Insumos:** `docs/business/metrics/2026-11-02-embudo-a-pago.md` (data), `docs/business/research/2026-11-02-que-paga-el-inversor-retail.md` (mercado), `docs/growth/2026-11-02-palancas-a-pago.md` (growth), `docs/business/monetization/2026-11-02-auditoria-conversion.md` (monetización).

### Tesis del mes

El aha ya funciona y es gratis (diagnóstico automático en minutos). La plata se pierde **entre el aha y la compra**, y hoy ese tramo es invisible: ni paywall visto ni compra con origen se guardan. En noviembre no agregamos features: **arreglamos los momentos donde el usuario ya quiere pagar y los hacemos medibles**. Un solo cambio global (la prueba de Gold) queda para diciembre, aislado, cuando haya línea de base.

Contexto de mercado que cambia el mensaje, no el plan del mes: IOL conecta la cuenta a ChatGPT/Claude gratis por MCP desde el 27/08. "Chat que ve tu cartera" ya no alcanza como diferencial. Lo que un chat genérico no da: varios brókers juntos, números exactos con su fuente, informe semanal, metas, plan de cartera. Eso es lo que los paywalls de este mes tienen que mostrar.

### Reglas del mes

- **Sin A/B.** Con el volumen probable no da significancia (~3.800 usuarios por brazo para ver 2 % → 3 %). Cada cambio va detrás de un interruptor en `app_config` (se apaga sin publicar) y se mide por cohorte antes/después.
- **Cada paywall nuevo tiene su `source`.** Así las compras se atribuyen por origen aunque haya varios cambios a la vez.
- **No se tocan precios ni cuotas.** Primero hacen falta 4–8 semanas de datos.
- **No se recorta nada de lo que Free ya tiene.** Lo nuevo suma valor gratis o agrega salidas.

### Métrica norte

**% de altas de la cohorte que pagan dentro de los 14 días**, por `source` del paywall y por `load_method`. Fuente: `product_events` (`paywall_viewed`, `purchase_result`) + `subscription_events` (nueva). Hoy no se puede calcular: la apuesta #1 lo habilita. **No hay línea de base**: la primera lectura es la de la semana del 23/11.

Guardarraíles: reembolsos, bajas de notificaciones, retención Free D7/D30, reseñas que digan "paywall" o "me cobró".

---

### Condición para publicar (no es apuesta, no compite por RICE)

**0. Borrado de cuenta en la app** (agregado el 2026-11-02 tras la revisión de compliance, `docs/legal/reviews/2026-11-02-paywall-y-nudges.md` H1). Hoy "Eliminar cuenta" solo muestra "estará disponible pronto" (`settings_screen.dart:211-223`). Apple 5.1.1(v) exige borrado dentro de la app y Google Play exige borrado en la app más un link web: **cualquier envío se rechaza**, con o sin estas apuestas. No suma pagos, pero sin esto no sale nada de lo de abajo. Brief: `docs/product/briefs/2026-11-02-borrado-de-cuenta.md`. Talla S–M (~2–3 días-persona). Dueños: porty-backend-dev (edge function), porty-flutter-dev (flujo), porty-security-reviewer.

También bloquea el envío, pero es tarea del usuario: que las páginas de Términos y Privacidad existan, digan Porty (no PortfolioAI) e incluyan la cláusula de suscripciones (H2, §4 de la revisión).

### Apuestas priorizadas (RICE)

Escala: **R** = % estimado de la cohorte mensual de altas expuesta (supuesto: no hay volumen medido, sale de Q1/Q2 del doc de data); **I** = 0,25 / 0,5 / 1 / 2 / 3; **C** = confianza; **E** = días-persona. Score = R × I × C / E. Los scores ordenan, no predicen.

| # | Apuesta | R | I | C | E | Score | Talla |
|---|---|---|---|---|---|---|---|
| 1 | Paywall medible y aprobable por las tiendas | 60 | 1 | 90 % | 3 | **18** | S |
| 2 | Plan anual en el paywall | 60 | 1 | 70 % | 2,5 | **16,8** | S + tiendas |
| 3 | Momentos de intención sin callejones (bróker, diagnóstico, cuota) | 60 | 1 | 50 % | 3 | **10** | S |
| 4 | Degustación de Premium (3 consultas de mercado por mes) | 30 | 2 | 50 % | 4 | **7,5** | M |
| 5 | Hábito del sábado (3 informes completos + push) | 50 | 1 | 40 % | 2,5 + ops | **8** | S–M |

Comparación con lo que queda afuera (mismo método):

| Fuera de noviembre | Score | Por qué no entra |
|---|---|---|
| Prueba de Gold 7 días sin tarjeta (P3) | ~18,7 | Por RICE estaría arriba. No entra por tres razones: (a) hay una decisión vigente del usuario (26/10, "sin prueba de Gold por ahora") y levantarla es de él; (b) es el único cambio **global**: mientras dura la prueba el usuario no ve ningún paywall, así que ensucia la lectura de todo lo demás si se prende junto; (c) el A/B de 3 brazos que propone monetización no da con este volumen. Se propone para diciembre, sola, con línea de base. |
| Orden de planes según motivo (P4, segunda parte) | — | Necesita A/B de ARPU. Diciembre, cuando haya datos por `source`. |
| Primera importación de Binance gratis (E1 variante B) | — | Solo si E1 muestra que la salida gratis no alcanza. Decide monetización. |
| 1 meta gratis en Free (E5) | 5,7 ICE | Diciembre. Toca servidor y gating. |
| Tarjeta compartible y referidos (E6/E7) | 5,0 / 4,3 ICE | Con poco tráfico rinde poco; pasa antes por compliance. |
| Rendimiento real en USD (MEP/CCL) contra benchmark, con fuente | — | Es la mejor oportunidad de diferenciación del doc de mercado, pero es L y hoy F2 usa el tipo oficial. Discovery en diciembre, spec en enero. |
| Fuente visible en cada número del asistente | — | Responde a "4 de cada 5 dudan de la exactitud". Brief en diciembre. |

---

#### 1. Paywall medible y aprobable

- **Problema:** no sabemos qué paywall vende, y el paywall no muestra los términos de renovación ni links a Términos y Privacidad (riesgo de rechazo por Apple 3.1.2 en la próxima revisión, que es justo la del plan anual). Además, el punto de entrada más intencional (Ajustes → "Mejorar plan") muestra un copy heredado ("desbloquear modos").
- **Qué:** eventos `paywall_viewed`, `paywall_plan_tapped`, `purchase_result`, `paywall_dismissed` en `product_events`; `source` obligatorio en cada apertura; `paywall_source` como atributo de RevenueCat; tabla `subscription_events` con el evento crudo del webhook (precio, tienda, tipo de período, entorno); términos de renovación y links; títulos por motivo; medidor de uso solo cuando el motivo es la cuota.
- **Métrica:** 100 % de aperturas con `source` no genérico; tabla paywall visto → compra por `source` disponible el 23/11.
- **Dueños:** porty-flutter-dev (paywall, eventos), porty-backend-dev (webhook, `subscription_events`, `product_funnel`), porty-compliance (texto de renovación).
- **Brief:** `docs/product/briefs/2026-11-02-paywall-medible.md`.
- **Diciembre:** dashboard del embudo (porty-data-analyst), `locked_feature_shown`.

#### 2. Plan anual

- **Problema:** todos los comparables tienen anual (Snowball, getquin, Delta, Copilot, Robinhood Gold) y en finanzas ~la mitad lo elige (dato de terceros, metodología dudosa). Las apps con IA pierden suscriptores ~30 % más rápido: el anual es la defensa más barata contra eso. Porty solo tiene mensual.
- **Qué:** productos `portfolio_premium_annual` y `portfolio_gold_annual`; selector Mensual / Anual en el paywall (sobrio, sin badge saturado, según `diferenciacion-planes.md` §d); ahorro calculado con el precio real de la tienda. Si el offering no tiene anuales, el selector no aparece (se puede publicar el código antes de que la tienda apruebe los productos).
- **Precio propuesto:** 10× el mensual ("2 meses gratis"). **Lo decide el usuario.**
- **Métrica:** % de compras anuales sobre el total; ingreso por comprador a 30 días (`subscription_events.price`).
- **Dueños:** usuario (crear productos esta semana: la revisión tarda), porty-flutter-dev, porty-monetization (configuración del offering).
- **Diciembre:** experimento de orden de planes; oferta introductoria en el anual si se decide prueba de tienda.

#### 3. Momentos de intención sin callejones

Tres cambios chicos en los tres lugares donde el usuario ya mostró intención con sus propios datos. Cada uno con su `source` y su interruptor.

- **3a. El bróker bloqueado deja de ser un callejón (E1).** Free que elige Binance u "Otro bróker" ve solo "Ver planes". Se suma una salida gratis: "Mientras tanto, traela con una captura". "Ver planes" sigue primero. Métrica: % de `onboarding_finished{exit: connectBroker}` que llega a `portfolio_loaded` en 24 h; `broker_connect_result`.
- **3b. Puente al pago al final del diagnóstico (E2).** El diagnóstico termina en "Ir a mi cartera". Se suman una fila tranquila según cómo cargó ("Para que se actualice sola, conectá tu bróker", `source: diagnosis_sync`) y el pedido de aviso del sábado (`push_opt_in{source: diagnosis}`). Sin modal ni urgencia. El diagnóstico sigue completo en Free.
- **3c. Aviso de cuota antes de la pared (P5).** A las 15 de 20, una línea en el chat, una vez por mes. En 0, el paywall dice cuándo vuelven las consultas ("Tus consultas vuelven el 1 de diciembre"). El límite de 20 no cambia.
- **Métrica:** compras atribuidas a `diagnosis_sync`, `binance_connect`, `snaptrade_connect`, `quota_soft`, `quota_zero` a 14 días.
- **Dueños:** porty-flutter-dev; porty-growth-lead (copy en la voz de Porty).
- **Diciembre:** Binance primera importación gratis si 3a no alcanza; la oferta de prueba en el paywall de cuota si se aprueba la prueba.

#### 4. Degustación de Premium

- **Problema:** la escalera está invertida. Gold se prueba (teaser, análisis semanal de cortesía, informe de regalo) y Premium, el escalón barato, corta el turno: "¿qué opinás de NVDA?" hace desaparecer la respuesta y abre una hoja. El usuario pagaría por algo que nunca vio.
- **Qué:** Free recibe 3 consultas de mercado por mes con datos reales ("Consulta de mercado gratis · te quedan 2 este mes"); agotadas, el turno no se corta: Porty responde lo que el plan permite y aparece un teaser de Premium (`source: chat_market_teaser`). Interruptor en `app_config`; espejo en `PlanMatrix` y `plan_limits`.
- **Costo:** ~US$0,02 por Free por mes (supuesto, 3 turnos × ~US$0,006).
- **Métrica:** compras de Premium atribuidas a `chat_market_teaser` a 30 días, contra la cohorte del corte actual (`marketDataLocked`). Guardarraíl: retención Free D30.
- **Dueños:** porty-assistant-dev (gating y teaser en el chat), porty-backend-dev (contador y `plan_limits`), porty-flutter-dev (`PlanMatrix`). Spec de porty-architect: cruza capas.
- **Requiere:** aprobación del usuario (cambia lo que incluye Free).
- **Diciembre:** ajustar el número (2–5) con datos.

#### 5. Hábito del sábado

- **Problema:** el único gancho recurrente de Free es el informe semanal, y se corta a la segunda semana. Sin push, solo lo ve quien abre la app. Las apps con IA retienen peor: Gold necesita valor recurrente.
- **Qué:** las primeras 3 semanas desde el alta con informe completo (N en `app_config.weekly_report`, reversible sin publicar); push del sábado prendido primero para una lista de usuarios y después solo `weekly_report` + `price_alert`.
- **Métrica:** `weekly_report_opened` W2–W4; compras con `source: weekly_report` en la semana 4–5. Se lee en diciembre.
- **Dueños:** porty-backend-dev (`claim_weekly_report`, migración nueva); usuario (F0 de Firebase/APNs según `docs/runbooks/push-notifications.md`).
- **Si el usuario no hace F0 este mes:** se hace igual la parte de los 3 informes (la tarjeta de la Home los muestra), con menos alcance.

---

### Secuencia semana por semana

| Semana | Producto / equipo | Usuario |
|---|---|---|
| **S1 · 2–6 nov** | porty-architect: spec de #1 y #2 (mismo archivo, mismo dev) y spec de #0. porty-flutter-dev + porty-backend-dev construyen #1 y arrancan #0 (la edge function de borrado es lo primero del backend). porty-compliance ya revisó los textos (aplicar H3–H10). | Crear productos anuales en App Store Connect, Play y RevenueCat. Correr Q1–Q8 y `select key, value from app_config;`. Decidir si hace F0 este mes. Aprobar precio anual. Abrir las URLs de Términos y Privacidad y publicarlas corregidas (H2). Crear la página web de borrado que pide Google Play. |
| **S2 · 9–13 nov** | Terminar #0. #2 (selector anual) y #3 (tres cambios chicos) sobre el paywall nuevo. porty-architect: spec de #4. Code, security y UI review; QA de humo de compra **y de borrado** en sandbox. **Release 1 = #0 + #1 + #2 + #3** a revisión, solo si #0 y H2 están cerrados. | Aprobar la publicación del release 1. Aprobar #4 (cambio en Free). |
| **S3 · 16–20 nov** | #4 (assistant + backend + flutter). #5 solo si el backend quedó libre después de #0; si no, pasa a S4 (igual se lee en diciembre). Primer chequeo de calidad de datos: ¿todas las aperturas llegan con `source`? ¿`subscription_events` separa sandbox? | Hacer F0 y prender push para la lista inicial, si se decidió. Aprobar el despliegue de `ai-chat` / migraciones de #4 y #5. |
| **S4 · 23–27 nov** | porty-data-analyst: primera tabla paywall → compra por `source` (~10 días de release 1). Prender #4 y #5 por `app_config`. porty-product-owner: aceptación de #1–#3 y propuesta de diciembre (prueba sí/no, con datos). | Aprobar prender los interruptores de #4 y #5 en producción. Decidir la prueba de Gold para diciembre. |

### Diciembre (tentativo, se decide el 27/11 con datos)

1. **Prueba de Gold de 7 días sin tarjeta**, si el usuario levanta la decisión del 26/10: sola, con línea de base, un solo brazo detrás de interruptor, tope de 100 consultas y búsquedas al nivel de Premium.
2. Orden de planes según motivo (si hay volumen, A/B de ARPU; si no, antes/después).
3. Lectura de #4 y #5; ajustar el número de degustaciones y de informes.
4. Discovery de "rendimiento real en USD (MEP/CCL) contra benchmark, con fuente".
5. Brief de "de dónde sale cada número" en las respuestas del asistente.
6. 1 meta gratis en Free y tarjeta compartible, después de compliance.
