# Embudo a pago y economía por plan

**Fecha:** 2026-11-02 · **Autor:** porty-data-analyst · **Pregunta:** "¿Qué deberíamos construir este mes para conseguir más usuarios que paguen?"

**Alcance:** todo sale de leer el repo. **No hay ningún dato de producción en este documento.** Cada número está marcado así:

- **[medido]**: está en el código, en una migración o en un doc del repo que dice que se midió.
- **[supuesto]**: lo estimo yo o lo tomé de un doc anterior que lo marca como estimación. Para confirmarlo hay que correr las consultas de la sección 6.

---

## 1. Conclusión

1. **Hoy no podemos medir la conversión a pago.** El embudo está instrumentado desde el alta hasta la primera respuesta del chat (`product_events`, del 2026-10-26, con ~1 semana de datos). Del paywall en adelante no hay nada persistido: `PaywallSourceLog` guarda solo en memoria y en `debugPrint`, no hay evento de compra y `user_subscriptions` guarda solo el estado actual. La compra se puede reconstruir a medias desde `subscription_sync_log` (tipo de evento de RevenueCat + tier resultante), pero sin source del paywall, sin precio y sin tienda.
2. **El costo de IA no es la restricción; la conversión sí.** Con gpt-6-luna `fast` y el prefijo cacheado, un turno típico sale ~US$0,006 [supuesto, a partir de tokens medidos]. Un Free que agota sus 20 consultas cuesta ≤ US$0,26/mes. Un Premium neto (US$10 → US$7–8,5) cubre entre ~50 y ~100 Free activos. El único plan que puede perder plata es **Gold a US$15 con uso máximo**, y lo empujan más las búsquedas web/noticias que el LLM.
3. **Los paywalls que hay son casi todos "pared" (bloqueo al tocar algo).** No hay plan anual, no hay prueba (decisión del usuario del 2026-10-26: "sin prueba de Gold por ahora") y no hay upsell en el momento aha (diagnóstico de cartera), que es Free completo por decisión.

---

## 2. Qué se mide hoy, etapa por etapa

| Etapa | ¿Se mide? | Fuente | Hueco |
|---|---|---|---|
| Instalación | **No** | Solo consolas de las tiendas | No hay SDK de analytics (`pubspec.yaml`: firebase_core/messaging/remote_config, sin analytics). Instalación → alta no se puede unir. |
| Alta | Sí [medido] | `auth.users.created_at` | No hay atribución de origen (ads, landing, orgánico). |
| Onboarding | Sí, desde 2026-10-26 | `product_events`: `onboarding_started`, `onboarding_finished` (`exit`) | `ProductEvents.log` descarta todo lo que no tiene sesión: lo que pasa antes del login se pierde. |
| Activación: carga de cartera | Sí | `portfolio_loaded` (`method`: manual, file, screenshot, etoro, binance, snaptrade, chat, note; `count`) | Mide solo el éxito. **No se registran intentos de conectar bróker ni rechazos por plan** (`snaptrade_plan_required`, `binance_plan_required`). |
| Aha | Sí | `diagnosis_seen` (`findings`), `diagnosis_question` (`kind`); vista `product_funnel` (minutos desde el alta) | Bien cubierto. Los usuarios dados de alta antes del 26/10 aparecen con `null`. |
| Uso del asistente | Sí, en el servidor | `first_chat_answer` (una vez); `ai_turn_usage` (una fila por turno: tier, modelo, rondas, tokens, `cost_usd`, búsquedas web); `ai_usage_monthly`; vista `ai_usage_monthly_stats` (p50/p90/p99 por tier y mes) | Uso fuera del chat (Home, alertas, watchlist, plan de cartera) no se mide. |
| Cuota agotada | Indirecto | `ai_usage_monthly.queries_used >= _monthly_quota(tier)`; `updated_at` ≈ cuándo llegó | Sirve para "qué % de Free llega a 20". No dice si después vio el paywall. |
| Funciones bloqueadas mostradas | **No** | — | `QaGoldTeaser`, chips con candado y bloques `analysis_locked_*` se muestran sin registrar la impresión. |
| Paywall visto | **No** | `PaywallSourceLog.record`: memoria + consola en debug | El propio archivo lo dice ("La app todavía no tiene telemetría de eventos"). Además, ~la mitad de las aperturas no pasan `source` y quedan con el `reason` genérico (ver sección 4). |
| Toque en un plan / resultado de la compra | **No** | `SubscriptionPaywallSheet._purchase` ve `Success/Cancelled/Failed/NotConfigured` y no lo registra | No se puede medir la tasa paywall → compra ni los errores de compra. |
| Compra / renovación / baja | Parcial | `subscription_sync_log` (`event_type` de RevenueCat, `outcome = synced:<tier>`, `created_at`); dashboard de RevenueCat | El webhook descarta `price`, `currency`, `store`, `period_type` (trial/intro/normal) y `environment` (sandbox). `user_subscriptions.status` nunca queda en `trialing`. En la base no hay MRR ni neto por tienda. |
| Retención | Parcial | `ai_turn_usage` (días con chat), renovaciones en `subscription_sync_log` | No hay evento de apertura de la app: un usuario que mira la Home todos los días y no chatea figura inactivo. |
| Cortesía Gold semanal | Sí | `weekly_free_analysis` (user_id, week_start, ticker) | La apertura del paywall desde "Conocer Gold" (`source: weekly_free_analysis`) tampoco se persiste. |

**Respuesta a "¿podemos medir instalación → activación → asistente → paywall → compra → retención?":** el tramo **alta → activación → asistente** sí, desde el 2026-10-26. El tramo **asistente → paywall → compra** no: falta todo el medio. **Compra → retención** a medias, desde `subscription_sync_log`.

---

## 3. Unit economics por plan

### 3.1 Insumos

| Insumo | Valor | Tipo | Fuente |
|---|---|---|---|
| Cuotas mensuales | Free 20 · Premium 500 · Gold 1000 | [medido] | `plan_matrix.dart`, `plan_limits` |
| Tope diario | Free sin tope · Premium 60 · Gold 100 | [medido] | `plan_limits.daily_queries` |
| Búsquedas web por día | Free 3 · Premium 10 · Gold 25 | [medido] | `20261011060000_web_search.sql` |
| `news-context` por día | Free/Premium 5 (cortesía) · Gold 40 | [medido] | `20261012000000_commercial_data_sources.sql` |
| Costo por búsqueda sin caché | US$0,01 | [medido, en código] | `searchCallUsd` en `news-context` y `web-search` |
| Modelo | gpt-6-luna, `service_tier: fast`; gpt-4.1-mini se reescribe a luna. `GPT6_ROLLOUT_PERCENT` (default 100) puede mandar una parte a gpt-4.1-mini | [medido, en código] / el valor del secret en prod no lo conozco | `ai-chat/handler.ts` |
| Precio luna fast (por 1M tokens) | input 0,20 · cacheado 0,02 · output 1,00 | [medido] | `20261014130000_gpt6_luna_fast_prices.sql` |
| Prefijo fijo por pedido | 26.887 tokens, ~99 % cacheado | [medido en doc] | `docs/superpowers/research/2026-10-24-porty-escalable.md` |
| Salida por turno | ~290 tokens promedio; 2–3 % llega a 3.000 | [medido en doc] | idem |
| Rondas por turno | 2–4 | [medido en doc / comentario] | `ai-chat/handler.ts` ("un turno usa 2-4") |
| Tokens variables por ronda (historial, cartera, resultados de tools) | 2K / 4K / 8K | **[supuesto]** | — |
| Turnos que abren conversación (prefijo sin caché) | 20 % / 33 % / 50 % | **[supuesto]** | — |
| Precio Premium / Gold | US$10 / US$15 (alternativa Gold US$20) | **[supuesto]**: no están en el código; los trae la tienda vía RevenueCat. Salen del doc `2026-09-30-diferenciacion-planes.md` | Confirmar en App Store Connect / Play |
| Comisión de tienda | 15 % (Small Business Program de Apple; suscripciones en Google) o 30 % | [supuesto, rango pedido] | — |
| Avisos + informe semanal | Premium ~US$0,05 · Gold ~US$0,07 por mes | [supuesto, doc 09-30] | — |
| Búsquedas web/noticias promedio por turno | Free 0,0005 · Premium 0,001 · Gold 0,0025 USD | **[supuesto]** | Se mide con `ai_turn_usage.web_search_cost_usd` |
| Fee de RevenueCat, Finnhub/datos pagos, infraestructura | No incluidos | — | — |

### 3.2 Costo de IA por turno (estimación con tokens medidos)

| Escenario | Rondas | Tokens variables/ronda | Salida final | Costo/turno |
|---|---|---|---|---|
| Bajo | 2 | 2K | 290 | **US$0,0033** |
| Típico | 3 | 4K | 400 | **US$0,0063** |
| Alto | 4 | 8K | 1.300 | **US$0,0127** |

Todos **[supuesto]**. El costo real ya está en `ai_turn_usage.cost_usd`: la consulta Q4 lo reemplaza por el medido. Como referencia, el mismo turno típico con gpt-4.1-mini costaría ~US$0,017: si `GPT6_ROLLOUT_PERCENT` < 100, una parte de los usuarios sale casi 3 veces más cara.

### 3.3 Margen mensual por usuario pago (USD)

Costo = consultas × (turno + búsquedas) + avisos/informe. Formato "típico / alto" según el costo por turno de la tabla anterior. El uso como % de la cuota es **[supuesto]**: la distribución real sale de Q3.

| Plan | Neto 15 % / 30 % | Uso 20 % | Uso 50 % | Uso 100 % (peor caso de cuota) |
|---|---|---|---|---|
| Free | 0 | costo 0,03 / 0,05 | 0,07 / 0,13 | **0,14 / 0,26** |
| Premium US$10 | 8,50 / 7,00 | margen 7,7 / 7,1 (15 %) · 6,2 / 5,6 (30 %) | 6,6 / 5,0 · 5,1 / 3,5 | 4,8 / 1,6 · 3,3 / **0,1** |
| Gold US$15 | 12,75 / 10,50 | 10,9 / 9,6 · 8,7 / 7,4 | 8,3 / 5,1 · 6,0 / 2,8 | 3,9 / **−2,5** · 1,6 / **−4,8** |
| Gold US$20 | 17,00 / 14,00 | 15,2 / 13,9 · 12,2 / 10,9 | 12,5 / 9,3 · 9,5 / 6,3 | 8,1 / 1,7 · 5,1 / **−1,3** |

**Peor caso por topes diarios de búsqueda** (sin caché, todos los días) [cálculo sobre topes medidos]: Gold (40 + 25)/día × US$0,01 × 30 = **US$19,5/mes**, solo en búsquedas; Premium US$4,5; Free US$2,4 en teoría, pero acotado en la práctica por las 20 consultas. En Gold el tope de búsquedas permite gastar más que todo el ingreso neto. La caché compartida lo baja mucho en la práctica, pero eso no está medido.

### 3.4 Lo que implica

- **Un pago financia a muchos Free.** Premium típico (uso 50 %, comisión 15 %) deja ~US$6,6. Un Free que agota la cuota cuesta ~US$0,14 → **un Premium cubre ~47 Free al máximo, o ~95 al 50 %** [supuesto]. Subir la cuota Free o dar más valor gratis es barato. El riesgo de hacerlo no es el costo: es sacarle motivo al upgrade.
- **Gold a US$15 solo pierde plata con usuarios extremos** (cuota completa + turnos caros, o búsquedas al tope). Antes de cambiar el precio, mirar el p99 de `cost_usd + web_search_cost_usd` por Gold (Q4).
- **Con cualquier escenario de uso razonable, la economía no es lo que frena el crecimiento de pagos.** Lo que frena es cuánta gente llega a ver un paywall en un buen momento, y eso hoy no se mide.

---

## 4. Puntos de conversión en la app hoy

| Lugar | Disparador | `reason` | `source` | Tiers mostrados |
|---|---|---|---|---|
| Chat: respuesta con datos Gold | `QaGoldTeaser`, bloque `analysis_locked_*`, chip con candado (`chip_<feature>`) | goldRequired | sí | Gold. Si compra, la card se completa en el lugar (`unlockGoldData`) |
| Chat: análisis de cortesía semanal | "Conocer Gold" | goldRequired | `weekly_free_analysis` | Gold |
| Chat: todo lo pedido es Premium (mercado ajeno, simulaciones, metas) | El turno se corta y se abre la hoja | modeLocked / marketDataLocked | no (queda el reason) | Gold + Premium |
| Chat: cuota agotada | Al intentar un turno; o tocar el contador cuando queda en 0 | quotaExceeded | no | Gold + Premium |
| Chat: pedido de alerta por encima del tope | Tool de alertas | priceAlerts | `porty` | Gold + Premium |
| Home | `BenchmarkLockedCard` (comparación con S&P 500) | modeLocked | `home_benchmark` | Gold + Premium |
| Home: agregar posición n.º 11 | `AppShell._onAddPosition` | modeLocked | no | Gold + Premium |
| eToro | Sincronización automática (la primera importación es gratis) | brokerSync | `etoro_connect` | Gold + Premium |
| SnapTrade | `snaptrade_plan_required`; segundo bróker → Gold | brokerSync / goldRequired | no | — |
| Binance | `binance_plan_required` | brokerSync | no | Gold + Premium |
| Alertas de precio | Tope (1 en Free) / reactivar | priceAlerts | `price_alert_limit` / `price_alert_reactivate` | Gold + Premium |
| Watchlist | Free tiene 0 | marketDataLocked | no | Gold + Premium |
| Plan de cartera (allocation, wizard) | Feature Premium | modeLocked | no | Gold + Premium |
| Importar resumen | Cuota / función bloqueada | quotaExceeded / modeLocked | no | Gold + Premium |
| Informe semanal | Teaser Gold / fila S&P 500 | goldRequired / modeLocked | `weekly_report` / `weekly_report_sp500` | — |
| Ajustes | Tarjeta de suscripción | modeLocked | no | Gold + Premium |

**Lo que falta (según la estructura del código):**

1. **Medir todo lo de arriba** (sección 5). Sin eso no se puede saber qué paywall convierte.
2. **Plan anual**: solo existen `premium_monthly` y `gold_monthly` en `SubscriptionCatalog`. El doc 09-30 lo priorizaba como n.º 1 (2–3 días + revisión de tiendas).
3. **Prueba**: no existe ni de tienda ni promocional. El usuario la descartó el 2026-10-26 para el onboarding ("si los datos muestran que hace falta"). Una prueba de tienda solo en Gold, ofrecida desde el paywall, es una decisión distinta y todavía no se tomó.
4. **Upsell en el momento aha**: el diagnóstico (`portfolio_diagnosis`) no tiene puente a pago. Es Free completo por decisión, pero ahí no se ofrece ni siquiera el siguiente paso pago (por ejemplo "que se actualice sola" o "comparar con el S&P 500").
5. **Antes de la pared de cuota**: el paywall de cuota solo aparece al llegar a 0. No encontré un aviso cerca del límite que lleve al paywall (el doc 09-30 proponía uno al 80 %).
6. **Después de la importación gratis de eToro**: no verifiqué que haya un puente a "sincronización automática" justo después de importar; queda a verificar con `porty-flutter-dev`.

---

## 5. Tracking plan: qué falta instrumentar

Todos los eventos de la app van por `ProductEvents.log` (tabla `product_events`; el nombre cumple `^[a-z][a-z0-9_]{2,39}$`; props ≤ 2 KB; sin datos personales).

| Evento | Props | Dónde se dispara | Dueño | Prioridad |
|---|---|---|---|---|
| `paywall_viewed` | `reason`, `source` (siempre; el `reason` si falta), `tier`, `visible_tiers`, `queries_used`, `queries_limit` | `SubscriptionPaywallSheet.show`, reemplazando o complementando `PaywallSourceLog.record` | porty-flutter-dev | **P0** |
| `paywall_plan_tapped` | `tier`, `source` | `_purchase` al entrar | porty-flutter-dev | P0 |
| `purchase_result` | `tier`, `source`, `result` (success / cancelled / failed / not_configured) | `_purchase` y `_restore` según el resultado | porty-flutter-dev | **P0** |
| `paywall_dismissed` | `source`, `seconds_open` | `whenComplete` de la hoja sin compra | porty-flutter-dev | P1 |
| Pasar `source` en las ~10 aperturas que no lo tienen | p. ej. `chat_quota`, `chat_turn_locked_<feature>`, `add_position_limit`, `snaptrade_connect`, `binance_connect`, `watchlist`, `allocation`, `statement_import`, `settings` | Los llamadores de la sección 4 | porty-flutter-dev | P0 (es una línea por llamador) |
| `locked_feature_shown` | `feature`, `surface` (teaser, chip, analysis_block, benchmark_card) | Al renderizar `QaGoldTeaser`, `_LockedChip`, `BenchmarkLockedCard` (una vez por surface) | porty-assistant-dev / porty-flutter-dev | P1 |
| `broker_connect_result` | `broker`, `result` (ok, plan_required, limit, error) | Pantallas de eToro, SnapTrade y Binance | porty-flutter-dev | P1 |
| `app_opened` | `tier` (una vez por día y usuario) | Al iniciar con sesión | porty-flutter-dev | P1 (retención) |
| Tabla `subscription_events` | `user_id`, `event_type`, `product_id`, `store`, `period_type`, `price`, `currency`, `environment`, `event_at` | `revenuecat-webhook`: guardar el evento crudo antes de recalcular | porty-backend-dev | **P0** (sin esto no hay MRR, neto por tienda ni separación sandbox/prod en la base) |

Con P0 + Q7 alcanza para la primera tabla de conversión **paywall visto → compra, por source**.

---

## 6. Consultas para correr en producción (las tiene que correr el usuario)

```sql
-- Q1. Embudo desde el 2026-10-27 (primer día completo con eventos)
select count(*) as altas,
       count(min_to_onboarding_done) as onboarding,
       count(min_to_portfolio)       as cartera,
       count(min_to_diagnosis)       as aha,
       count(min_to_first_answer)    as primera_respuesta,
       percentile_cont(0.5) within group (order by min_to_diagnosis) as min_a_aha_p50
from public.product_funnel
where signed_up_at >= '2026-10-27';

-- Q1b. Cómo cargan la cartera
select load_method, count(*) from public.product_funnel
where signed_up_at >= '2026-10-27' group by 1 order by 2 desc;

-- Q2. Usuarios por plan hoy
select tier, status, provider, count(*) from public.user_subscriptions group by 1, 2, 3;

-- Q3. Distribución de uso y costo por plan
select * from public.ai_usage_monthly_stats where month >= '2026-09' order by month, tier;

-- Q3b. % de Free que agota la cuota (tier actual: aproximación)
select m.month,
       count(*) filter (where m.queries_used >= 20)::numeric / nullif(count(*), 0) as pct_free_al_tope
from public.ai_usage_monthly m join public.user_subscriptions s using (user_id)
where s.tier = 'free' group by 1 order by 1;

-- Q4. Costo real por turno (últimos 30 días)
select tier, model, count(*) as turnos,
       avg(cost_usd) as costo_medio,
       percentile_cont(0.9) within group (order by cost_usd) as costo_p90,
       avg(web_search_cost_usd) as busqueda_media,
       avg(round_count) as rondas, avg(completion_tokens) as salida,
       sum(cached_tokens)::numeric / nullif(sum(prompt_tokens), 0) as cache_ratio
from public.ai_turn_usage
where charged_at is not null and created_at >= now() - interval '30 days'
group by 1, 2;

-- Q5. Compras, renovaciones y bajas por semana
select date_trunc('week', created_at) as semana, event_type, outcome,
       count(distinct user_id) as usuarios
from public.subscription_sync_log
where created_at >= '2026-09-01' group by 1, 2, 3 order by 1, 2;

-- Q6. Uso de la cortesía Gold semanal
select week_start, count(*) from public.weekly_free_analysis group by 1 order by 1 desc limit 8;

-- Q7. ¿Pagan más los que llegaron al aha? (correlación, no causalidad)
select (f.min_to_diagnosis is not null) as llego_al_aha,
       count(*) as usuarios,
       count(*) filter (where s.tier <> 'free') as pagos
from public.product_funnel f join public.user_subscriptions s using (user_id)
where f.signed_up_at >= '2026-10-27' group by 1;

-- Q8. Flags prendidos
select key, value, updated_at from public.app_config order by key;
```

Q5 incluye compras de sandbox si se probó con cuentas de test: hoy no hay forma de filtrarlas en la base.

---

## 7. Sobre experimentos

Con el volumen que probablemente hay (no lo sé: Q2), **un A/B de conversión no da**. Para detectar 2 % → 3 % de conversión con 80 % de potencia hacen falta ~3.800 usuarios por brazo [cálculo estándar]. Hasta tener ese volumen: cambios reversibles detrás de `app_config`, comparación antes/después con la misma definición, y entrevistas a quienes cerraron el paywall sin comprar.

---

## 8. Recomendación para este mes

1. **Instrumentar el tramo paywall → compra (P0 de la sección 5).** Son ~1–2 días entre app y webhook, y sin esto no vamos a saber si lo que se construya mueve algo. Va en paralelo con lo que siga, no antes.
2. **Plan anual en el paywall.** Es el cambio de esfuerzo bajo que no toca la decisión de "sin prueba". Tampoco tiene costo de IA adicional.
3. **Paywalls contextuales en los dos momentos de mayor intención que ya existen:** la conexión de bróker (sincronización automática después de la importación gratis) y la cuota agotada (mostrar qué habría respondido). Son los puntos donde el usuario ya vio valor con sus propios datos. Cuál de los dos pesa más, se sabe con Q1b, Q3b y el `paywall_viewed` nuevo.

Si se mantiene Gold a US$15, sumar una alerta sobre el p99 de costo mensual de Gold (Q4 + búsquedas): es el único escenario con margen negativo.
