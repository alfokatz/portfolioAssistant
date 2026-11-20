# Spec: paywall medible, aprobable y con plan anual

**Fecha:** 2026-11-02 · **Autor:** porty-architect · **Estado:** lista para construir
**Implementa:** `docs/product/briefs/2026-11-02-paywall-medible.md` (apuesta #1) + apuesta #2 de `docs/product/roadmap.md` (plan anual). Decisiones: `docs/product/decisions.md` (2026-11-02).
**Insumos:** `docs/business/metrics/2026-11-02-embudo-a-pago.md` §5 (plan de eventos), `docs/business/monetization/2026-11-02-auditoria-conversion.md` P1 y P4.

---

## 1. Objetivo

Hoy no sabemos qué paywall vende ni cuánto se cobra, y el paywall corre riesgo de rechazo de Apple (3.1.2). Al terminar:

- cada apertura, toque, compra/restauración y cierre del paywall queda en `product_events` con un `source` específico (nunca el `reason` genérico);
- cada evento de RevenueCat queda en `subscription_events` con precio, moneda, tienda, trial, entorno, producto y `paywall_source`;
- el paywall muestra los términos de renovación junto al botón y links a Términos y Privacidad, títulos por motivo sin "modos" y el medidor de consultas solo cuando el motivo es la cuota;
- si el offering de RevenueCat trae los anuales, el paywall ofrece Mensual / Anual con el ahorro calculado con precios reales; si no, se ve igual que hoy.

**Listo** = criterios de la sección 5 en verde + humo de compra en sandbox (iOS y Android) con las filas verificadas en las dos tablas.

## 2. Fuera de alcance

- Orden de planes según motivo (diciembre). Gold sigue primero.
- Prueba de Gold, ofertas introductorias o trials de tienda, cambios de precio o de cuotas.
- Paywalls nuevos (los de la apuesta #3 van en `2026-11-02-sin-callejones.md`).
- `locked_feature_shown`, `weekly_report_opened`, `app_opened` (viajan con la apuesta #5 o en diciembre). `broker_connect_result` y `push_opt_in` van en la spec de callejones.
- Dashboard: alcanzan las consultas de porty-data-analyst.
- SDK de analytics de terceros.
- Cambios en el prompt, las tools o el catálogo del chat. **No toca la allowlist** (ver §6).

---

## 3. Contrato de datos

### 3.1 `PaywallSource` (app): catálogo de orígenes

Archivo nuevo `lib/features/subscription/config/paywall_source.dart` (dueño: flutter-dev). `abstract final class PaywallSource` con constantes `String` y dos helpers. Formato: `^[a-z][a-z0-9_]{2,59}$`. Nunca igual a un `PaywallReason.name`.

| Constante | Valor | Lugar (archivo) | `PaywallReason` |
|---|---|---|---|
| `settings` | `settings` | `settings_subscription_card.dart` | `plans` (nuevo) |
| `addPositionLimit` | `add_position_limit` | `config/navigation/app_shell.dart` | `positionLimit` (nuevo) |
| `importPositionLimit` | `statement_import_position_limit` | `statement_import_screen.dart:805` | `positionLimit` |
| `importQuota` | `statement_import_quota` | `statement_import_screen.dart:260` | `quotaExceeded` |
| `allocation` | `allocation` | `allocation_screen.dart` | `allocationPlan` (nuevo) |
| `allocationWizard` | `allocation_wizard` | `allocation_wizard_screen.dart` | `allocationPlan` |
| `watchlist` | `watchlist` | `watchlist_screen.dart` | `marketDataLocked` |
| `binanceConnect` | `binance_connect` | `binance_screen.dart` (botón y error de plan) | `brokerSync` |
| `snaptradeConnect` | `snaptrade_connect` | `snaptrade_screen.dart` (botón y `snaptrade_plan_required`) | `brokerSync` |
| `snaptradeMulti` | `snaptrade_multi` | `snaptrade_screen.dart` (`_addAnother`, `snaptrade_connection_limit`) | `goldRequired` |
| `quotaZero` | `quota_zero` | chat: turno rechazado por cuota | `quotaExceeded` |
| `quotaZeroHeader` | `quota_zero_header` | chat: tocar el contador en 0 | `quotaExceeded` |
| `chatActionWatchlist` | `chat_action_watchlist` | `assistant_provider.executeAction` | `marketDataLocked` |
| `chatActionBroker` | `chat_action_broker` | idem | `brokerSync` |
| `chatActionMultiBroker` | `chat_action_multi_broker` | idem | `goldRequired` |
| `chatActionAllocation` | `chat_action_allocation` | idem | `allocationPlan` |
| `chatActionPortfolio` | `chat_action_portfolio` | idem (`portfolioActions`) | `modeLocked` |
| `chatPlanSave` | `chat_plan_save` | `assistant_provider` (guardar plan de cartera) | `allocationPlan` |
| `chatAlertLimit` | `chat_alert_limit` | `assistant_provider._createAlert` | `priceAlerts` |
| *(ya existen, no cambian)* | `home_benchmark`, `weekly_report`, `weekly_report_sp500`, `etoro_connect`, `price_alert_limit`, `price_alert_reactivate`, `weekly_free_analysis`, `analysis_locked_*` | — | — |
| *(existen, se normalizan; dueño assistant-dev)* | `chip_<feature>` → `PaywallSource.snake` del `PlanFeature.name` (`chip_company_analysis`); `answer_locked_<a>+<b>` → unidos con `_` (`answer_locked_fundamentals_earnings`) | `catalog/kit/qa_identity.dart`, `catalog/widgets/analysis_widgets.dart` | sin cambio |

Helpers:

```dart
/// Turno del chat cortado porque todo lo pedido estaba fuera del plan.
/// PlanFeature.investSimulation → "chat_turn_locked_invest_simulation".
static String chatTurnLocked(PlanFeature feature);

/// Valida el formato (lo usan el assert de `show` y los tests).
static bool isValid(String source);

/// camelCase → snake_case ("companyAnalysis" → "company_analysis"). Lo usan
/// chatTurnLocked y los sources armados en el catálogo del chat.
static String snake(String value);
```

Nota: `quota_zero` reemplaza al `chat_quota` de ejemplo del brief (mismo significado; coincide con la métrica de la apuesta #3 del roadmap).

### 3.2 `PaywallReason` (app): motivos nuevos

En `lib/features/subscription/providers/subscription_provider.dart` se agregan: `plans`, `positionLimit`, `simulations`, `goals`, `allocationPlan`. `modeLocked` queda como fallback genérico (benchmark, operaciones de cartera, S&P del informe) con copy nuevo.

| Reason | Tiers visibles (igual que hoy) | Medidor de uso |
|---|---|---|
| `goldRequired` | Gold | no |
| `quotaExceeded` | Gold + Premium (Premium ve solo Gold) | **sí** |
| todos los demás | Gold + Premium (Premium ve solo Gold) | no |

Mapeo en el chat (`AssistantToolContext.lockedFeature`, dueño assistant-dev): `investSimulation → simulations`, `goals → goals`, `allocationPlan → allocationPlan`, `marketData → marketDataLocked`, Gold → `goldRequired`, resto → `modeLocked`. `AssistantTurnPolicy.paywallFor` corta el turno con cualquier reason de nivel Premium (`modeLocked`, `simulations`, `goals`, `allocationPlan`, `marketDataLocked`), en ese orden de prioridad.

### 3.3 `SubscriptionPaywallSheet.show` (app): firma

```dart
static Future<void> show(
  BuildContext context,
  WidgetRef ref, {
  required PaywallReason reason,
  required String source,          // antes String?; ver §4 fase A/B
  VoidCallback? onUpgraded,
  WidgetBuilder? preview,
});
```

`assert(PaywallSource.isValid(source) && source != reason.name)`. `PaywallSourceLog` se **borra** (archivo y usos): el único registro es `product_events`.

### 3.4 Eventos en `product_events` (tabla existente, sin migración)

Se agregan a `enum ProductEvent` (`lib/features/product_events/data/product_events.dart`), todos `once: false`. Se registran con `ref.read(productEventsProvider).log(...)`. Sin datos personales ni montos de la cartera.

| Evento (`name`) | Cuándo | `props` |
|---|---|---|
| `paywall_viewed` | `show` abre la hoja (no en Gold, que retorna antes) | `reason`, `source`, `tier`, `visible_tiers`, `queries_used`, `queries_limit` |
| `paywall_plan_tapped` | toque en el CTA de un plan, antes de comprar | `tier`, `period`, `source` |
| `purchase_result` | al volver de comprar o de restaurar | `action`, `tier`*, `period`*, `source`, `result`, `error_code`** |
| `paywall_dismissed` | la hoja se cierra sin compra ni restauración exitosa | `source`, `seconds_open`, `tapped_plan` |

\* solo con `action: purchase`. \*\* solo con `result: failed`.

Tipos y valores:

```jsonc
// paywall_viewed
{"reason": "positionLimit",            // PaywallReason.name
 "source": "add_position_limit",
 "tier": "free",                       // SubscriptionTier.name actual
 "visible_tiers": ["gold", "premium"],
 "queries_used": 7, "queries_limit": 20}

// paywall_plan_tapped
{"tier": "premium", "period": "annual", "source": "add_position_limit"}

// purchase_result
{"action": "purchase",                  // "purchase" | "restore"
 "tier": "premium", "period": "annual",
 "source": "add_position_limit",
 "result": "failed",                    // "success" | "cancelled" | "failed" | "not_configured"
 "error_code": "networkError"}          // ver abajo

// paywall_dismissed
{"source": "add_position_limit", "seconds_open": 14, "tapped_plan": true}
```

`error_code`: un código corto, nunca el mensaje libre de la tienda. Valores: `offerings_unavailable`, `package_not_found`, `invalid_tier`, el `PurchasesErrorCode.name` de RevenueCat (`networkError`, `storeProblemError`, `productNotAvailableForPurchaseError`…) o `unknown`. Para eso `RevenueCatPurchaseFailed` suma un campo `code` (el `message` sigue para debug).

### 3.5 RevenueCat (app)

**Atributo del suscriptor:** antes de `Purchases.purchase`, `Purchases.setAttributes({'paywall_source': source})`. Si falla, se compra igual (try/catch silencioso).

**Productos y packages** (`lib/features/subscription/config/subscription_catalog.dart`):

| Tier | Período | Package id (offering `default`) | Product id (tiendas) | Entitlement |
|---|---|---|---|---|
| Premium | mensual | `premium_monthly` | `portfolio_premium_monthly` | `premium` |
| Gold | mensual | `gold_monthly` | `portfolio_gold_monthly` | `gold` |
| Premium | anual | `premium_annual` | `portfolio_premium_annual` | `premium` |
| Gold | anual | `gold_annual` | `portfolio_gold_annual` | `gold` |

Búsqueda del package: por package id; si no, por `storeProduct.identifier == productId` **o** que empiece con `"$productId:"` (Google Play devuelve `producto:baseplan`). Esto vale también para los mensuales.

**Oferta que ve el paywall** (reemplaza `fetchTierPrices` / `subscriptionTierPricesProvider`):

```dart
enum BillingPeriod { monthly, annual }   // .name es el valor de `period` en los eventos

class TierPrice {
  final String priceString;   // storeProduct.priceString, localizado por la tienda
  final double price;         // storeProduct.price
  final String currencyCode;  // storeProduct.currencyCode
}

class PaywallOffer {
  static const empty = PaywallOffer({});
  final Map<SubscriptionTier, Map<BillingPeriod, TierPrice>> prices;

  TierPrice? priceOf(SubscriptionTier tier, BillingPeriod period);

  /// El selector Mensual/Anual aparece solo si TODOS los tiers visibles
  /// tienen anual y mensual.
  bool hasAnnualFor(Iterable<SubscriptionTier> tiers);

  /// floor((1 - anual / (12 × mensual)) × 100). null si falta alguno, si
  /// las monedas difieren o si da < 1.
  int? annualSavingsPercent(SubscriptionTier tier);
}

// RevenueCatService
Future<PaywallOffer> fetchOffer();   // PaywallOffer.empty si no está configurado o falla
Future<RevenueCatPurchaseResult> purchase(SubscriptionTier tier, BillingPeriod period, {required String source});

// SubscriptionNotifier
Future<RevenueCatPurchaseResult> purchaseTier(SubscriptionTier tier, {BillingPeriod period = BillingPeriod.monthly, required String source});

// providers
final paywallOfferProvider = FutureProvider<PaywallOffer>(...);   // reemplaza subscriptionTierPricesProvider
```

`PaywallOffer.fromOffering(Offering)` es una función pura (testeable con `Offering`/`Package`/`StoreProduct` construidos a mano).

**El plan no cambia en el servidor:** el webhook calcula el tier por entitlements, así que los anuales funcionan sin tocar `planFrom` siempre que el usuario los asocie a `premium` / `gold`.

### 3.6 Interruptor `app_config.paywall_annual`

Fila nueva (migración del backend), formato `PortyRolloutFlag`:

```json
{"percent": 100, "users": []}
```

- Arranca en **100**: el anual igual solo aparece si la tienda devuelve los productos (antes de la aprobación no los devuelve en producción). El interruptor es para apagarlo sin publicar. Además, el revisor de Apple tiene que poder ver y comprar el anual en la revisión: con 0 no lo encontraría.
- Lectura en la app: archivo nuevo `lib/features/subscription/config/conversion_flags.dart` (dueño flutter-dev):

```dart
abstract final class ConversionFlags {
  static final paywallAnnual = PortyRolloutFlag('paywall_annual');
}

/// false sin sesión, sin red o sin la fila (falla cerrado).
final paywallAnnualEnabledProvider = FutureProvider<bool>(...);
```

`PortyRolloutFlag` se importa de `lib/features/assistant/data/porty_rollout_flag.dart` **sin editarlo** (es de assistant-dev).

Selector visible = `paywallAnnualEnabledProvider == true` **y** `offer.hasAnnualFor(visibleTiers)`. Período por defecto: **Mensual** (ver §6).

### 3.7 Lo que ve el usuario (contrato de UI y textos)

Orden de la hoja: manija · cerrar · título · subtítulo · preview (si hay) · **medidor (solo `quotaExceeded`)** · selector Mensual/Anual (si aplica) · cards de planes · bloque de términos · Restaurar compras.

**Card de plan:**
- Precio: `{price}/mes` o `{price}/año` según el período. En anual, debajo y en texto secundario: `Ahorrás {n} %` si `annualSavingsPercent != null`. Sin badge nuevo.
- "N consultas por mes" baja a texto secundario después de la lista de features: `Uso justo: {count} consultas por mes`.
- Debajo del CTA, en texto secundario: `Se renueva cada {mes|año} a {price}. Cancelás cuando quieras.` (se omite si no hay precio).

**Bloque de términos** (siempre, aunque falte el precio), debajo de las cards: texto de renovación + `Términos` · `Privacidad` como links tocables (≥ 48 dp) que abren en el navegador externo con `url_launcher`. URLs en un archivo nuevo `lib/config/legal/legal_links.dart` (`abstract final class LegalLinks { static const terms = 'https://portfolioai.app/terms'; static const privacy = 'https://portfolioai.app/privacy'; }`, las mismas que ya usan Ajustes y el login). Tienda: `App Store` en iOS/macOS, `Google Play` en Android.

**Claves de traducción** (flutter-dev; en `es-ES.json` y `en-US.json`). Las marcadas **[C]** las revisa y fija **porty-compliance** antes del release; las **[G]** pasan por la voz de porty-growth-lead. Los textos de abajo son borrador.

| Clave | es-ES (borrador) | en-US (borrador) |
|---|---|---|
| `paywall_renews_line` **[C]** | Se renueva cada {period} a {price}. Cancelás cuando quieras. | Renews every {period} at {price}. Cancel anytime. |
| `paywall_period_month` / `_year` | mes / año | month / year |
| `paywall_terms_block` **[C]** | El cobro se hace en tu cuenta de {store} al confirmar la compra. La suscripción se renueva sola salvo que la canceles al menos 24 horas antes de que termine el período. La gestionás y la cancelás desde {store}. | Payment is charged to your {store} account at confirmation of purchase. The subscription renews automatically unless canceled at least 24 hours before the end of the current period. Manage or cancel it in {store}. |
| `paywall_terms_link` / `paywall_privacy_link` | Términos / Privacidad | Terms / Privacy |
| `paywall_price_per_year` | {price}/año | {price}/year |
| `paywall_annual_savings` **[C]** | Ahorrás {percent} % | Save {percent}% |
| `paywall_period_monthly` / `_annual` | Mensual / Anual | Monthly / Annual |
| `paywall_fair_use` | Uso justo: {count} consultas por mes | Fair use: {count} queries per month |
| `paywall_title_plans` / `paywall_subtitle_plans` **[C][G]** | Elegí tu plan / Premium para mirar el mercado. Gold para entender el porqué. | Choose your plan / Premium to follow the market. Gold to understand the why. |
| `paywall_title_position_limit` / `_subtitle_` **[C][G]** | Traé toda tu cartera / Free llega a {limit} posiciones. Con Premium cargás todas y Porty la mira completa. | Bring your whole portfolio / Free covers up to {limit} positions. With Premium you add them all and Porty sees the full picture. |
| `paywall_title_simulations` / `_subtitle_` **[C][G]** | Probá escenarios con datos reales / Con Premium, Porty simula cuánto podría crecer un aporte. Es educativo, no una recomendación. | Try scenarios with real data / With Premium, Porty simulates how a contribution could grow. Educational, not a recommendation. |
| `paywall_title_goals` / `_subtitle_` **[C][G]** | Ponele número a tu meta / Con Premium, Porty calcula cuánto aportar y te avisa si te atrasás. | Put a number on your goal / With Premium, Porty works out how much to contribute and tells you if you fall behind. |
| `paywall_title_allocation_plan` / `_subtitle_` **[C][G]** | Armá tu plan de cartera / Con Premium definís cuánto querés en cada cosa y Porty te dice cómo repartir el próximo aporte. | Build your portfolio plan / With Premium you set your targets and Porty shows how to split your next contribution. |
| `paywall_title_mode_locked` / `_subtitle_` (se reescriben) **[C][G]** | Esto viene con Premium / Mejorá tu plan para usar esta función. | This comes with Premium / Upgrade your plan to use this feature. |
| `settings_upgrade_coming_soon` (se reescribe) | Las compras no están disponibles ahora. Probá de nuevo en un rato. | Purchases aren't available right now. Try again in a bit. |

`paywall_queries_month` **se queda**: lo sigue usando `settings_subscription_card._description`.

### 3.8 Base: `subscription_events` (migración nueva)

Archivo `supabase/migrations/20261102120000_subscription_events.sql` (dueño backend-dev). Idempotente.

```sql
create table if not exists public.subscription_events (
  id bigint generated always as identity primary key,
  event_id text not null,                       -- event.id de RevenueCat
  user_id uuid references auth.users (id) on delete set null,  -- null: id anónimo de RC o usuario borrado
  event_type text not null,                     -- INITIAL_PURCHASE, RENEWAL, CANCELLATION, EXPIRATION, PRODUCT_CHANGE, TEST…
  product_id text,
  new_product_id text,                          -- solo PRODUCT_CHANGE
  store text,                                   -- APP_STORE, PLAY_STORE, PROMOTIONAL…
  period_type text,                             -- NORMAL, TRIAL, INTRO, PROMOTIONAL, PREPAID
  is_trial boolean not null default false,      -- period_type = 'TRIAL'
  environment text,                             -- SANDBOX | PRODUCTION
  is_sandbox boolean generated always as (environment is distinct from 'PRODUCTION') stored,
  price_usd numeric(12,4),                      -- event.price (USD, bruto; negativo en reembolsos)
  price_local numeric(14,4),                    -- event.price_in_purchased_currency
  currency text,                                -- event.currency
  takehome_pct numeric(5,4),                    -- event.takehome_percentage
  paywall_source text,                          -- event.subscriber_attributes.paywall_source.value
  reason text,                                  -- cancel_reason ?? expiration_reason
  event_at timestamptz,                         -- event_timestamp_ms
  purchased_at timestamptz,                     -- purchased_at_ms
  expires_at timestamptz,                       -- expiration_at_ms
  created_at timestamptz not null default now(),
  constraint subscription_events_event_id_key unique (event_id)
);

create index if not exists subscription_events_user_idx
  on public.subscription_events (user_id, event_at);
create index if not exists subscription_events_type_idx
  on public.subscription_events (event_type, event_at);

alter table public.subscription_events enable row level security;
-- Sin políticas: la app no lee ni escribe. Solo la service role (webhook).
revoke all on public.subscription_events from public, anon, authenticated;
grant select, insert on public.subscription_events to service_role;
```

Sin `check` sobre valores de RevenueCat (un valor nuevo no puede romper el webhook). Sin guardar el evento crudo: `subscriber_attributes` puede traer `$email` y otros datos personales.

**`product_funnel`** (misma migración): `create or replace view` copiando la definición actual **sin cambiar** columnas ni orden y agregando al final:

- `min_to_first_paywall` = minutos desde el alta hasta el primer `product_events.name = 'paywall_viewed'`;
- `min_to_purchase` = minutos desde el alta hasta el primer `subscription_events.event_at` con `event_type = 'INITIAL_PURCHASE'` y `not is_sandbox`.

Repetir `revoke all on public.product_funnel from public, anon, authenticated;`.

**Interruptor:** `supabase/migrations/20261102120100_paywall_annual_flag.sql`:

```sql
insert into public.app_config (key, value)
values ('paywall_annual', '{"percent": 100, "users": []}'::jsonb)
on conflict (key) do nothing;
```

### 3.9 Webhook `revenuecat-webhook`

Request (de RevenueCat, sin cambios de auth: `Authorization: Bearer $REVENUECAT_WEBHOOK_SECRET`). Campos que se leen de `event`, todos opcionales salvo `id` y `type`:

```jsonc
{"event": {
  "id": "c1a2…", "type": "INITIAL_PURCHASE",
  "app_user_id": "<uuid>", "original_app_user_id": "<uuid>", "aliases": ["…"],
  "product_id": "portfolio_premium_annual", "new_product_id": null,
  "store": "APP_STORE", "period_type": "NORMAL", "environment": "PRODUCTION",
  "price": 99.99, "price_in_purchased_currency": 99.99, "currency": "USD",
  "takehome_percentage": 0.85,
  "subscriber_attributes": {"paywall_source": {"value": "add_position_limit", "updated_at_ms": 1762100000000}},
  "cancel_reason": null, "expiration_reason": null,
  "event_timestamp_ms": 1762100000000, "purchased_at_ms": 1762100000000, "expiration_at_ms": 1793636000000
}}
```

Flujo nuevo (en `handle`, después de validar el secreto y parsear):

1. Si hay `event.id` y `event.type`: `upsert` en `subscription_events` con `onConflict: 'event_id', ignoreDuplicates: true` (los reintentos de RevenueCat no duplican). `user_id` = `app_user_id` si es uuid, si no el primero de `affectedUserIds(event)`, si no `null`. Se guarda **también** si no hay usuario de la app (TEST, anónimos). Mapeo en una función pura exportada `eventRow(event): Record<string, unknown>` (testeable sin base).
2. Sigue igual que hoy: ignorar sin usuario / recalcular el plan por usuario.
3. Si el paso 1 falló: el plan se recalcula igual, se registra `outcome: 'event_store_error'` en `subscription_sync_log` y la respuesta es **500** `event_store_error` (RevenueCat reintenta; las dos operaciones son idempotentes). Si el paso 1 anduvo, la respuesta no cambia (`200 {ok, tiers}` o `{ok, ignored}`).

Respuesta: misma forma que hoy. Ningún consumidor nuevo.

---

## 4. Tareas por dueño

Dos dueños nunca tocan el mismo archivo. Traducciones: solo flutter-dev.

### porty-backend-dev (independiente; arranca ya)

| Archivo | Qué |
|---|---|
| `supabase/migrations/20261102120000_subscription_events.sql` (nuevo) | Tabla, índices, RLS, grants, `product_funnel` con 2 columnas al final (§3.8) |
| `supabase/migrations/20261102120100_paywall_annual_flag.sql` (nuevo) | Fila `paywall_annual` (§3.6) |
| `supabase/functions/revenuecat-webhook/handler.ts` | `eventRow` + guardado previo + manejo de error (§3.9) |
| `supabase/functions/tests/revenuecat_webhook_test.ts` | Tests nuevos (§5) |

No depende de nadie. Avisa a flutter-dev y a porty-data-analyst cuando la migración pase local.

### porty-flutter-dev (dos fases para no romper la compilación del chat)

**Fase A** (primero, chica; al terminar avisa a assistant-dev): `PaywallSource`, `PaywallReason` nuevos, `ConversionFlags`, `source` todavía `String?` en `show`.
**Fase B**: todo lo demás. **Fase C** (cuando assistant-dev avise que pasó `source` en todas sus llamadas): `source` pasa a `required String` y se agrega el `assert`.

| Archivo | Qué |
|---|---|
| `lib/features/subscription/config/paywall_source.dart` (nuevo) | §3.1 |
| `lib/features/subscription/config/conversion_flags.dart` (nuevo) | §3.6 |
| `lib/features/subscription/config/subscription_catalog.dart` | Ids anuales, `BillingPeriod`, `packageIdFor(tier, period)`, `productIdFor(tier, period)` |
| `lib/features/subscription/services/revenue_cat_service.dart` | `fetchOffer`, `purchase(tier, period, source)`, `setAttributes`, `code` en `RevenueCatPurchaseFailed`, match por prefijo |
| `lib/features/subscription/services/paywall_offer.dart` (nuevo) | `TierPrice`, `PaywallOffer`, `fromOffering` |
| `lib/features/subscription/services/paywall_source_log.dart` | **Borrar** |
| `lib/features/subscription/providers/subscription_provider.dart` | Reasons nuevos, `purchaseTier(..., period, source)`, `paywallOfferProvider` |
| `lib/features/subscription/ui/subscription_paywall_sheet.dart` | Eventos, selector, términos, títulos, medidor solo en cuota, `Uso justo` |
| `lib/features/product_events/data/product_events.dart` | 4 eventos nuevos |
| `lib/config/legal/legal_links.dart` (nuevo) | URLs de Términos y Privacidad |
| `lib/presentation/flows/settings/ui/widgets/settings_subscription_card.dart` | `plans` + `settings` |
| `lib/config/navigation/app_shell.dart` | `positionLimit` + `add_position_limit` |
| `lib/features/statement_import/view/statement_import_screen.dart` | 2 llamadas (§3.1) |
| `lib/features/allocation/view/allocation_screen.dart`, `allocation_wizard_screen.dart` | `allocationPlan` + source |
| `lib/features/watchlist/view/watchlist_screen.dart` | source |
| `lib/features/binance/view/binance_screen.dart` | source |
| `lib/features/snaptrade/view/snaptrade_screen.dart` | sources (`_paywall` recibe source) |
| `assets/translations/es-ES.json`, `assets/translations/en-US.json` | §3.7 |
| `test/features/subscription/paywall_sheet_test.dart` | Reescribir sin `PaywallSourceLog` (fake de `ProductEvents` como en `first_portfolio_watcher_test.dart`) |
| `test/features/subscription/paywall_offer_test.dart` (nuevo), `paywall_source_test.dart` (nuevo), `subscription_catalog_test.dart` | §5 |

Arranca contra el contrato: no necesita el backend (los eventos van a una tabla que ya existe; el anual se prueba con `PaywallOffer` armado a mano).

### porty-assistant-dev (después de la fase A de flutter-dev)

| Archivo | Qué |
|---|---|
| `lib/features/assistant/tools/assistant_tool_context.dart` | `lockedFeatures` (`Set<PlanFeature>`) y mapeo feature → reason (§3.2) |
| `lib/features/assistant/tools/assistant_toolset.dart` | `paywallFor` devuelve `ChatPaywall(reason, source)` (clase chica en el mismo archivo) con prioridad §3.2 y `PaywallSource.chatTurnLocked(feature)` |
| `lib/features/assistant/states/assistant_state.dart` | `paywallSource` junto a `paywallReason` (se setean y limpian juntos) |
| `lib/features/assistant/providers/assistant_provider.dart` | Source en cada lugar que setea `paywallReason` (§3.1); `TurnAbortedException` lleva un `ChatPaywall` (es `Object`, no toca genui_core) |
| `lib/features/assistant/view/assistant_screen.dart` | Pasar `state.paywallSource` (turno), `quota_zero_header` (contador) y `request.source` (Gold, ya está) |
| `lib/features/assistant/catalog/kit/qa_identity.dart`, `lib/features/assistant/catalog/widgets/analysis_widgets.dart` | Normalizar `chip_*` y `answer_locked_*` a snake_case con `PaywallSource.snake` (§3.1). Solo cambia el string del source, no lo que ve ni recibe el modelo: el hash del prompt no se mueve (lo confirma el criterio 16) |
| `test/features/assistant/...` (los que correspondan) | §5 |

No toca prompt, reglas, tools expuestas al modelo, catálogo ni widgets del catálogo: el JSON `locked` que ve el modelo no cambia. Al terminar avisa a flutter-dev para la fase C.

### Orden

`backend` ∥ `flutter A` → `assistant` ∥ `flutter B` → `flutter C`. Integración: no hay dependencia de runtime entre app y backend; se verifican juntos en el humo de sandbox.

---

## 5. Criterios de aceptación

**Backend** (`deno test` en `supabase/functions/tests/revenuecat_webhook_test.ts`, contra la base local):
1. Un `INITIAL_PURCHASE` con todos los campos de §3.9 deja una fila con `price_usd`, `price_local`, `currency`, `store`, `period_type`, `environment`, `is_sandbox = false`, `product_id`, `paywall_source`, `event_at` correctos; `period_type: 'TRIAL'` → `is_trial = true`; `environment: 'SANDBOX'` → `is_sandbox = true`.
2. El mismo `event.id` dos veces → una sola fila; el plan queda igual.
3. Evento sin usuario de la app (`$RCAnonymousID:…`) → fila con `user_id null` y respuesta `ignored` como hoy.
4. Si el insert falla (tabla renombrada en el test o fake de db), el plan se recalcula, hay `event_store_error` en `subscription_sync_log` y la respuesta es 500.
5. Los tests actuales del webhook siguen verdes.
6. `supabase db reset` local aplica las migraciones dos veces sin error (idempotencia) y `select * from product_funnel limit 1` devuelve las columnas viejas en el mismo orden + las 2 nuevas.
7. Con un JWT de `authenticated`, `select` e `insert` sobre `subscription_events` fallan por permisos.

**App** (`flutter test test/features/subscription test/features/assistant test/features/genui_core test/security`, `flutter analyze` sin warnings nuevos):
8. `show` no compila sin `source` (fase C). `paywall_source_test`: todas las constantes son únicas, cumplen el formato y ninguna es un `PaywallReason.name`; `chatTurnLocked(PlanFeature.investSimulation) == 'chat_turn_locked_invest_simulation'`.
9. Widget: abrir el paywall registra `paywall_viewed` con las 6 props; tocar un plan registra `paywall_plan_tapped` y luego `purchase_result` con el `result` del fake (los 4 casos, `error_code` solo en `failed`); Restaurar registra `purchase_result{action: restore}`; cerrar sin comprar registra `paywall_dismissed` con `seconds_open` entero; comprar con éxito **no** registra `paywall_dismissed`.
10. Widget: `purchase` del fake recibe el `source` y se llama `setAttributes` antes (o se verifica en el fake del service).
11. Widget: con `quotaExceeded` se ve el medidor; con `goldRequired`, `plans`, `positionLimit` no.
12. Widget: en todos los reasons se ven el bloque de términos, los dos links y "Restaurar compras"; con precio, cada card muestra `paywall_renews_line` con el precio y el período elegido.
13. Widget: `plans` muestra "Elegí tu plan"; ningún título ni subtítulo contiene "modo" ni "Pro" (test sobre los dos JSON para las claves `paywall_title_*`, `paywall_subtitle_*` y `settings_upgrade_coming_soon`).
14. `paywall_offer_test`: con mensuales y anuales → selector visible y `annualSavingsPercent` = floor correcto; sin anuales, con monedas distintas o con anual de un solo tier visible → sin selector; con `paywallAnnualEnabledProvider = false` → sin selector aunque haya anuales; match por prefijo `producto:baseplan`.
15. Chat: un turno cortado por simulación abre el paywall con `simulations` y `chat_turn_locked_invest_simulation`; cuota agotada → `quota_zero`; contador en 0 → `quota_zero_header`.
16. `flutter test test/security/system_prompt_allowlist_test.dart` verde **sin** `UPDATE_PROMPT_ALLOWLIST` (no cambió el prompt).

**Humo en sandbox** (porty-qa-engineer, iOS y Android, con cuenta de test):
17. Comprar Premium mensual desde Ajustes, cancelar una compra de Gold anual desde el tope de posiciones y restaurar: en `product_events` aparecen `paywall_viewed`/`paywall_plan_tapped`/`purchase_result`/`paywall_dismissed` con su `source`; en `subscription_events` aparece el `INITIAL_PURCHASE` con `environment = 'SANDBOX'`, `store`, `price_*`, `currency` y `paywall_source = 'settings'`.
18. Captura del paywall con términos y links (iOS y Android, claro y oscuro) para porty-ui-reviewer; los dos links abren una página real.

---

## 6. Riesgos y decisiones

**Decisiones**
- **Eventos en `product_events`, no tabla `paywall_events`** (decisión del PO): una sola fuente; `ProductEvents.log` ya nunca rompe un flujo.
- **`PaywallSourceLog` se borra** en vez de "complementarse": dos registros divergen y el de memoria no le sirve a nadie fuera de los tests.
- **`source` obligatorio en compilación** (no solo un test que busca texto): es la garantía más fuerte y gratis. Fases A/B/C para no dejar el chat sin compilar mientras assistant-dev trabaja.
- **Sin `PlanFeature` nueva**: el anual es un período de cobro, no una capacidad. El tier lo siguen dando los entitlements.
- **Interruptor anual en 100**: el gate real es que la tienda devuelva el producto; con 0, el revisor de Apple no vería el anual y rechazaría por IAP no encontrado.
- **Mensual por defecto en el selector**: menos riesgo de "me cobró un año" (guardarraíl del mes) y no cambia nada para quien no toca el selector. Cambiarlo a anual por defecto es una decisión de producto para diciembre, con datos.
- **Ahorro calculado, nunca escrito**: si no hay los dos precios en la misma moneda, no se muestra.
- **Webhook: guardar antes, responder 500 si no se pudo guardar**: el plan nunca queda trabado por la analítica, y RevenueCat reintenta lo que faltó.
- **`user_id on delete set null`** (no `cascade`): el historial de ingresos sobrevive a la baja de la cuenta sin datos personales. Lo confirma **porty-compliance** / **porty-security-reviewer**; si piden `cascade`, es un cambio de una palabra antes del `db push`.
- **Atribución**: `paywall_source` de RevenueCat es el último valor seteado; para atribuir compras usar solo `INITIAL_PURCHASE` y `PRODUCT_CHANGE` (nota para porty-data-analyst).

**Descartado**
- Tabla `paywall_events` con RPC (auditoría P1): duplica `product_events`.
- Leer el período del `subscriptionPeriod` ISO de la tienda para decidir mensual/anual: los package ids son explícitos y testeables.
- Guardar el evento crudo de RevenueCat en `jsonb`: trae `subscriber_attributes` con posibles datos personales.

**Riesgos**
- Ofertas introductorias o trials configurados en la tienda: la app **no** los muestra y Apple exige explicarlos. El usuario **no** debe configurar ofertas introductorias en los anuales en este release.
- Si las páginas `portfolioai.app/terms` y `/privacy` no existen o no hablan de suscripciones, rechazo seguro: verificarlo antes del envío (usuario + compliance). Si Términos no cubre la renovación automática, agregar el link al EULA estándar de Apple en la ficha.
- Google Play con base plans: el match por prefijo lo cubre; se valida en el humo de Android.

**Textos para porty-compliance:** todas las claves **[C]** de §3.7 (renovación, términos, ahorro y títulos/subtítulos por motivo; `simulations` en particular por "no es una recomendación").

**Toca el prompt o el catálogo del chat:** **no**. No hace falta regenerar la allowlist ni desplegar `ai-chat`.

**Necesita OK del usuario**
1. `db push` de `20261102120000_subscription_events.sql` y `20261102120100_paywall_annual_flag.sql` (antes del deploy del webhook).
2. Deploy de `revenuecat-webhook`.
3. Crear `portfolio_premium_annual` y `portfolio_gold_annual` en App Store Connect (mismo grupo que los mensuales) y Google Play, asociarlos a los entitlements `premium`/`gold` y agregarlos al offering `default` como packages `premium_annual` y `gold_annual`. Precio propuesto 10× el mensual: lo decide el usuario.
4. Texto final de compliance en las claves [C].
5. Publicación del release (la app funciona sin los anuales).
