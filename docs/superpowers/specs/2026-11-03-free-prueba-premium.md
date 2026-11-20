# Spec: Free prueba Premium (3 consultas de mercado por mes)

**Fecha:** 2026-11-03 · **Autor:** porty-architect · **Estado:** lista para construir
**Implementa:** apuesta "Degustación de Premium" de `docs/product/roadmap.md` (en el roadmap es la #4; el usuario la aprobó como "apuesta 5", junto con el cambio en lo que incluye Free). Insumos: `docs/business/monetization/2026-11-02-auditoria-conversion.md` P2; costos en `docs/business/metrics/2026-11-02-embudo-a-pago.md` §3.2.
**Depende de:** `2026-11-03-habito-del-sabado.md` §3.1 (`_rollout_on`, migración `20261103110000_rollout_flag_sql.sql`, mismo dueño) y de la spec `2026-11-02-sin-callejones.md` en curso (mismos archivos de flutter-dev y de assistant-dev: van después).

---

## 1. Objetivo

Hoy un Free que pregunta "¿qué opinás de NVDA?" (ticker que no tiene) ve desaparecer la respuesta y se le abre el paywall: paga por algo que nunca vio. Con el interruptor prendido:

1. Free tiene **3 consultas de mercado por mes** (mes UTC) con datos reales de tickers fuera de su cartera. Debajo de la respuesta: "Consulta de mercado gratis · te quedan 2 este mes".
2. Agotadas, **el turno no se corta**: Porty responde lo que el plan permite (concepto, relación con su cartera, sin números del ticker ajeno) y debajo aparece un aviso de Premium tocable (`source: chat_market_teaser`).

El conteo vive en el servidor (atómico, idempotente por turno). **Listo** = criterios de §5 en verde; con el interruptor apagado el chat es idéntico al de hoy.

## 2. Fuera de alcance

- Lista de seguimiento, simulaciones, metas, plan de cartera y acciones: siguen siendo Premium y siguen cortando el turno como hoy.
- Datos de Gold (fundamentals, earnings, noticias, análisis): no los abre la degustación.
- Cambiar la cuota de 20, precios o el paywall en sí.
- Widgets nuevos del catálogo, cambios al system prompt o a las reglas `[W:…]` (ver §6: no se toca la allowlist).
- Gating de datos de mercado en el servidor (Yahoo/Finnhub no filtran por plan hoy; el gating es en la app, igual que antes).
- A/B: se mide antes/después por cohorte, como el resto del mes.

---

## 3. Contrato de datos

### 3.1 Interruptor, límite por plan y tabla

`supabase/migrations/20261103130000_market_tastes.sql` (backend). Requiere `20261103110000_rollout_flag_sql.sql`.

```sql
insert into public.app_config (key, value)
values ('market_taste', '{"percent": 0, "users": []}'::jsonb)
on conflict (key) do nothing;

-- Espejo de PlanSpec.marketDataTastesPerMonth (el servidor manda).
alter table public.plan_limits
  add column if not exists market_tastes_per_month int not null default 0
    check (market_tastes_per_month >= 0);
update public.plan_limits set market_tastes_per_month = 3
 where tier = 'free' and market_tastes_per_month = 0;

-- Una fila por turno que usó una degustación. La PK hace idempotente el
-- "usar" (reintentos del mismo turno no gastan otra).
create table if not exists public.market_tastes (
  user_id uuid not null references auth.users (id) on delete cascade,
  turn_id text not null,
  month text not null check (month ~ '^\d{4}-\d{2}$'),   -- _current_usage_month()
  tickers text[] not null,
  used_at timestamptz not null default now(),
  primary key (user_id, turn_id)
);
create index if not exists market_tastes_user_month_idx
  on public.market_tastes (user_id, month);
alter table public.market_tastes enable row level security;
-- policy: select own (auth.uid() = user_id). Sin policies de escritura.
grant select on public.market_tastes to authenticated;
grant select, insert, update, delete on public.market_tastes to service_role;
```

### 3.2 RPCs (rol `authenticated`, `auth.uid()`, `security definer`)

**`market_taste_status() returns jsonb`** — al abrir el chat y después de cada turno que la usó:

```jsonc
{"enabled": true, "limit": 3, "used": 1, "remaining": 2, "month": "2026-11"}
// interruptor apagado para el usuario, o plan con límite 0 (Premium/Gold)
{"enabled": false, "limit": 0, "used": 0, "remaining": 0, "month": "2026-11"}
```

`enabled` = `_rollout_on('market_taste', uid) and limit > 0`; `limit` = `plan_limits.market_tastes_per_month` del `_effective_tier`.

**`consume_market_taste(p_turn_id text, p_tickers text[]) returns jsonb`** — antes de ejecutar la ronda que la usa:

```jsonc
{"ok": true,  "remaining": 2, "limit": 3, "reused": false}   // gastó una
{"ok": true,  "remaining": 2, "limit": 3, "reused": true}    // mismo turn_id: no gasta
{"ok": false, "reason": "exhausted",    "remaining": 0, "limit": 3}
{"ok": false, "reason": "disabled",     "remaining": 0, "limit": 0}  // flag apagado
{"ok": false, "reason": "not_eligible", "remaining": 0, "limit": 0}  // el plan ya incluye mercado
{"ok": false, "reason": "invalid_turn_id" | "invalid_tickers"}
```

Reglas:
- Orden de chequeos: sesión → formato → `disabled` → `not_eligible` → idempotencia por `(uid, p_turn_id)` → límite.
- Atómico: `pg_advisory_xact_lock(hashtext('market_taste:' || uid::text))` antes de contar; cuenta = filas de `(uid, _current_usage_month())`.
- `p_turn_id`: mismo formato que acepta `ai-chat` (`invalid_turn_id`; regex a verificar por el dev en `handler.ts`). `p_tickers`: 1–6, `upper`, `^[A-Z0-9.\-]{1,12}$`.
- `revoke all ... from public, anon`; `grant execute ... to authenticated`.

Borrado de cuenta: la tabla tiene FK `on delete cascade`. A verificar por el dev: si `_account_purge_before_delete` limpia `users` de `app_config` por lista de claves, sumar `market_taste`; la guardia de `account_deletion_db_test.sql` tiene que quedar verde.

### 3.3 Planes (flutter-dev)

En `lib/domain/subscription/plan_matrix.dart`:

```dart
// PlanSpec
/// Consultas de mercado (tickers que no tiene) de regalo por mes, si el plan
/// no incluye PlanFeature.marketData. Espejo de
/// plan_limits.market_tastes_per_month (el servidor manda).
final int marketDataTastesPerMonth;   // Free: 3. Premium y Gold: 0. Default 0.
```

Por capacidad: el chat pregunta `PlanMatrix.of(tier).marketDataTastesPerMonth > 0`, nunca por tier.

`PaywallSource.chatMarketTeaser = 'chat_market_teaser'` (sumarlo a `values`). Motivo del paywall: `PaywallReason.marketDataLocked` (existente).

`ProductEvent` nuevos (`once: false`):

| Evento | Cuándo | `props` |
|---|---|---|
| `market_taste_used` | turno respondido con degustación | `{"remaining": 2}` |
| `market_teaser_shown` | se muestra el aviso de Premium | `{}` |

### 3.4 Chat (assistant-dev)

**Qué es una consulta de mercado:** una ronda en la que el modelo pide `get_quote`, `get_etf_holdings` o `get_dividends` con al menos un ticker fuera de `ctx.heldTickers`, y el plan no incluye `marketData`. La degustación cubre **el turno entero** (todas sus rondas y tickers).

**`MarketTasteGrant`** (nuevo, gemelo de `WeeklyFreeAnalysisGrant`), en `beforeRound`, una sola decisión por turno:
- Si `ctx.marketDataAllowed`, o `available == false` (de `market_taste_status`), o la ronda no es de mercado → nada.
- Si no: `consume(turnId, tickersAjenos)`.
  - `ok` → `ctx.marketTaste = true`, `ctx.marketTasteRemaining = remaining`.
  - `exhausted` → `ctx.marketTasteExhausted = true`.
  - `disabled`, `not_eligible`, error de red → nada (comportamiento de hoy, el turno se corta como siempre).
- `turnId` = el mismo que viaja como `x-porty-turn-id` (`ConversationLog.currentTurn.id`; cómo llevarlo a `beforeRound` lo decide el dev).

**`AssistantToolContext`**: suma `bool marketTaste`, `bool marketTasteExhausted`, `int? marketTasteRemaining` y `bool get marketDataServed => marketDataAllowed || marketTaste`. Solo `get_quote`, `get_etf_holdings` y `get_dividends` pasan a usar `marketDataServed`; las tools de watchlist (`plan_tools.dart`, `manage_tools.dart`) siguen con `marketDataAllowed`.

**No cortar:** `AssistantTurnPolicy.paywallFor` ignora `marketDataLocked` cuando `ctx.marketTasteExhausted` (las demás razones siguen cortando).

**Guía en el resultado** (no en el prompt): con `marketTasteExhausted`, los resultados `locked` de esas 3 tools llevan un `AnswerGuide` en inglés, borrador: *"The user's plan does not include market data for these tickers this month. Do not state any price, return or other number about them, and do not guess. Answer conceptually and, if relevant, relate it to the user's own portfolio. Do not mention plans or upgrades: the app shows that."*

**Mensaje** (`PortfolioQaMessage`): `final int? marketTasteRemaining;` y `final bool marketTeaser;` (con `copyWith`). Los fija el provider al cerrar el turno; nunca los escribe el modelo.
- `marketTasteRemaining != null` → línea secundaria debajo de la respuesta: `assistant_market_taste_left` (o `_last` si es 0).
- `marketTeaser` (turno con `marketTasteExhausted` y algún `locked` de mercado) → línea con link "Ver Premium" → `SubscriptionPaywallSheet.show(reason: marketDataLocked, source: PaywallSource.chatMarketTeaser)`. Una por respuesta. Registra `market_teaser_shown` al mostrarse.
- Ambas fuera del catálogo, estilo `AssistantQuietNotice` (como la línea de cuota de sin-callejones). Si en el mismo turno corresponde la línea de cuota, va primero la de mercado.

**Cuota:** un turno respondido cobra 1 consulta, con o sin degustación (el servidor cobra por `turn_id` al llegar la respuesta final). Después del tope, el turno de mercado que antes se cortaba gratis ahora se responde y cobra (ver §6). A verificar por el dev: que `AssistantTurnPolicy.quotaWeight` no se use para descontar del lado del cliente en este caso.

**Claves de traducción** (las agrega flutter-dev, `es-ES.json` y `en-US.json`):

| Clave | es-ES | en-US |
|---|---|---|
| `assistant_market_taste_left` **[G][C]** | Consulta de mercado gratis · te quedan {remaining} este mes | Free market lookup · {remaining} left this month |
| `assistant_market_taste_last` **[G][C]** | Consulta de mercado gratis · era la última de este mes | Free market lookup · that was the last one this month |
| `assistant_market_teaser` **[G][C]** | Con Premium ves precios, gráficos y comparaciones de cualquier ticker. Tus {count} consultas gratis de este mes ya se usaron. | Premium shows prices, charts and comparisons for any ticker. Your {count} free lookups this month are used up. |
| `assistant_market_teaser_cta` | Ver Premium | See Premium |

`{count}` = `PlanMatrix.of(tier).marketDataTastesPerMonth`. Ningún número escrito en el texto.

---

## 4. Tareas por dueño

### porty-backend-dev (primero)

| Archivo | Qué |
|---|---|
| `supabase/migrations/20261103110000_rollout_flag_sql.sql` | Si no existe ya por la otra spec (§3.1 de hábito del sábado) |
| `supabase/migrations/20261103130000_market_tastes.sql` (nuevo) | §3.1 y §3.2 |
| `supabase/tests/market_tastes_db_test.sql` (nuevo) | §5 1–6 |

### porty-flutter-dev (después de su trabajo de sin-callejones en estos archivos)

**Primero, "piezas" para assistant-dev** (commit chico, avisa): `PlanSpec.marketDataTastesPerMonth`, `PaywallSource.chatMarketTeaser`, los 2 `ProductEvent`, las 4 claves.

| Archivo | Qué |
|---|---|
| `lib/domain/subscription/plan_matrix.dart` | §3.3 |
| `lib/features/subscription/config/paywall_source.dart` | `chatMarketTeaser` |
| `lib/features/product_events/data/product_events.dart` | 2 eventos |
| `assets/translations/es-ES.json`, `assets/translations/en-US.json` | 4 claves |
| `test/domain/subscription/plan_matrix_test.dart` | Free 3, Premium/Gold 0 |

### porty-assistant-dev (después de las "piezas" y de su tarea 3c de sin-callejones; arranca contra un fake del repositorio)

| Archivo | Qué |
|---|---|
| `lib/features/assistant/data/market_taste/market_taste_repository.dart` (nuevo) | `status()` y `consume(turnId, tickers)` contra las RPCs; nunca tira (error → `disabled`); provider al final |
| `lib/features/assistant/tools/market_taste_grant.dart` (nuevo) | §3.4 |
| `lib/features/assistant/tools/assistant_tool_context.dart` | Campos y `marketDataServed` |
| `lib/features/assistant/tools/market_tools.dart` | 3 tools con `marketDataServed`; guía en `locked` |
| `lib/features/assistant/tools/assistant_toolset.dart` | `paywallFor` no corta con `marketTasteExhausted` |
| `lib/features/assistant/models/portfolio_qa_message.dart` | 2 campos |
| `lib/features/assistant/providers/assistant_provider.dart` | Status al abrir, grant en `beforeRound`, marcar el mensaje, `market_taste_used`, refrescar status |
| `lib/features/assistant/view/widgets/assistant_market_taste_notice.dart` (nuevo) | Las dos líneas |
| `lib/features/assistant/view/assistant_screen.dart` | Renderizarlas; abrir el paywall |
| `lib/features/genui_core/...` (solo si hace falta exponer el turn id a `beforeRound`) | Sin lógica de negocio |
| `test/features/assistant/...` (grant, policy, tools, provider, widget) | §5 7–14 |

A verificar por el dev: que las cards de precio/gráfico de un ticker ajeno no se autobloqueen por `QaPlanScope` en un turno con degustación (hoy solo las de análisis miran el plan).

### Orden

`backend` ∥ `flutter: piezas` → `assistant` (contra fake; integra cuando backend avise). Todo después de sin-callejones en los archivos compartidos.

---

## 5. Criterios de aceptación

`psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/market_tastes_db_test.sql` imprime `MARKET_TASTES_DB_TEST_OK`; `flutter test test/domain/subscription test/features/assistant test/features/genui_core test/security`; `flutter analyze` sin warnings nuevos.

**Backend**
1. Flag apagado: `status` → `enabled: false`; `consume` → `disabled` y no inserta.
2. Free en `users`: 3 `consume` con turnos distintos → `remaining` 2, 1, 0; el 4.º → `exhausted`. Repetir un `turn_id` usado → `ok, reused: true`, sin fila nueva.
3. Premium/Gold → `not_eligible`. Gold vencido (`status` no activo) cuenta como Free.
4. Mes nuevo (fila con `month` anterior) no cuenta.
5. Turn id o tickers inválidos → `invalid_*`. Sin sesión → excepción. Un usuario no ve filas de otro (RLS).
6. `supabase db reset` aplica la migración dos veces sin error; `plan_limits.market_tastes_per_month` = 3 / 0 / 0.

**Chat**
7. Grant: ronda con `get_quote(['NVDA'])`, Free sin NVDA, `available: true` → llama `consume` una vez por turno; con `ok`, `get_quote` devuelve datos (`status: ok`). Ronda con solo tickers propios → no llama.
8. Con `exhausted`: `paywallFor` devuelve `null` aunque toda la primera ronda sea `locked`; el resultado `locked` trae la guía. Con `simulations`/`goals`/`modeLocked` sigue cortando.
9. Con `disabled`, error de red o flag apagado: el turno se corta con `chat_turn_locked_market_data`, como hoy (test de regresión).
10. La degustación no abre `get_watchlist`, `propose_watch` ni fuentes de Gold.
11. Mensaje del turno con degustación: `marketTasteRemaining = 2` y la línea "Consulta de mercado gratis · te quedan 2 este mes"; con 0, "era la última". Se registra `market_taste_used{remaining}`.
12. Turno después del tope: respuesta visible + aviso; "Ver Premium" abre el paywall `marketDataLocked` con `chat_market_teaser` y se registra `paywall_viewed{source: chat_market_teaser}` y `market_teaser_shown`.
13. Premium/Gold: nunca se llama a la RPC ni aparecen las líneas.
14. `flutter test test/security/system_prompt_allowlist_test.dart` verde **sin** `UPDATE_PROMPT_ALLOWLIST`.

**Humo** (porty-qa-engineer, cuenta Free en `users`): 4 preguntas de tickers ajenos en el mismo mes → 3 con datos y contador, la 4.ª con respuesta conceptual sin números del ticker + aviso; filas en `market_tastes` y `product_events`. Capturas de las dos líneas para porty-ui-reviewer (claro y oscuro).

**Eval opcional** (cuesta plata, solo con OK del usuario): 2–3 casos de `test/evals/assistant_tool_evals_test.dart` con mercado agotado, para verificar que el modelo no inventa precios con la guía (≈ US$0,05; corrida completa US$0,15–0,30).

---

## 6. Riesgos y decisiones

**Decisiones**
- **Contador en el servidor, por turno** (`market_tastes`, PK `(user_id, turn_id)`, lock por usuario): reinstalar no lo reinicia, dos turnos en paralelo no gastan de más y un reintento no gasta dos veces. Es el patrón de `weekly_free_analysis`.
- **El interruptor lo evalúa el servidor** (`_rollout_on`), no la app: `disabled` vuelve al corte de hoy. Un cliente modificado igual podría mostrar datos de mercado (el gating de mercado siempre fue de la app); lo que no puede es inflar el contador.
- **Una degustación = un turno**, no un ticker ni una tool: "consulta" significa lo mismo que en la cuota.
- **Avisos fuera del catálogo** (estilo `AssistantQuietNotice`), no un `QaPremiumTeaser` en el catálogo como proponía P2: un widget nuevo del catálogo cambia el hash del prompt y obliga a desplegar `ai-chat`. Descartado por costo operativo; se puede migrar en diciembre si el aviso necesita un preview de card.
- **La guía para responder sin datos viaja en el resultado de la tool** (`AnswerGuide`), no en el system prompt.
- **Un turno respondido cobra 1 consulta** también después del tope. Antes, el corte no cobraba. Es la regla general (se cobra lo que se responde) y evita tocar `ai-chat`. Guardarraíl: retención Free D30 y uso de cuota Free (`ai_usage_monthly`).
- Se descartó contar en SharedPreferences (se reinicia al reinstalar) y gatear Yahoo/Finnhub en el servidor (L, otro proyecto).

**Costo de IA estimado por Free por mes** (turnos de `embudo-a-pago.md` §3.2, todos **[supuesto]** hasta Q4):
- 3 degustaciones × US$0,0063 (típico) a US$0,0127 (alto, varias tickers/rondas) = **US$0,019–0,038** para quien las usa todas. Las RPC son despreciables.
- Turnos después del tope: ahora se responden, pero caben dentro de las 20 consultas. **El peor caso mensual de Free no cambia: ≤ US$0,26** (20 × US$0,0127).
- Las búsquedas web no se abren (son Gold). Con ~50–95 Free cubiertos por un Premium, el margen no se mueve.

**Riesgos**
- El modelo podría escribir precios de memoria después del tope: lo frena la guía, y el grounding de `_perTicker` (a verificar por el dev que cubra tickers `locked`). Eval opcional en §5.
- Algún Free se conforma con 3 por mes: por eso el número es chico y reversible (`plan_limits` + interruptor).
- Cobrar el turno después del tope puede sentirse como un recorte de la cuota; si sube `quota_zero` o cae D30 en Free, se apaga.

**Textos para porty-compliance:** las 3 claves **[C]** de §3.4 y el borrador de la guía (que la respuesta sin datos no suene a recomendación).

**Toca el prompt o el catálogo del chat:** **no**. Cambian tools (resultados y guía), el loop y avisos fuera del catálogo; el hash del system prompt no cambia. No hay que regenerar la allowlist ni desplegar `ai-chat`.

**Necesita OK del usuario**
1. `db push` de `20261103110000_rollout_flag_sql.sql` (si no se subió con la otra spec) y `20261103130000_market_tastes.sql`.
2. Publicar la versión de la app.
3. Prender `market_taste` en producción (`update public.app_config set value = '{"percent": 100, "users": []}'::jsonb, updated_at = now() where key = 'market_taste';`), en un día conocido.
4. Eval opcional (≈ US$0,05).
5. Que un turno respondido después del tope cobre 1 consulta (decisión de §6).
