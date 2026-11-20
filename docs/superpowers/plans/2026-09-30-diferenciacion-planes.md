# Diferenciación de planes: propuesta post-FASE 1

**Fecha:** 2026-09-30 · **Estado:** propuesta (solo documento, nada implementado) · **Rama de referencia:** `feature/ui_redesign`

## Resumen

La FASE 1, que alguien está implementando ahora, deja la matriz de planes como fuente única de verdad (`lib/domain/subscription/plan_matrix.dart`). También deja el "Incluido en el plan Gold" tocable con preview, un análisis Gold gratis por semana y el desbloqueo en el lugar después de la compra. Este documento propone qué hacer después y en qué orden:

1. **Antes de cualquier feature nueva conviene arreglar dos cosas chicas.** Primero, el webhook de RevenueCat, que hoy baja a Free a un usuario que tenga otra suscripción activa. Segundo, registrar el costo real de cada turno. Sin eso las decisiones de precio y límites se toman a ciegas.
2. **Precio anual (d)** y **prueba de Gold de 7 días con entitlement promocional (c)**: son de esfuerzo bajo, impacto directo en ingresos y conversión, y casi no requieren infraestructura nueva.
3. **Resumen semanal (a)** generado del lado del cliente la primera vez que se abre la app en la semana. No necesita backend programado ni push. Con un prompt dedicado cuesta **~US$0,004 por usuario por semana** (estimado).
4. **Límites como seguro (e)**: no bajar el límite de Gold ahora. Primero hay que medir 60 días. El riesgo real está en el peor caso (un usuario Gold que usa las 1000 consultas cuesta ~US$13), no en el usuario típico.
5. **Avisos proactivos (b)** al final. Es lo más caro en infraestructura: las posiciones hoy viven solo en el dispositivo (Hive), no hay push, y hace falta una key de Finnhub paga del lado del servidor a partir de ~100–150 usuarios Gold.

### Estructura de planes acordada

| | **Free** | **Premium** | **Gold** |
|---|---|---|---|
| Pregunta que responde | "¿Cómo está mi cartera?" | "¿Cómo está el mercado?" | "¿Qué significa, qué está pasando y por qué?" |
| Cartera propia (posiciones, P&L) | ✔ (con tope de posiciones) | ✔ sin tope | ✔ sin tope |
| Cualquier ticker, gráficos, comparaciones | — | ✔ | ✔ |
| Simulaciones y metas | — | ✔ | ✔ |
| Análisis de empresa (`QaCompanyAnalysis`) | 1 gratis/semana (FASE 1) | 1 gratis/semana (FASE 1) | ✔ |
| Noticias, earnings, fundamentals | — | — | ✔ |
| Resumen semanal, avisos (futuro) | — | — | ✔ |
| Consultas/mes (`_monthly_quota`) | 20 | 500 | 1000 |

> Nota: `SubscriptionPolicy.isAdviceAllowed` hoy devuelve `true` solo para Gold. La estructura nueva pasa simulaciones y metas a Premium, y eso queda cubierto por la matriz de FASE 1.

---

## Qué hay hoy en el repo (relevante para todo lo que sigue)

| Pieza | Estado | Dónde |
|---|---|---|
| Suscripciones | RevenueCat (`purchases_flutter ^10.12.0`), offering `default` con `premium_monthly` / `gold_monthly` | `lib/features/subscription/config/subscription_catalog.dart`, `services/revenue_cat_service.dart` |
| Tier en servidor | Webhook RevenueCat → RPC `upsert_subscription_from_provider` | `supabase/functions/revenuecat-webhook/index.ts` |
| Cuota | RPC `consume_ai_quota(p_weight)`, tabla `ai_usage_monthly` | `supabase/migrations/20260611000000_subscription_tiers.sql` |
| Edge functions | **Solo** `revenuecat-webhook` | `supabase/functions/` |
| Cron / pg_cron | **No existe** | — |
| Push | **No hay** `firebase_messaging`, `flutter_local_notifications` ni OneSignal. Sí hay Firebase (`firebase_remote_config`), así que el proyecto Firebase ya existe | `pubspec.yaml` |
| Deep links | `go_router ^14.2.7`. No hay esquema propio ni intent-filters aparte del launcher | `lib/config/navigation/app_router.dart`, `android/app/src/main/AndroidManifest.xml` |
| Posiciones | **Solo locales en Hive** (`Box<PositionModel>`). El servidor no conoce la cartera | `lib/infraestructure/data_sources/position_local_data_source_impl.dart` |
| OpenAI | Se llama **desde el cliente** con `OPENAI_API_KEY` de `.env` | `lib/features/genui_core/services/openai_raw_chat_client.dart` |
| Finnhub | Key free compartida, también desde el cliente (`FINNHUB_API_KEY`). Caché en memoria por dispositivo (earnings 6 h, noticias 10 min) | `lib/infraestructure/data_sources/finnhub_http_client.dart`, `lib/features/assistant/data/market/*_fetcher.dart` |
| Veracidad | Grounding check y rechazo de números en prosa que no vienen de tools | `lib/features/assistant/utils/assistant_grounding_check.dart`, `assistant_answer_review.dart` |

Tres hallazgos que condicionan el plan:

- **Bug latente en el webhook.** Ante `EXPIRATION` pone `tier = free` sin mirar si el usuario tiene otro entitlement activo. Con la prueba promocional (c) o con upgrades mensual→anual esto pasa a ser un bug real: si vence la promo Gold, un usuario que paga Premium quedaría en Free en Supabase. El arreglo: ante cualquier evento, pedirle a RevenueCat el `CustomerInfo` del usuario (`GET /v1/subscribers/{id}`) y calcular el tier más alto que tenga activo. Esfuerzo: ~0,5–1 día.
- **La key de OpenAI está en el binario.** La cuota de `consume_ai_quota` la respeta la app honesta, pero alguien que extraiga la key la saltea. Para (a) está bien, pero (b) y cualquier generación del lado del servidor necesitan la key en los secrets de Supabase. A mediano plazo conviene un proxy (edge function), y eso además vuelve real la cuota.
- **Licencia de Finnhub.** El plan free es para uso personal y no comercial ([pricing Finnhub](https://finnhub.io/pricing), [planes de stock API](https://www.finnhub.io/pricing-stock-api-market-data)). Una app que cobra suscripciones ya está afuera de ese uso, con o sin avisos. Esto es independiente de este documento, pero conviene tenerlo presente al presupuestar.

---

## a) Resumen semanal de cartera escrito por Porty (Gold)

> **Reemplazada (2026-10-01)** por `2026-10-01-informe-semanal-porty.md`, que la lleva a la Home, le suma super investors y la actualiza a la infraestructura actual (posiciones en Supabase, proxy `ai-chat`). Lo que sigue queda como contexto histórico.

### Qué es

Un único mensaje por semana con tres bloques:
1. **Qué se movió**: el cambio de la cartera en la semana y los 3 mayores movimientos entre sus posiciones.
2. **Por qué**: 1–2 frases por movimiento, basadas en titulares reales.
3. **Qué viene**: earnings de sus tickers en los próximos 7 días.

No consume cuota de consultas.

### Cómo se vería

- **Dónde:** como primer mensaje de Porty en la conversación de esa semana, renderizado por un widget de catálogo nuevo, `QaWeeklySummary`. Además, una fila compacta en home ("Tu semana, por Porty") que lleva a ese mensaje. Para Free/Premium esa fila aparece con el tratamiento "Incluido en el plan Gold" de FASE 1: se puede tocar, abre el paywall con un preview estático y no se ve contenido real.
- **Estructura del widget:** encabezado "Semana del 22 al 26 de sep." y el cambio de la cartera en cifras tabulares. Debajo, lista de 3 movers (logo client-side, ticker, % semanal) con una línea de "por qué" debajo de cada uno y la fuente del titular como texto secundario. Cierra con "Qué viene", una lista de fechas de earnings. Es una sola superficie, sin cards anidadas: los bloques se separan con espacio y divisores finos. El terracota se usa solo en el avatar y el acento de Porty.
- **Cómo entra:** mientras se genera, la fila de home muestra texto estático ("Porty está preparando tu semana…") con altura reservada. Cuando está listo, crossfade de ~220 ms `easeOutCubic` dentro de `AnimatedSize`, sin saltos de layout. El mensaje en el chat entra con `RevealEntrance` (`lib/features/assistant/catalog/widgets/reveal_step.dart`): fade, slide corto y haptic suave vía `PortyHapticsService`, con los bloques escalonados. Con reduce motion se ve el estado final. Si se reconstruye el historial, el resumen no se vuelve a animar (`skip` de `RevealEntrance`).

### Trigger: dos opciones

| | (1) Primera apertura de la semana (cliente) | (2) Job semanal en servidor + push |
|---|---|---|
| Infraestructura nueva | 1 tabla + 1 RPC | Sync de posiciones al servidor, key OpenAI/Finnhub en servidor, Supabase Cron, FCM/APNs |
| Cuándo lo ve | Al abrir la app | Lunes 8:00 hora local, aunque no abra la app |
| Retención | Menor (solo quien abre) | Mayor (la notificación trae de vuelta) |
| Costo LLM | Solo usuarios activos esa semana | Todos los Gold. Con [Batch API](https://developers.openai.com/api/docs/pricing) sale 50% más barato |
| Esfuerzo | ~4–6 días | ~12–18 días (la mayor parte se comparte con b) |
| Riesgo | Latencia visible la primera vez (5–15 s) | Privacidad (tickers en servidor), más piezas que operar |

**Recomendación: (1) ahora.** Cuando exista la infraestructura de (b), migrar a (2) reutilizándola, y el mismo widget sirve para el payload generado en servidor.

### Implementación técnica (opción 1)

- **Supabase (migración nueva):** tabla `weekly_summaries (user_id, iso_week, status, payload jsonb, created_at)` con `unique(user_id, iso_week)`. RPC `claim_weekly_summary(p_iso_week)` que verifica que el tier sea Gold (`user_subscriptions`) e inserta `status='generating'` si no existe. Así es idempotente entre dispositivos y no se genera dos veces. Después, `complete_weekly_summary(p_iso_week, p_payload)`. **No llama a `consume_ai_quota`.**
- **Datos (determinísticos, sin tool loop):** un servicio nuevo `lib/features/assistant/services/weekly_summary_service.dart` que:
  - toma las posiciones de `PositionRepositoryImpl`,
  - pide el cambio de 5 días a Yahoo (`yahoo_quote_remote_data_source.dart`, `range=5d`),
  - toma 2–3 titulares por mover de `news_fetcher.dart` (Google News RSS + `news_relevance_ranker.dart`),
  - pide 1 llamada a `earnings_fetcher.dart` para el rango de los próximos 7 días.
- **LLM:** una sola llamada con un **prompt dedicado compacto** (`lib/features/assistant/prompts/weekly_summary_prompt.dart`). El modelo recibe los datos ya calculados y devuelve solo prosa por slot (`why[ticker]`, `closing`). Todos los números los pone la app desde los datos, igual que en `QaCompanyAnalysis`. La prosa pasa por el mismo chequeo de números que ya rechaza cifras que no vienen de tools. Si falla, se reintenta una vez y, si vuelve a fallar, se muestra el widget sin "por qué" (solo datos).
- **Gating:** `PlanFeature.weeklySummary` nuevo en `plan_matrix.dart`.

### Costo estimado por usuario por semana (gpt-4.1-mini: US$0,40/M input, US$0,10/M cacheado, US$1,60/M output, [verificado](https://developers.openai.com/api/docs/pricing))

| Variante | Tokens (estimado) | Costo/usuario/semana | Por mes |
|---|---|---|---|
| **Prompt dedicado compacto**, 1 llamada, caché frío | ~3K prompt + ~4K datos = 7K in · ~600 out | 7K×0,40 + 0,6K×1,60 ≈ **US$0,0038** | ~US$0,016 |
| Prompt completo del asistente (~24,3K) con tool loop de ~3 rondas | 1ª ronda 24,3K fría + 2 rondas ~26K mayormente cacheadas · ~800 out | 0,0097 + ~0,0065 + 0,0013 ≈ **US$0,017** | ~US$0,075 |

Con 1.000 usuarios Gold activos, el prompt dedicado cuesta unos US$16/mes contra ~US$75/mes con el prompt completo. La diferencia en plata es chica, pero el prompt dedicado además es más rápido (menos latencia en la primera apertura) y más fácil de testear en evals.

**Datos:** ~8 llamadas a Yahoo (una por ticker, gratis, no oficial), ~3–6 a Google News RSS y **1 a Finnhub** (`/calendar/earnings`) por usuario por semana. Contra la key compartida de 60 req/min, es despreciable.

### Esfuerzo: ~4–6 días-persona (estimado)

Tabla + RPC 1, servicio de datos 1, prompt + evals 1–1,5, widget + fila en home 1–1,5, tests 0,5–1.

### Riesgos

- **Semana sin noticias relevantes para un mover:** el "por qué" tiene que poder decir "no encontramos una noticia que lo explique". Hay que exigirlo en el prompt y cubrirlo en los evals.
- **Atribución causal falsa** ("bajó por X" cuando X no lo explica): usar formulaciones prudentes ("coincidió con…") como regla del prompt.
- **Cartera vacía o de 1 posición:** estado vacío explícito, sin llamada al LLM.
- **ToS de Google News** (uso personal): el mismo riesgo que ya existe en `get_news`.

---

## b) Avisos proactivos (Gold)

### Qué es

Notificaciones push de tres tipos:
- **Earnings:** "NVDA reporta mañana después del cierre".
- **Movimiento de precio:** "AAPL bajó 5,2% hoy".
- **Noticia importante:** "Noticia relevante sobre MSFT".

Solo sobre tickers de la cartera propia.

### Cómo se vería

- **Notificación:** título con el ticker y el hecho, en una línea, sin emojis ni signos de exclamación. Si hay varios eventos del mismo tipo el mismo día, se agrupan: "3 de tus acciones se movieron más de 5% hoy".
- **Al tocar:** deep link a Porty con una pregunta precargada **ya respondida**. Por ejemplo, para "AAPL bajó 5%", se abre el chat con "¿Por qué bajó AAPL hoy?" y la respuesta entra con `RevealEntrance`. La respuesta originada en un aviso **no consume cuota**: el servidor emite un `alert_id` y el cliente lo pasa a una RPC que marca el uso. Para earnings, la respuesta abre la card de earnings del ticker.
- **Settings:** sección "Avisos" con toggles por tipo, umbral de movimiento (3/5/8%), horario silencioso y silenciar ticker. Targets ≥44 px, cambios de estado con crossfade de 200–250 ms. En Free/Premium la sección aparece con "Incluido en el plan Gold".

### Infraestructura necesaria (qué falta)

1. **Tickers en el servidor.** Tabla `user_watch_symbols (user_id, symbol, updated_at)`, sincronizada desde `PositionRepositoryImpl` al crear, editar o borrar posiciones. Se suben solo símbolos, no cantidades (por privacidad, y alcanza para los avisos). Hay que mencionarlo en la política de privacidad.
2. **Push.** Agregar `firebase_messaging` (el proyecto Firebase ya existe por Remote Config), subir la APNs auth key a Firebase y crear la tabla `push_tokens (user_id, token, platform, tz, updated_at)`. Opcional: `flutter_local_notifications` para mostrar avisos con la app en primer plano.
3. **Backend programado.** Supabase Cron (pg_cron + pg_net) invocando edge functions ([guía oficial](https://supabase.com/docs/guides/functions/schedule-functions)). Funciones nuevas en `supabase/functions/`:
   - `alerts-scan-earnings`: diario, 1 llamada.
   - `alerts-scan-prices`: 2 veces por día hábil, a mitad de sesión y al cierre.
   - `alerts-scan-news`: 1 vez por día.
   - `send-push`: FCM HTTP v1, aplica reglas y deduplicación.
4. **Keys del lado del servidor.** Finnhub (idealmente paga, ver abajo) y OpenAI solo si el aviso de noticia lleva resumen. Recomendación: que no lo lleve; el título alcanza y la explicación la da Porty al tocar.
5. **Tablas de control:** `alert_preferences`, `alerts_sent (user_id, symbol, type, day)` para deduplicación y tope diario.
6. **Deep link:** payload `{route: '/assistant', prompt, alert_id, card}`, manejado con `FirebaseMessaging.onMessageOpenedApp` y `getInitialMessage` → `app_router.dart` y `lib/features/assistant/nav/assistant_router.dart`.

### Carga sobre Finnhub, con deduplicación de tickers

Supuestos (estimados, a validar con datos reales de `user_watch_symbols`):
- 8 tickers promedio por usuario.
- Distribución tipo Zipf: pocos tickers (AAPL, NVDA, MSFT, SPY, VOO…) concentran gran parte de las tenencias. El universo total de tickers únicos crece mucho más lento que los usuarios.
- Por tipo de señal:
  - **Earnings:** 1 llamada diaria a `/calendar/earnings?from=hoy&to=hoy+7`, en bloque y sin depender de la cantidad de usuarios (puede necesitar 2 si la respuesta se trunca; a verificar).
  - **Precio:** 1 `/quote` por ticker único por ciclo, 2 ciclos por día.
  - **Noticias:** 1 `/company-news` por ticker único por día.

| Usuarios Gold | Tickers sin dedup (×8) | **Tickers únicos (estimado)** | Earnings/día | Precio/ciclo | Noticias/día | Total/día | Minutos por ciclo de precio a 60 req/min | … a 30 req/min (mitad de la key para el backend) |
|---|---|---|---|---|---|---|---|---|
| 100 | 800 | ~350 | 1–2 | 350 | 350 | ~1.050 | ~6 | ~12 |
| 1.000 | 8.000 | ~1.500 | 1–2 | 1.500 | 1.500 | ~4.500 | ~25 | ~50 |
| 10.000 | 80.000 | ~4.000 | 1–2 | 4.000 | 4.000 | ~12.000 | ~67 | ~133 |

La deduplicación reduce la carga entre 2,3× y 20×, y es lo que vuelve viable el diseño. Aun así, **la key free es compartida con el tráfico interactivo de todos los usuarios de la app**, que ya pega contra el mismo límite desde los dispositivos.

**¿Desde cuántos usuarios hace falta pagar?** Si queremos que un ciclo de precios termine en ≤15 min usando como mucho la mitad de la key free, entran ~450 tickers únicos, o sea **~100–150 usuarios Gold**. Además, por licencia, el plan free no cubre uso comercial ([Finnhub pricing](https://finnhub.io/pricing)).

Planes pagos del stock API según la [página de precios](https://www.finnhub.io/pricing-stock-api-market-data): Basic ~US$49,99/mes (150 req/min), Standard ~US$129,99/mes (300 req/min), Professional ~US$199,99/mes (900 req/min). Esas cifras hay que confirmarlas. También hay que confirmar con Finnhub qué licencia cubre mostrar datos a usuarios finales en una app paga, porque los planes publicados figuran como uso personal y la licencia comercial se negocia aparte. Con 150 req/min, 1.500 tickers se recorren en ~10 min, así que alcanza hasta ~1–2k usuarios Gold. Con 10k conviene 900 req/min o un proveedor con snapshot masivo (un endpoint que devuelve todos los tickers de EE. UU. en una llamada, como el de Polygon.io/Massive; precio y licencia a verificar).

Alternativa para precio: Yahoo `v8/finance/chart` (lo que ya usa la app), gratis pero no oficial. Desde IPs de datacenter suele devolver 429, así que no la recomiendo como base de un backend.

Contexto: 100 usuarios Gold × US$15 × 0,85 ≈ US$1.275/mes de ingreso neto, así que US$50–130/mes de datos es razonable.

### Reglas para no molestar

- **Precio:** avisar si |Δ intradía| ≥ umbral elegido (default 5%) **y** además ≥ 2× la variación diaria media de 30 días del ticker. Así no se avisa cada día por una acción volátil. Máximo 1 aviso de precio por ticker por día.
- **Earnings:** el día anterior a las 18:00 hora local. Solo "antes/después del cierre", sin estimaciones en el texto.
- **Noticias:** solo si `news_relevance_ranker.dart` supera un umbral alto y la fuente está en `news_media_index.dart`. Máximo 1 por ticker por día. Hay que portar esa lógica a TypeScript, o compartir las reglas como datos.
- **Tope global:** 3 avisos por día por usuario. Lo que exceda se agrupa en uno solo.
- **Horario silencioso:** 22:00–08:00 hora local por defecto, configurable. Lo que cae adentro se descarta (precio) o se difiere a las 08:00 (earnings).
- **Defaults conservadores:** earnings activado; precio y noticias activados con el umbral de 5%. El primer aviso de cada tipo incluye "Podés ajustar esto en Ajustes".

### Costo operativo (estimado)

- FCM: gratis.
- Invocaciones de edge functions: holgadas dentro del plan de Supabase (algunas miles por día).
- Finnhub: US$0 hasta ~100–150 Gold (con el riesgo de licencia); después ~US$50–200/mes.
- OpenAI: solo las respuestas al tocar. Del orden de US$0,01 por aviso tocado; con un 30% de tap-through y 1 aviso cada 2 días, ~US$0,05 por usuario por mes.

### Esfuerzo: ~15–22 días-persona (estimado)

Sync de símbolos 2, push y tokens 3, cron + 4 edge functions 5–7, reglas y deduplicación 2–3, preferencias en Settings 2, deep link + respuesta precargada 2–3, QA en dispositivos 2.

### Riesgos

- Falsos positivos que generen desinstalaciones o bajas de permisos de notificación. Por eso los topes y los defaults conservadores.
- Datos erróneos del proveedor que disparen un "bajó 30%" por un split mal ajustado: exigir que el movimiento aparezca también en un segundo dato (cierre previo de Yahoo) antes de enviar.
- Privacidad: los tickers pasan a vivir en el servidor.
- Operación: primer backend que "corre solo". Necesita logs y alertas si falla un scan.

---

## c) Prueba de Gold de 7 días al registrarse, "que después baja al plan que eligió"

### Qué permiten las tiendas

- **Una free trial de tienda convierte en el mismo producto que la inició.** Si el usuario empieza la prueba en `portfolio_gold_monthly`, al día 7 se le cobra Gold. Para terminar en Premium, el usuario tendría que hacer un downgrade durante la prueba. En iOS, un downgrade dentro del grupo toma efecto en la próxima fecha de renovación ([Apple: auto-renewable subscriptions](https://developer.apple.com/app-store/subscriptions/), [App Store Connect Help](https://developer.apple.com/help/app-store-connect/reference/auto-renewable-subscription-information/)). En Play se programaría con un replacement mode diferido. Técnicamente se puede, pero requiere una segunda compra en el flujo de onboarding: confuso y frágil.
- **Elegibilidad:** en iOS hay una sola oferta introductoria por grupo de suscripción. Quien la usó en Gold no puede usarla después en Premium del mismo grupo, y quien hace upgrade o downgrade no es elegible ([RevenueCat: subscription offers](https://www.revenuecat.com/docs/subscription-guidance/subscription-offers)). En Google Play la elegibilidad va por base plan/oferta y la puede determinar Google o el desarrollador (misma fuente).
- **Entitlement promocional de RevenueCat:** se otorga del lado del servidor con `POST /v1/subscribers/{app_user_id}/entitlements/{entitlement_id}/promotional` (con duración o `end_time_ms`), sin transacción de tienda. Se aplica en simultáneo con cualquier compra, sin reemplazarla ni diferirla, y se puede revocar ([RevenueCat API v1: entitlements](https://www.revenuecat.com/docs/api-v1/entitlements)).

### Comparación

| | Trial de tienda en Gold | **Entitlement promocional (recomendado)** |
|---|---|---|
| Qué ve el usuario al final | Se le cobra Gold, salvo que haya cancelado o bajado de plan | Vuelve a Free, o sigue en Premium si lo compró. "Baja al plan que eligió" sin hacer nada |
| Tarjeta requerida | Sí (hay que pasar por el sheet de la tienda) | No |
| Riesgo de cobro no deseado y reembolsos | Alto: el principal motivo de quejas en reseñas | Nulo |
| Política de tienda | Hay que explicar claramente precio y renovación | No es una compra, así que las reglas de trials no aplican. Igual hay que comunicarlo honestamente como "7 días de Gold de regalo" |
| Abuso por cuentas nuevas | La tienda limita por Apple ID/cuenta Google | Limitado por `user_id` de Supabase. Se puede abusar con emails nuevos. Mitigación: email verificado y tope de consultas durante la prueba |
| Reinstalación | Lo maneja la tienda | Sin impacto: vive en RevenueCat por `app_user_id` y no se vuelve a otorgar |
| Conversión | Alta (opt-out) | Menor por usuario (opt-in), pero sin fricción de entrada |

**Recomendación:** entitlement promocional para la prueba al registrarse. Más adelante se puede sumar una trial de tienda solo en el producto Gold para quien lo elige en el paywall, que es el caso donde "convierte en lo mismo" es justo lo que se busca.

### Cómo se vería

Después del registro, una pantalla sobria: "Tenés 7 días de Gold" con 3 ejemplos concretos (análisis, noticias de tus acciones, resumen semanal) y un botón "Empezar". En Settings > Suscripción aparece "Gold de regalo · quedan 4 días", en cifras tabulares. En el día 6 (o dentro de la app si no hay push todavía) aparece un aviso: "Mañana termina tu prueba de Gold", con acceso al paywall. Al vencer no hay pantalla bloqueante: los widgets Gold pasan al estado "Incluido en el plan Gold" de FASE 1.

### Implementación técnica

- Edge function nueva `supabase/functions/grant-trial` que llama a la API de RevenueCat con la secret key en los secrets de Supabase. Se invoca una vez desde el cliente después del primer login y es idempotente: tabla `trial_grants (user_id unique, granted_at, ends_at)`.
- **Arreglar `revenuecat-webhook`** (ver arriba): hoy `tierFromProductId` deduce el tier del `product_id` y `EXPIRATION` fuerza Free. Los promocionales llegan con un product id sintético, cuyo formato hay que verificar en los eventos reales. El webhook tiene que recalcular el tier consultando el subscriber.
- Cliente: `subscription_provider.dart` ya lee entitlements de RevenueCat, así que el promocional se refleja sin cambios en el gating. Para "quedan N días" se usa `expirationDate` del entitlement.
- Cuota durante la prueba: al quedar el tier en Gold, `_monthly_quota` da 1000. Sugiero un tope de prueba (por ejemplo 100) con una columna `is_trial` en `user_subscriptions`, para acotar el abuso.

**Esfuerzo:** ~3–4 días-persona (incluye el arreglo del webhook). **Costo:** RevenueCat no cobra por los promocionales (el fee se calcula sobre ingresos). El costo en LLM de un usuario de prueba típico es ~50 turnos × US$0,01 = **US$0,50**, con un peor caso acotado por el tope de US$1,30.

**Riesgos:** abuso por cuentas múltiples (acotado y barato); webhook mal recalculado (cubrir con tests de secuencias como promo→compra Premium→vence promo); expectativa de "gratis para siempre" si la comunicación no es clara.

---

## d) Precio anual con descuento (2 meses gratis)

### Qué se configura fuera de la app

- **App Store Connect:** productos nuevos `portfolio_premium_annual` y `portfolio_gold_annual` en **el mismo grupo** que los mensuales. Gold anual va en el mismo nivel de servicio que Gold mensual y Premium anual en el mismo nivel que Premium mensual. Así, mensual↔anual del mismo tier es un crossgrade: con duración distinta toma efecto en la renovación ([App Store Connect Help](https://developer.apple.com/help/app-store-connect/reference/auto-renewable-subscription-information/)).
- **Google Play Console:** agregar un base plan `annual` a cada suscripción existente. Nota: el product id existente dice `monthly`. Funciona igual, pero conviene decidir si se crean suscripciones nuevas con nombres neutros.
- **RevenueCat:** asociar los productos nuevos a los entitlements `premium` y `gold`, y agregar packages `premium_annual` / `gold_annual` (o `$rc_annual`) al offering `default`. Se puede crear un offering alternativo para hacer un A/B test de precios más adelante.
- **Precio:** 10× el mensual, o sea US$100 Premium y US$150 Gold (o US$200 si Gold pasa a US$20).

### Qué cambia en la app

- `lib/features/subscription/config/subscription_catalog.dart`: ids de packages anuales y `packageIdFor(tier, period)`.
- `lib/features/subscription/providers/subscription_provider.dart`: `subscriptionTierPricesProvider` pasa a devolver precio por tier **y período**, y el ahorro se calcula con los `StoreProduct` reales (no hardcodeado, para que funcione con precios locales).
- `lib/features/subscription/ui/subscription_paywall_sheet.dart`: selector Mensual / Anual (segmented control ≥44 px). El precio cambia con crossfade de ~220 ms y "2 meses gratis" va como texto secundario, sin badge saturado. El anual se muestra como precio total más el equivalente mensual en cifras tabulares.
- `revenuecat-webhook`: `tierFromProductId` ya detecta `gold`/`premium` dentro del id, así que no cambia (pero el arreglo de recálculo aplica igual).

**Esfuerzo:** ~2–3 días-persona, más el tiempo de revisión de las tiendas. **Costo operativo:** ninguno adicional. Un año adelantado mejora el cash flow y baja el churn. Apple cobra 15% desde el segundo año de suscripción continua, o siempre 15% con el Small Business Program; Google cobra 15% en suscripciones.

**Riesgos:** reembolsos de anuales (en Apple los decide Apple); la confusión mensual→anual del mismo tier se evita dejando la gestión al sheet de la tienda.

---

## e) Límites de consultas como seguro, no como argumento de venta

### Unit economics (estimado, por usuario y por mes)

Costo por turno: US$0,007–0,013 real (se usa US$0,013 para el peor caso y ~US$0,010 para el típico). Uso típico supuesto: ~20% de la cuota (hipótesis, no medido).

| Plan | Precio | Neto con 15% | Neto con 30% | Peor caso (cuota completa × 0,013) | Margen peor caso (15% / 30%) | Típico (20% × 0,010) |
|---|---|---|---|---|---|---|
| Free | US$0 | — | — | 20 × 0,013 = **US$0,26** | −0,26 | ~US$0,04 |
| Premium | US$10 | 8,50 | 7,00 | 500 × 0,013 = **US$6,50** | +2,00 / +0,50 | ~US$1,00 |
| Gold | US$15 | 12,75 | 10,50 | 1000 × 0,013 = **US$13,00** | **−0,25 / −2,50** | ~US$2,00 |
| Gold | US$20 | 17,00 | 14,00 | US$13,00 | +4,00 / +1,00 | ~US$2,00 |

Sin contar Finnhub pago, el resumen semanal (~US$0,02/mes), los avisos (~US$0,05/mes) ni el fee de RevenueCat. Conclusión: el usuario típico es muy rentable en ambos planes, pero **Gold a US$15 pierde plata en el peor caso**. Hay dos formas de cerrar esa brecha: subir el precio a US$20 o limitar el peor caso. No hace falta tocar la cuota típica.

### Recomendación

1. **No vender el número.** El paywall comunica qué responde cada plan, no "1000 consultas". La cuota se presenta como "uso justo".
2. **No bajar el límite de Gold a quien ya pagó.** Sería quitar un beneficio comprado, con riesgo de reclamos y reembolsos. Si después de medir hace falta bajarlo:
   - aplicarlo **solo a suscripciones nuevas**, con una columna `quota_policy_version` en `user_subscriptions` que se fija en la compra y hace que `_monthly_quota(tier, version)` respete la versión (grandfathering);
   - publicar una **política de uso justo** en los términos antes del cambio.
3. **Límites blandos antes que duros:** un tope diario (por ejemplo 80/día en Gold) corta el peor caso real, que suele ser uso automatizado o compulsivo, sin afectar a nadie típico. Al llegar al 80% mensual, un aviso discreto en la barra de cuota. Opción a evaluar: pasado el 100%, seguir respondiendo con un modelo más barato (gpt-4.1-nano cuesta 1/4) en vez de cortar. Hay que medir la calidad en evals antes.
4. **La key en el cliente** vuelve la cuota evitable para un atacante. El "seguro" completo requiere el proxy en una edge function (ver hallazgos).

### Datos a juntar primero (60 días)

- **Costo real por turno:** guardar el `usage` de cada respuesta de OpenAI (`prompt_tokens`, `cached_tokens`, `completion_tokens`, cantidad de rondas de tools) en una tabla `ai_turn_usage (user_id, created_at, tier, prompt_tokens, cached_tokens, completion_tokens, tool_rounds, cost_usd)` mediante una RPC `log_ai_turn_usage`, llamada desde `assistant_openai_service.dart` / `openai_raw_chat_client.dart`.
- **Distribución mensual por usuario y tier:** p50/p90/p99 de consultas (ya está en `ai_usage_monthly`) y costo por usuario.
- **Tasa de caché por sesión**, para confirmar el rango US$0,007–0,013.
- **Correlación uso↔retención:** si los que más usan son los que más renuevan, el tope diario tiene que quedar bien por encima de p99.

**Esfuerzo:** logging ~1–1,5 días; tope diario + grandfathering ~1,5–2 días, solo si los datos lo justifican.

---

## f) Orden recomendado después de la FASE 1

| # | Item | Impacto | Esfuerzo (estimado) | Riesgo | Dependencias / por qué en este orden |
|---|---|---|---|---|---|
| 0 | **Arreglo del webhook + logging de costo por turno** | Habilita todo lo demás | 1,5–2,5 d | Bajo | El webhook es prerrequisito de (c) y (d). El logging es prerrequisito de (e) y conviene que corra lo antes posible para acumular datos |
| 1 | **d) Precio anual** | Medio-alto (ingresos, churn) | 2–3 d + revisión de tiendas | Bajo | Solo configuración y paywall. Aprovecha que el paywall se está tocando en FASE 1 |
| 2 | **c) Prueba Gold 7 días (promocional)** | Alto (muestra Gold a todos los nuevos) | 3–4 d | Bajo-medio | Necesita el webhook arreglado. Gana valor cuando Gold tiene más contenido, pero el análisis de FASE 1 ya alcanza |
| 3 | **a) Resumen semanal (trigger cliente)** | Alto (valor Gold recurrente, retención) | 4–6 d | Medio (calidad de la prosa) | Reutiliza la veracidad del análisis. Hace que la prueba de (c) muestre algo que el usuario no pidió |
| 4 | **e) Ajuste de límites** | Protección de margen | 1,5–2 d | Medio (percepción) | Solo con ≥60 días de datos de #0. Decidir junto con el precio de Gold (US$15 vs US$20) |
| 5 | **b) Avisos proactivos** | Alto, pero en pocos usuarios al principio | 15–22 d | Alto (infra nueva, licencia, molestia) | Requiere sync de posiciones, push, cron, key paga. Cuando exista, migrar (a) al trigger de servidor. Conviene esperar a tener ≥50–100 Gold para que el costo fijo se justifique |

Criterio: primero lo que desbloquea medición y corrige riesgos de facturación, después lo que mueve ingresos con poco esfuerzo, después el valor recurrente de Gold y al final la infraestructura pesada, cuando haya usuarios que la paguen.

---

## Fuentes

- OpenAI, precios de API (gpt-4.1-mini, gpt-4.1-nano, Batch 50%): https://developers.openai.com/api/docs/pricing
- Finnhub, precios y licencia: https://finnhub.io/pricing · https://www.finnhub.io/pricing-stock-api-market-data
- RevenueCat, API v1 de entitlements (promocionales): https://www.revenuecat.com/docs/api-v1/entitlements
- RevenueCat, ofertas de suscripción y elegibilidad: https://www.revenuecat.com/docs/subscription-guidance/subscription-offers
- Apple, auto-renewable subscriptions: https://developer.apple.com/app-store/subscriptions/
- Apple, App Store Connect Help (upgrade/downgrade/crossgrade): https://developer.apple.com/help/app-store-connect/reference/auto-renewable-subscription-information/
- Apple, Small Business Program: https://developer.apple.com/app-store/small-business-program/
- Google Play, service fees: https://support.google.com/googleplay/android-developer/answer/112622
- Supabase, programar edge functions (pg_cron + pg_net): https://supabase.com/docs/guides/functions/schedule-functions

> Todas las cifras de esfuerzo, tickers únicos, uso típico y tokens son **estimaciones**. Las de precios de terceros se verificaron el 2026-09-30, salvo donde dice "a verificar".
