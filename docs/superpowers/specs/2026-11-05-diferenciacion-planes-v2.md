# Diferenciación de planes v2

Fecha: 2026-11-05 · Autor: porty-architect · Rama: `claude/plan-differentiation`

> **Decisión del usuario (fundador), 2026-11-05.** Aprobó los seis cambios de esta spec. Dos de ellos reemplazan decisiones de `docs/product/decisions.md`:
> - "El orden de planes según motivo pasa a diciembre" (2026-11-02): **se adelanta a noviembre** (§3.5).
> - "No se tocan precios ni cuotas en noviembre" (2026-11-02): **se tocan los topes** de búsquedas (topes mensuales nuevos, §3.6), la watchlist de Free (0 → 3) y el tope de posiciones en la primera importación. Los precios y las consultas mensuales (20/500/1000) **no cambian**.
>
> product-owner agrega estas dos líneas a `decisions.md` (con "usuario" como quien decide). Esta spec no edita ese archivo.

## 1. Objetivo

Que cada plan prometa un resultado distinto y que el paywall lo cuente bien:
- **Free:** la cartera completa desde la primera importación, registrar operaciones hablando con Porty y seguir 3 tickers.
- **Premium:** "tu plata ordenada y al día, y por qué se movió lo tuyo". Suma noticias **solo de lo que tenés**.
- **Gold:** "Porty te explica cualquier empresa y qué pasó".

Además: se prenden al 100 % los interruptores de conversión, el peor caso de costo de búsquedas queda acotado por mes, y el paywall se puede leer por feature bloqueada y por cohorte de interruptores.

**Listo** = §5 en verde, con las migraciones listas para `db push` y las functions listas para deploy. Ninguna de las dos cosas la hace un agente.

## 2. Fuera de alcance

- Precios, consultas mensuales y planes anuales.
- La prueba de Gold.
- Binance gratis la primera vez.
- Cambios al prompt de sistema. El diseño de §3.4 evita tocarlo; ver la verificación en §4.3, tarea A6.
- Que la primera importación gratis de eToro consuma también la de archivo. Son dos cupos de una vez, independientes (§6, D3).
- Renombrar "Earnings" en los chips del chat (`qa_identity.dart`). Se puede hacer después; acá se cambian solo los textos de planes y paywall.
- Pasar `news_provider` a `v2`. Es un paso del usuario y es **precondición** para publicar (§6, R1).

## 3. Contrato

### 3.1 Interruptores al 100 % (verificado en el código)

| Flag | App | Servidor | `source` del paywall |
|---|---|---|---|
| `market_taste` | `MarketTasteGrant` + `AssistantMarketTasteNotice` | `market_taste_status`, `consume_market_taste` (decide el servidor con `_rollout_on`) | `chat_market_teaser` |
| `weekly_report_courtesy` (`reports: 3`) | "Regalo N de 3" en el informe | `_weekly_courtesy_limit` + `claim_weekly_report` | hoy `'weekly_report'` (literal, compartido con el Gold genérico) → **nuevo** `weekly_report_courtesy_ended` (§4.2, F7) |
| `quota_nudge` | `quotaNudgeEnabledProvider` → línea de cuota | — (no hace falta) | `quota_soft` |
| `diagnosis_bridge` | filas del diagnóstico | — | `diagnosis_sync` |
| `broker_screenshot_exit` | Binance/SnapTrade bloqueados | — | No abre paywall: es una salida a la importación por captura (origen `broker_locked_*`) |

El único hueco es el `source` propio de la cortesía (F7). Los demás están completos.

**Migración `20261105100100_conversion_flags_on.sql`** (idempotente, conserva `users`):
```sql
insert into public.app_config (key, value) values
  ('market_taste',           '{"percent":100,"users":[]}'),
  ('quota_nudge',            '{"percent":100,"users":[]}'),
  ('diagnosis_bridge',       '{"percent":100,"users":[]}'),
  ('broker_screenshot_exit', '{"percent":100,"users":[]}'),
  ('weekly_report_courtesy', '{"percent":100,"users":[],"reports":3}')
on conflict (key) do update
  set value = public.app_config.value || (excluded.value - 'users'), updated_at = now();
```
Tiene que correr **después** de `20261105100000_app_config_history.sql` (§3.7) para que el cambio quede en el historial.

### 3.2 Free: primera importación sin tope

**Verificado:**
- El tope de 10 posiciones existe **solo en la app**: `StatementImportState.exceedsLimit`, `AppShell._onAddPosition` y `SubscriptionPolicy.positionLimit`.
- En las migraciones no hay trigger, RPC ni edge function con tope de posiciones. `statement-import` corta en 200 filas (`rows.ts maxRows`), no por plan.
- La importación gratis de eToro ya trae toda la cartera (`etoro-sync` no recorta) y es de una sola vez en el servidor (`etoro_connections.free_import_at`). **No se toca.**
- `positions` viene de antes del CLI, así que en prod podría haber un trigger que no está en las migraciones. Hace falta la auditoría de §6, R2.

**Regla:** la primera importación de archivo, captura o texto **que pase el tope** entra entera. Desde entonces vuelve a regir el tope para agregar posiciones nuevas: el FAB, las filas nuevas de importaciones siguientes y las compras de tickers nuevos desde el chat. Una importación que no pasa el tope no gasta el cupo.

**Migración `20261105100200_free_first_import.sql`:**
```sql
create table if not exists public.first_full_imports (
  user_id uuid primary key references auth.users (id) on delete cascade,
  import_id text not null check (import_id ~ '^[A-Za-z0-9_-]{8,64}$'),
  origin text not null check (origin in ('file','screenshot','note')),
  positions int not null check (positions > 0),
  used_at timestamptz not null default now()
);
-- RLS on; select propio para authenticated; escritura solo vía RPC.

first_import_status() returns jsonb
  -- {"available": true} | {"available": false, "used_at": "..."}
claim_first_import(p_import_id text, p_origin text, p_positions int) returns jsonb
  -- {"ok": true, "reused": false}
  -- {"ok": true, "reused": true}                   -- mismo import_id (reintento)
  -- {"ok": false, "reason": "already_used"}
  -- {"ok": false, "reason": "invalid_args"}
```
- Las dos son `security definer` con `auth.uid()`; `execute` solo para `authenticated`.
- `pg_advisory_xact_lock` por usuario, igual que en `consume_market_taste`.
- La FK con cascade cubre el borrado de cuenta. Si `account_deletion_db_test.sql` lista tablas, se suma ahí.

**App (statement_import):**
1. Al pasar a `preview`, si `positionLimit != null`, leer `first_import_status`.
2. Si `available`, el estado lleva `firstImportAvailable: true` y `exceedsLimit` da `false`. La vista previa muestra `import_first_full_note` ("Tu primera importación entra entera. Después, Free suma hasta {limit} posiciones.").
3. En `importReady`, si la importación pasaría el tope, llamar `claim_first_import(importId, origin, nuevas+tenidas)` antes de escribir:
   - `ok` → se importa.
   - `already_used` → se vuelve al estado con tope y se muestra el aviso de siempre (`statement_import_position_limit`).
   - Sin red → no se importa y se muestra error de red. **Falla cerrado.**
4. `importId` es un uuid por vista previa.

### 3.3 Free: operaciones desde el chat y watchlist de 3

**`PlanFeature.portfolioActions` pasa a `_free`.** El chat necesita, además, el tope de posiciones:
- `propose_buy` de un ticker que no tiene, con Free y `valuations.length >= positionLimit`, devuelve `{"status":"limit_reached","limit":10}` más un `answer_guide` ("their plan allows up to `limit` holdings; they can upgrade to Premium for unlimited holdings").
- `executeAction` lo vuelve a chequear. Si corta, el paywall va con `PaywallReason.positionLimit` y source `chat_action_position_limit`.
- Se borra el chequeo `portfolioActions` → `modeLocked` de `assistant_provider.dart:932`.

**Watchlist:** `plan_limits.watchlist` de Free pasa de 0 a 3. Lo aplica la migración `20261105100300_free_watchlist.sql`: `update … set watchlist = 3 where tier='free' and watchlist = 0`. En `PlanMatrix`, Free queda con `watchlistLimit: 3`.
- Las tools del chat (`get_watchlist`, `propose_watch`, `propose_watchlist_change`) dejan de usar `marketDataAllowed` y preguntan `PlanMatrix.of(tier).watchlistLimit > 0`.
- Al llegar al tope, el chat responde con `limit_reached` (ya existe). En la app, la pantalla y el chat abren `PaywallReason.watchlistLimit` (nueva).
- Los avisos de "se movió fuerte" (`market-watch`) quedan también para Free. El costo es despreciable.

### 3.4 Premium: "por qué se movió lo tuyo" (`PlanFeature.heldNews`)

**Fuente.** Google News RSS (camino `legacy`) no admite uso comercial. Premium usa **solo el camino v2**: titulares de GDELT (`headlines`) y contexto con citas (`news-context`, búsqueda web de OpenAI restringida a `news_source_allowlist`).
- Con `news_provider = legacy`, `heldNews` **no se sirve**: `get_news` responde `locked`, como hoy.
- `sec` (resultados trimestrales y fundamentals) sigue siendo solo Gold.

**Dominio (`plan_matrix.dart`):**
```dart
/// Noticias y "por qué se movió" SOLO de tickers en cartera (get_news).
heldNews,                       // en _premium (y por herencia en Gold)

static bool allowsNewsFor(SubscriptionTier t, {required bool held}) =>
    allows(t, PlanFeature.news) || (held && allows(t, PlanFeature.heldNews));
```

**`get_news` (en `market_tools.dart`), en este orden:**
1. `allows(news)` o cortesía (`ctx.gate`) → como hoy.
2. `!ctx.secData` → `ctx.lockedFeature(news)`, como hoy.
3. Se separan `held = tickers ∩ ctx.heldTickers` y `others`. `heldTickers` incluye lo que llegó por bróker.
   - Sin `heldNews` (Free): si `held` no está vacío → `ctx.lockedFeature(heldNews)` (Premium, corta el turno como los demás motivos Premium; source `chat_turn_locked_held_news`). Si no → `lockedFeature(news)` (Gold).
   - Con `heldNews` y `held` vacío → `{"status":"locked","required_plan":"gold","reason":"not_held","as_of":…}`. Se suma `news` a `lockedFeatures` y `goldRequired` a `lockedReasons`. No corta el turno: aparece el `QaGoldTeaser`, y su paywall usa source **`chat_news_not_held`** (lo deduce el teaser de la evidencia: llamada `get_news` locked con `reason: not_held`). **Sin prop nueva en el catálogo.**
   - Con `heldNews`, `held` con elementos y `others` también → se sirve `held`. El resultado agrega `"locked_tickers": [...]` y un `answer_guide`: "News for locked_tickers needs Gold: say it in one clause, never invent". También se marca `news` en `lockedFeatures`.
4. Los chips "Noticias" (`qa_identity.dart`), las sugerencias de `porty_screen_suggestions.dart` (posición en cartera → `heldNews`) y `QaPlanScope` usan `allowsNewsFor(held: …)`.

**Servidor.** Nueva función en `20261105100500_held_news.sql`:
```sql
news_data_allowed(p_user_id uuid, p_ticker text default null) returns boolean
  = gold_data_allowed(p_user_id, p_ticker)
    or (p_ticker is not null
        and coalesce(_effective_tier(p_user_id),'free') = 'premium'
        and public._news_provider() = 'v2'
        and exists (select 1 from public.positions
                    where user_id = p_user_id and upper(ticker) = upper(p_ticker)
                      and quantity > 0));
-- revoke de public/anon/authenticated (la llama la service role)
update public.plan_limits set news_context_per_day = 10 where tier = 'premium' and news_context_per_day = 5;
```
- `headlines` y `news-context` cambian `goldAllowed` por un `newsAllowed` nuevo en `_shared/data_cache.ts`. Ese helper llama `news_data_allowed` por ticker con el ticker **como vino en el request** (antes de `normalizeTicker`).
- `sec` sigue con `goldAllowed`.
- Respuesta 403: `{"error":{"type":"plan_required","required_plan":"gold"}}` (sin cambios).

**Prompt y allowlist.** Las reglas actuales ya cubren `locked`, `locked_tickers` y "news locked → numeric move + banner". Cambian solo descripciones de tools y `answer_guide`, que no entran en el hash. Verificación obligatoria en A6.

### 3.5 Paywall y textos

**`PaywallReason`:**
- Nuevas: `benchmark`, `watchlistLimit`, `heldNews`.
- **Se borra** `modeLocked`, en fases (§4).

`AssistantToolContext.reasonFor` pasa a ser un switch **exhaustivo, sin `_`**:

| Feature | Reason |
|---|---|
| `marketData` | `marketDataLocked` |
| `investSimulation` | `simulations` |
| `goals` | `goals` |
| `allocationPlan` | `allocationPlan` |
| `benchmark` | `benchmark` |
| `unlimitedPositions` | `positionLimit` |
| `brokerSync` | `brokerSync` (antes caía en `modeLocked`) |
| `heldNews` | `heldNews` |
| `ownPortfolio`, `portfolioActions` | `plans` (no ocurre) |
| el resto | `goldRequired` |

`_turnPaywallPriority` queda `[brokerSync, heldNews, simulations, goals, allocationPlan, marketDataLocked]`.

**Orden de tarjetas.** `PaywallReason.offerTier` es `premium`, `gold` o `null`:
- `premium`: `positionLimit`, `simulations`, `goals`, `allocationPlan`, `marketDataLocked`, `brokerSync`, `priceAlerts`, `benchmark`, `watchlistLimit`, `heldNews`, y `quotaExceeded`/`quotaLow` si el plan actual es Free.
- `gold`: `goldRequired`.
- `null`: `plans`.

`visibleTiersFor`:
- `gold` o tier actual Premium → `[gold]`.
- `premium` → `[premium, gold]`.
- `null` → `[gold, premium]` (como hoy).

El badge "Recomendado" va en la **primera** tarjeta cuando hay dos. El estilo dorado (`featured`) sigue siendo de Gold.

**Promesa por tarjeta.** Va debajo del título de cada tarjeta.

| Clave | es-ES | en-US |
|---|---|---|
| `paywall_premium_promise` | Tu plata ordenada y al día, y por qué se movió lo tuyo. | Your money organized and up to date, plus why your holdings moved. |
| `paywall_gold_promise` | Porty te explica cualquier empresa y qué está pasando. | Porty explains any company and what's going on. |

**Highlights (`PlanMatrix`).** Se agrega `PlanSpec.leadingMarketingKeys` (const `[]`). `marketingKeys` = leading + highlights + extra.
- **Premium:** `brokerSync`, `unlimitedPositions`, `heldNews`, `allocationPlan`, `goals`, `marketData`. Extra: `[]`. Salen `investSimulation`, `benchmark` y `price_alerts` de la lista de marketing; las features siguen incluidas.
- **Gold:** leading `['plan_feature_weekly_report']`, después `multiBrokerSync`, `companyAnalysis`, `news`, `earnings`. Extra: `[]`.
- `featureKeysFor(gold)` pone `plan_feature_everything_premium` **al final**.

**Textos de features** (sin jerga):

| Clave | es-ES | en-US |
|---|---|---|
| `plan_feature_broker_sync` | Tu bróker se actualiza solo | Your broker updates on its own |
| `plan_feature_unlimited_positions` | Todas tus posiciones, sin límite | All your holdings, no limit |
| `plan_feature_held_news` (nueva) | Por qué se movió lo que tenés | Why what you own moved |
| `plan_feature_allocation_plan` | Tu plan de cartera y cómo repartir cada aporte | Your portfolio plan and how to split each deposit |
| `plan_feature_goals` | Metas de ahorro con cuánto aportar | Savings goals and how much to put in |
| `plan_feature_market_data` | Precios y gráficos de cualquier acción | Prices and charts for any stock |
| `plan_feature_weekly_report` | Tu informe de cada sábado, completo | Your full Saturday report |
| `plan_feature_multi_broker_sync` | Todos tus brókers juntos | All your brokers together |
| `plan_feature_company_analysis` | Análisis completo de cualquier empresa | Full analysis of any company |
| `plan_feature_news` | Noticias de cualquier empresa, explicadas | News on any company, explained |
| `plan_feature_earnings` | Resultados trimestrales: cuándo salen y cómo le fue | Quarterly results: when they come out and how it went |

**Títulos nuevos** (`paywall_title_*` / `paywall_subtitle_*`):

| Motivo | es-ES | en-US |
|---|---|---|
| `benchmark` | ¿Le ganás al mercado? / Con Premium comparás tu cartera con el S&P 500, el índice de las 500 empresas más grandes de EE. UU. | Are you beating the market? / With Premium you compare your portfolio with the S&P 500, the index of the 500 largest US companies. |
| `watchlist_limit` | Seguí todas las que te interesan / Free sigue hasta {limit}. Con Premium seguís hasta {premium} y te aviso si se mueven fuerte. | Follow everything you care about / Free follows up to {limit}. With Premium you follow up to {premium} and I'll tell you when they move sharply. |
| `held_news` | Por qué se movió lo tuyo / Con Premium, Porty te cuenta qué pasó con las empresas que tenés, con fuentes. | Why your holdings moved / With Premium, Porty tells you what happened with the companies you own, with sources. |

- `paywall_subtitle_plans`: "Premium ordena tu plata y te cuenta qué pasó con lo tuyo. Gold te explica cualquier empresa." / "Premium organizes your money and tells you what happened with yours. Gold explains any company."
- Otros: `import_first_full_note` (§3.2) y `watchlist_locked_body`, que se mantiene aunque ningún plan tenga 0.

**Usos genéricos de `modeLocked` que se reemplazan:**
- `benchmark_locked_card.dart` → `benchmark` / `home_benchmark`
- `weekly_report_screen.dart:404` → `benchmark` / `weekly_report_sp500`
- `assistant_provider.dart:935` → se borra (§3.3)
- `assistant_tool_context.dart:353` → switch exhaustivo
- `assistant_toolset.dart:156` → la prioridad de arriba

**Claves que se borran** (sin uso, confirmado con grep en `lib/` y `test/`):
- `settings_plan_free_desc`, `settings_plan_premium_desc`, `settings_plan_gold_desc`
- `settings_upgrade_pro`
- `paywall_premium_desc`, `paywall_premium_feature_explore`, `paywall_premium_feature_benchmark`, `paywall_premium_feature_alerts`
- `paywall_gold_desc`, `paywall_gold_feature_invest`, `paywall_gold_feature_plan`, `paywall_gold_feature_news`
- `paywall_title_news`, `paywall_subtitle_news`
- En la fase C: `paywall_title_mode_locked` y `paywall_subtitle_mode_locked`.

**`PaywallSource`**: constantes nuevas, todas en `values`. Los literales pasan a constantes con el mismo valor:
- `homeBenchmark='home_benchmark'`, `weeklyReportSp500='weekly_report_sp500'`, `weeklyReportLocked='weekly_report'`
- `weeklyReportCourtesyEnded='weekly_report_courtesy_ended'`
- `etoroConnect='etoro_connect'`, `priceAlertLimit='price_alert_limit'`, `priceAlertReactivate='price_alert_reactivate'`
- `chatActionPositionLimit='chat_action_position_limit'`, `chatNewsNotHeld='chat_news_not_held'`

### 3.6 Topes mensuales de búsquedas pagas

**Costos usados:**
- Búsqueda de `news-context` sin caché: US$0,013–0,058, típico 0,025 (runbook).
- `web-search`: ~US$0,02 (`searchCallUsd` 0,01 × llamadas + tokens).
- Turno de LLM: ~US$0,006.
- Neto por plan: Premium US$7–8,5 y Gold ~12,75 (doc de métricas).

**Unidad de `news-context`:** una por ticker **buscado sin caché** (`missing.length`), no por pedido. Un "¿por qué bajó mi cartera?" con 5 tickers puede costar 5 búsquedas.

| | web/mes | news-context/mes (unidades) | news/día | Peor caso típico (búsquedas + cuota LLM completa) |
|---|---|---|---|---|
| Free | **15** (propuesta 15) | **10** (cortesía semanal) | 5 (sin cambio) | 0,3 + 0,25 + 0,12 ≈ **US$0,67** |
| Premium | **60** (propuesta 100) | **80** (propuesta 60) | **10** (era 5) | 1,2 + 2,0 + 3,0 ≈ **US$6,2** < 7 neto |
| Gold | **100** (propuesta 200) | **160** (propuesta 300) | 40 (sin cambio) | 2,0 + 4,0 + 6,0 ≈ **US$12** < 12,75 neto |

**Por qué ajusté la propuesta:**
- Con 200/300, Gold costaba ~US$17,5 en el peor caso típico, más que su ingreso neto.
- A Premium le subí news-context porque ahora es su diferencial y gasta hasta 5 unidades por pregunta.
- Con el costo alto (US$0,058) Premium queda cerca del empate, pero solo con la cuota completa y todo sin caché.

**Migración `20261105100400_monthly_search_caps.sql`:**
```sql
alter table public.plan_limits
  add column if not exists web_searches_per_month int not null default 0 check (web_searches_per_month >= 0),
  add column if not exists news_context_per_month int not null default 0 check (news_context_per_month >= 0);
update … set web_searches_per_month = case tier when 'free' then 15 when 'premium' then 60 when 'gold' then 100 end
  where web_searches_per_month = 0;
update … set news_context_per_month = case tier when 'free' then 10 when 'premium' then 80 when 'gold' then 160 end
  where news_context_per_month = 0;
alter table public.news_context_usage add column if not exists units int not null default 0;
update public.news_context_usage set units = count where units = 0 and count > 0;

web_search_quota_hit(p_user_id uuid) returns jsonb
news_context_quota_hit(p_user_id uuid, p_units int) returns jsonb   -- p_units 1..5
  -- {"ok": true} | {"ok": false, "reason": "daily_limit" | "monthly_limit"}
  -- mes = mes UTC (igual que _current_usage_month); se suman las filas diarias del mes
  -- si no hay cupo, revierte el incremento (patrón actual)
-- web_search_hit(uuid) y news_context_hit(uuid) (boolean) se redefinen llamando a las nuevas
-- (units = 1), para que las functions ya desplegadas apliquen el tope mensual desde el db push.
-- revoke de public/anon/authenticated en todas.
```
- **Edge:** `web-search` y `news-context` llaman a las RPC nuevas. Con `monthly_limit`, `news-context` devuelve la caché vencida si la hay; si no, 429 `{"error":{"type":"monthly_limit"}}`. `web-search` devuelve 429 `monthly_limit`.
- **App:** `news_context_client.dart` y `web_search_client.dart` mapean `monthly_limit` a `{"status":"limit","reason":"monthly_limit"}`.
- **Asistente:**
  - `get_news` con `context.status = limit` y `reason = monthly_limit` responde con los titulares y suma el guide "This month's source-backed searches are used up; they come back on the 1st. Say it in one short clause; answer from the headlines; do not mention plans".
  - `search_web` con `monthly_limit` lleva el guide "ask the user for the fact instead; do not mention plans".
  - **Sin paywall:** el tope es de costo, no una oferta.
- No se espeja en `PlanSpec`: la app nunca muestra el número. Es como `web_searches_per_day`, que tampoco está espejado.
- **Grandfathering: no hace falta.** El release 1 no se envió y no hay suscriptores reales. Antes del `db push`, el usuario lo confirma con una consulta de solo lectura (§6, R3).

### 3.7 Medición: `locked_feature` en `paywall_viewed` e historial de `app_config`

**Elijo la prop `locked_feature` más una tabla de historial, en lugar de una prop `flags`:**
- Con todo al 100 %, `flags` tendría el mismo valor en todos los eventos.
- Dos flags (`market_taste`, `weekly_report_courtesy`) los decide el servidor, y la app tendría que reevaluarlos de forma asíncrona.
- El historial guarda el instante exacto de cada cambio y sirve para **cualquier** evento, no solo el paywall.
- Si algún día un flag queda en un porcentaje parcial, el cohorte se reconstruye en SQL con `_rollout_bucket(user_id) < percent` vigente a esa fecha.

**App.** `SubscriptionPaywallSheet.show(..., PlanFeature? lockedFeature)` es un parámetro opcional, así que no necesita fases. `paywall_viewed` suma `locked_feature: PaywallSource.snake(f.name)` (p. ej. `held_news`) cuando viene. Es obligatorio en todos los paywalls del chat:
- turno cortado (`ChatPaywall` gana `feature`)
- `QaPaywallRequest.feature`
- acciones del chat
- benchmark, watchlist y posición

**Migración `20261105100000_app_config_history.sql`:**
```sql
create table if not exists public.app_config_history (
  id bigserial primary key,
  key text not null,
  value jsonb,              -- sin 'users' (uuids): no hace falta sumarla al borrado de cuenta
  users_count int,
  op text not null check (op in ('snapshot','insert','update','delete')),
  changed_at timestamptz not null default now()
);
-- RLS on, sin políticas (solo service role). Trigger after insert/update/delete on app_config
-- (update solo si value cambió). Snapshot inicial de todas las filas al migrar (idempotente:
-- solo si la tabla está vacía).
```

Consulta de ejemplo (data-analyst): el `percent` vigente de cada flag para el `created_at` de cada `paywall_viewed`, con un `lateral` sobre `app_config_history` `order by changed_at desc limit 1`.

## 4. Tareas por dueño

**Orden:**
1. backend B1–B5 y flutter F1 en paralelo.
2. assistant A1–A5 contra fakes del contrato, después de F1, que define las constantes y enums que usa.
3. flutter F6 al final (fase C: borra `modeLocked`), después de que assistant avise A3.

### 4.1 porty-backend-dev (`supabase/`)

| # | Archivos | Listo cuando |
|---|---|---|
| B1 | `supabase/migrations/20261105100000_app_config_history.sql` | Tabla, trigger y snapshot. El test SQL inserta, actualiza y borra una fila de prueba y ve 3 filas en el historial sin `users` |
| B2 | `supabase/migrations/20261105100100_conversion_flags_on.sql` | §3.1. Al correrla dos veces: `percent`=100, `users` conservado, `reports`=3 |
| B3 | `supabase/migrations/20261105100200_free_first_import.sql`, `supabase/migrations/20261105100300_free_watchlist.sql` | §3.2 y §3.3. Status, claim, reintento con el mismo `import_id`, `already_used` y otro usuario no lo ve. Free sigue 3 en `watchlist_items` y el 4.º da `watchlist_limit_reached` |
| B4 | `supabase/migrations/20261105100400_monthly_search_caps.sql`, `supabase/functions/web-search/handler.ts`, `supabase/functions/news-context/handler.ts` | §3.6. 429 `monthly_limit`. Las booleanas viejas aplican el tope mensual. Unidades = búsquedas sin caché |
| B5 | `supabase/migrations/20261105100500_held_news.sql`, `supabase/functions/_shared/data_cache.ts` (`newsAllowed`), `supabase/functions/headlines/handler.ts` | §3.4. Premium + ticker en cartera + v2 → 200. Premium + ticker ajeno → 403 `plan_required`. `sec` sin cambios |
| Tests | `supabase/tests/first_full_imports_db_test.sql`, `supabase/tests/monthly_search_caps_db_test.sql`, `supabase/tests/held_news_db_test.sql`, `supabase/tests/app_config_history_db_test.sql`, `supabase/functions/tests/{web_search,news_context,headlines}_test.ts`, `supabase/tests/account_deletion_db_test.sql` (si la guarda de catálogo lo pide) | `deno test` y los tests SQL en verde |

Antes de B3, B5 tiene que cerrar R2: el usuario corre la auditoría de triggers de `positions`.

### 4.2 porty-flutter-dev (`lib/` salvo assistant y genui_core, `test/` espejo, `assets/translations/`)

| # | Archivos | Listo cuando |
|---|---|---|
| F1 (fase A) | `lib/domain/subscription/plan_matrix.dart`, `lib/domain/subscription/subscription_policy.dart`, `lib/features/subscription/providers/subscription_provider.dart` (reasons nuevas + `offerTier`; **`modeLocked` se mantiene**), `lib/features/subscription/config/paywall_source.dart`, `assets/translations/es-ES.json`, `assets/translations/en-US.json` | `heldNews`, `allowsNewsFor`, `portfolioActions` en Free, `watchlistLimit` 3, `leadingMarketingKeys`, highlights §3.5, claves nuevas y borradas. **Avisa a assistant al terminar** |
| F2 | `lib/features/subscription/ui/subscription_paywall_sheet.dart` | Orden por `offerTier`, badge en la primera, promesa, Gold con "Todo lo de Premium" al final, subtítulos con `{limit}`/`{premium}`, `lockedFeature` → `locked_feature` |
| F3 | `lib/features/statement_import/providers/statement_import_provider.dart`, `lib/features/statement_import/view/statement_import_screen.dart`, nuevo `lib/features/statement_import/data/first_import_repository.dart` | §3.2 contra un fake del repositorio |
| F4 | `lib/features/watchlist/view/watchlist_screen.dart`, `lib/features/watchlist/view/watchlist_entry_card.dart` | Free ve su lista con "N de 3". En el tope o con `WatchlistLimitReached` → `watchlistLimit` + `watchlist` + `lockedFeature: marketData` |
| F5 | `lib/presentation/flows/home/ui/widgets/benchmark_locked_card.dart`, `lib/features/weekly_report/view/weekly_report_screen.dart`, `lib/features/etoro/view/etoro_connection_screen.dart`, `lib/features/notifications/view/price_alerts_screen.dart`, `lib/features/notifications/view/create_price_alert_sheet.dart` | Benchmark con reason propio. Literales pasados a constantes `PaywallSource` |
| F7 | `lib/features/weekly_report/providers/weekly_report_controller.dart`, `lib/features/weekly_report/data/weekly_report_repository.dart`, `lib/features/weekly_report/view/weekly_report_screen.dart` (`_GoldTeaser`) | En `numbersLocked`, si el usuario recibió ≥2 informes de regalo (`select count(*) … where courtesy`, RLS propia), el source es `weekly_report_courtesy_ended`; si no, `weekly_report` |
| F6 (fase C) | `subscription_provider.dart`, `subscription_paywall_sheet.dart`, traducciones | Se borran `modeLocked` y sus 2 claves después de A3. `flutter analyze` limpio |
| Tests | `test/domain/subscription/plan_matrix_test.dart` (línea 28: `portfolioActions` en los 3; `heldNews` Premium+Gold; highlights ⊂ features), `test/domain/subscription/subscription_policy_test.dart`, `test/features/subscription/paywall_sheet_test.dart` (`visibleTiersFor` por `offerTier`, badge, promesa, `locked_feature`), `test/features/subscription/paywall_sheet_copy_test.dart`, `test/features/subscription/config/paywall_source_test.dart`, `test/features/statement_import/statement_import_provider_test.dart` (primera completa, `already_used`, sin red = falla cerrado, segunda con tope), `test/features/statement_import/statement_import_screen_test.dart`, `test/features/watchlist/watchlist_test.dart` (Free 3), test de `weekly_report_screen` existente para el source | Verde |

### 4.3 porty-assistant-dev (`lib/features/assistant/`, `genui_core`, evals, allowlist)

| # | Archivos | Listo cuando |
|---|---|---|
| A1 | `lib/features/assistant/tools/market_tools.dart` (`get_news` §3.4, descripción), `lib/features/assistant/tools/answer_guide.dart` (si los guides viven ahí) | Matriz §3.4 completa |
| A2 | `lib/features/assistant/tools/assistant_tool_context.dart` (`reasonFor` exhaustivo, sin `modeLocked`), `lib/features/assistant/tools/assistant_toolset.dart` (prioridad; `ChatPaywall.feature`) | — |
| A3 | `lib/features/assistant/providers/assistant_provider.dart` (borra el chequeo de `portfolioActions`; tope de posiciones en `executeAction`; watchlist con `watchlistLimit`; pasa `lockedFeature`), `lib/features/assistant/view/assistant_screen.dart` (pasa `lockedFeature`). **Avisa a flutter para F6** | — |
| A4 | `lib/features/assistant/tools/action_tools.dart` (`limit_reached` en `propose_buy`), `lib/features/assistant/tools/plan_tools.dart`, `lib/features/assistant/tools/manage_tools.dart` (gates de watchlist) | — |
| A5 | `lib/features/assistant/catalog/kit/qa_plan_scope.dart` (`allowsNews(ticker)`, `QaPaywallRequest.feature`), `lib/features/assistant/catalog/kit/qa_identity.dart`, `lib/features/assistant/catalog/widgets/analysis_widgets.dart` (teaser con `chat_news_not_held` desde la evidencia), `lib/features/assistant/utils/porty_screen_suggestions.dart`, `lib/features/assistant/data/market/news_context_client.dart`, `lib/features/assistant/data/web/web_search_client.dart`, `lib/features/assistant/tools/web_tools.dart` (`monthly_limit`) | — |
| A6 | `test/security/system_prompt_allowlist_test.dart` (solo correrlo) | Si falla: `UPDATE_PROMPT_ALLOWLIST=1 …`, se actualiza `supabase/functions/ai-chat/allowed_system_prompts.json` y se avisa que **hay que desplegar `ai-chat`**. Lo esperado es que pase sin cambios |
| Tests | `test/features/assistant/tools/assistant_tools_test.dart` (get_news: Free held → locked heldNews; Premium held → ok; Premium ajeno → locked `not_held`; mixto → `locked_tickers`; legacy → locked; `monthly_limit` → guide), `test/features/assistant/tools/action_tools_test.dart` (Free sin gate; `limit_reached` en el 11.º ticker), `test/features/assistant/tools/plan_tools_test.dart` y `test/features/assistant/tools/manage_tools_test.dart` (watchlist Free 3), tests de `assistant_toolset` y de `assistant_provider` existentes (`reasonFor`, prioridad, `locked_feature`, source `chat_action_position_limit`) | `flutter test test/features/assistant test/features/genui_core test/security` verde |

Evals pagas: no se corren. Si el usuario quiere, se pueden sumar 2 casos (Premium "¿por qué bajó mi cartera?" y Premium "noticias de TSLA" sin tenerla).

## 5. Criterios de aceptación

1. `flutter analyze` sin warnings nuevos. `flutter test` verde en `test/domain/subscription`, `test/features/{subscription,statement_import,watchlist,assistant,genui_core}` y `test/security`.
2. `deno test` en `supabase/functions/tests` y los tests SQL nuevos en verde con `supabase start`.
3. `grep -rn "modeLocked\|paywall_title_mode_locked" lib assets` → vacío. Las claves de §3.5 no están en ninguno de los dos JSON y los dos JSON tienen las mismas claves.
4. Capturas del paywall (es y en, claro y oscuro):
   - Free desde `marketDataLocked`: Premium primero con el badge.
   - Free desde `goldRequired`: solo Gold.
   - Ajustes: Gold primero.
5. Free importa una captura con 18 posiciones: entran todas y el diagnóstico tiene 18. Una segunda importación con un ticker nuevo muestra el aviso de tope. Reinstalar no devuelve el cupo.
6. Free registra una compra desde el chat. El ticker 11 da `limit_reached` y el paywall `chat_action_position_limit`.
7. `paywall_viewed` desde un turno cortado lleva `locked_feature`. `app_config_history` tiene el cambio de los 5 flags.

## 6. Riesgos y decisiones

**Decisiones:**
- **D1.** Se usa historial de `app_config` en lugar de la prop `flags` (§3.7).
- **D2.** El cupo de primera importación se gasta solo si la importación pasa el tope, y aplica a archivo, captura y texto. Es más generoso que "la primera, sea cual sea", así una prueba de 2 posiciones no lo quema.
- **D3.** eToro gratis y la importación por archivo son cupos separados. Permite dos importaciones sin tope, pero las posiciones no cuestan y unificarlas obligaba a reescribir `etoro_finish_free_import` y a cortar eToro gratis a quien ya importó.
- **D4.** Los topes mensuales quedan más bajos que la propuesta en Gold y en el web de Premium (§3.6, con la cuenta).
- **D5.** El tope mensual no abre paywall.
- **D6.** Las booleanas viejas de las RPC aplican el tope mensual, así el `db push` protege el costo aunque las functions todavía no estén desplegadas.

**Riesgos:**
- **R1.** Con `news_provider = legacy`, Premium no tiene noticias pero el paywall las promete. **Antes de publicar** hay que pasar a v2 siguiendo `docs/runbooks/news-sources-v2.md`. Lo pendiente no técnico (términos de GDELT, *fair access* de la SEC) sigue abierto.
- **R2.** `positions` viene de antes del CLI. El usuario corre, solo lectura, en prod: `select tgname from pg_trigger where tgrelid = 'public.positions'::regclass and not tgisinternal;`. Si aparece un tope, B3 lo adapta.
- **R3.** Grandfathering: el usuario confirma que no hay suscriptores reales con `select environment, count(*) from public.subscription_events group by 1;`.
- **R4.** Normalización de tickers: si `positions.ticker` y el ticker del request no coinciden (sufijos `.BA`, cripto), Premium recibe 403 y el chat cae en `failed`. B5 cubre los casos `.BA` y `-USD` en el test.
- **R5.** El cambio de Premium primero puede bajar la mezcla de Gold. Se lee por `source`/`reason` y el ARPU por expuesto con el historial.

**Necesita OK del usuario:**
- `supabase db push`: 6 migraciones `20261105100000…100500`.
- `supabase functions deploy web-search news-context headlines`.
- `ai-chat`, solo si A6 cambió la allowlist.
- Pasar `news_provider` a v2.
- Las consultas de R2 y R3.
