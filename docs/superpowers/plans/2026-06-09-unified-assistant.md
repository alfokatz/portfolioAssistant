# Asistente unificado — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reemplazar los tres flujos GenUI separados por un asistente unificado (`/assistant`) con modos, Home con atajos, y **cero tolerancia a alucinación de datos** + **mínima tasa de errores GenUI**.

**Architecture:** Evolucionar `portfolio_qa/` → `assistant/` con `AssistantMode`, catálogo compuesto por modo, snapshot inyectado por turno (no confiar en memoria del LLM), routing de intención sugerido, infra `genui_core/` compartida.

**Tech Stack:** Flutter, Riverpod, GenUI SDK, OpenAI (`gpt-4.1-mini`), Yahoo quotes, Supabase.

**Spec:** [`docs/superpowers/specs/2026-06-09-unified-assistant-design.md`](../specs/2026-06-09-unified-assistant-design.md)

---

## Mapa de archivos (Fase 0)

| Acción | Ruta | Responsabilidad |
|--------|------|-----------------|
| Crear | `lib/features/assistant/models/assistant_mode.dart` | Enum de modos |
| Migrar | `lib/features/portfolio_qa/**` → `lib/features/assistant/**` | Chat, catálogo, snapshot |
| Crear | `lib/features/assistant/reliability/` | Reglas, validación, políticas |
| Crear | `lib/features/assistant/nav/assistant_router.dart` | `/assistant` + query `mode` |
| Modificar | `lib/config/navigation/app_router.dart` | Rutas assistant, redirect portfolio-qa |
| Eliminar | `lib/features/analysis/`, `investment/`, `planning/` | Flujos viejos |
| Eliminar | `lib/features/genui_core/nav/genui_router.dart`, `genui_nav.dart`, `gen_ui_flow_type.dart` | Rutas GenUI viejas |
| Modificar | `lib/presentation/flows/home/ui/widgets/assistant_shortcuts_section.dart` | Atajos Home B |
| Modificar | `lib/presentation/flows/home/providers/home_provider.dart` | `openAssistant(mode:)` |
| Crear | `test/features/assistant/reliability/` | Tests anti-alucinación y GenUI |

---

## PILAR 0 — Confiabilidad (FUNDAMENTAL, aplica a TODAS las fases)

> **No negociable.** Cada tarea de implementación debe verificar este pilar antes de cerrarse.

### 0A. Anti-alucinación (datos)

**Principio:** El LLM **nunca** es fuente de verdad para números, precios, P&L, fechas ni causas de mercado. Solo explica y formatea datos que la app inyecta en el snapshot del turno.

| Regla | Implementación |
|-------|----------------|
| Snapshot por turno | Cada mensaje incluye `ASSISTANT_SNAPSHOT` JSON generado en Dart (no por el LLM) |
| Modo aislado | Al cambiar modo, el LLM recibe **solo** el turno actual + snapshot del modo nuevo (historial visual se mantiene, contexto LLM no) |
| Campos con scope | `pnl_scope`, `data_source`, `has_sufficient_history` en JSON para que el prompt distinga conceptos |
| Causas / noticias | Prohibido inventar hasta Fase 4; Fase 4 solo con web search + `sources[]` citadas en snapshot |
| Aprender | Solo conceptos; si menciona ticker → sugerir Explorar, **sin** inventar precio |
| Explorar | Números solo de `ExploreContextBuilder` + Yahoo; si fetch falla → decirlo, no estimar |
| Invertir | Opciones limitadas a tickers con datos verificados; `fit_score` calculado en app o con fórmula documentada |
| Planificar | Proyecciones calculadas en `PlanProjectionCalculator` (Dart); LLM solo narra resultados |
| Tickers inexistentes | Si no está en snapshot → "no tengo datos verificados para X" |

**Archivo central de reglas de prompt:**

```
lib/features/assistant/reliability/grounding_prompt_rules.dart
```

Contenido mínimo (fragmento para system prompt de todos los modos):

```dart
const groundingPromptRules = '''
GROUNDING RULES — NEVER VIOLATE:
- Use ONLY numeric values present in ASSISTANT_SNAPSHOT for this turn.
- Never invent tickers, prices, percentages, dates, news, or market causes.
- If a field is missing or has_sufficient_history is false, say so plainly.
- Do not use training knowledge to fill financial figures.
- Educational explanations (Learn mode) must not include specific live prices.
- For "why did X move" without sources in snapshot: numeric move only + disclaimer.
''';
```

- [ ] **Step 1:** Crear `grounding_prompt_rules.dart` y test que verifica que cada catálogo de modo lo incluye en `systemPromptFragments`.

```dart
// test/features/assistant/reliability/grounding_prompt_rules_test.dart
test('every mode catalog includes grounding rules', () {
  for (final mode in AssistantMode.values) {
    final catalog = AssistantCatalog.buildFor(mode);
    expect(
      catalog.systemPromptFragments.join('\n'),
      contains('NEVER VIOLATE'),
    );
  }
});
```

- [ ] **Step 2:** Crear `SnapshotGroundingValidator` — valida que el snapshot no esté vacío cuando el modo lo requiere.

```dart
// lib/features/assistant/reliability/snapshot_grounding_validator.dart
enum SnapshotValidation { ok, noPortfolioData, exploreFetchFailed, partial }

abstract final class SnapshotGroundingValidator {
  static SnapshotValidation validate({
    required AssistantMode mode,
    required Map<String, dynamic> snapshot,
  }) {
    switch (mode) {
      case AssistantMode.portfolio:
        if (snapshot['has_portfolio_data'] != true) {
          return SnapshotValidation.noPortfolioData;
        }
        return SnapshotValidation.ok;
      case AssistantMode.explore:
        final tickers = snapshot['explore_tickers'] as Map?;
        if (tickers == null || tickers.isEmpty) {
          return SnapshotValidation.exploreFetchFailed;
        }
        return SnapshotValidation.ok;
      case AssistantMode.learn:
      case AssistantMode.invest:
      case AssistantMode.plan:
        return SnapshotValidation.ok;
    }
  }
}
```

- [ ] **Step 3:** En `AssistantScreen._sendMessage`, si validación falla → **no llamar al LLM**; mostrar mensaje de error local (evita que el modelo invente).

### 0B. Minimización de errores GenUI (renderizado / JSON)

**Principio:** Preferir respuesta de texto correcta antes que widget roto. Cada capa reduce fallos en cascada.

| Capa | Mecanismo existente | Acción en asistente unificado |
|------|---------------------|-------------------------------|
| JSON válido | `critical_output_rules.dart` | Incluir en **todos** los catálogos de modo |
| Dispatch síncrono | `A2uiControllerDispatch` | Reusar sin cambios |
| Espera surface | `GenUiRequestTracker` + `hasRootComponent` | Un surfaceId por turno: `assistant_{mode}_{n}` |
| Widget seguro | `guardedCatalogWidget` + `GenUiHelpers.safe*` | Obligatorio en **cada** `CatalogItem` |
| Smoke tests | `catalog_widget_smoke_test.dart` | Un grupo por modo |
| Timeout UX | 45s + mensaje claro | Mantener; añadir botón reintentar |
| Schema examples | `exampleData` en cada item | Mantener; añadir para widgets nuevos |
| Catálogo mínimo | Máx. 1 widget de datos por respuesta | Regla en prompt (ya en QA v2) |
| Fallback | Si surface falla tras retry | Mostrar `QaAnswerText` con error + tip reintentar |

**Archivo central:**

```
lib/features/assistant/reliability/genui_reliability.dart
```

- [ ] **Step 4:** Crear `GenUiSurfaceIds.assistantTurn(AssistantMode mode, int turn)` en `genui_surface_ids.dart`.

```dart
static String assistantTurn(AssistantMode mode, int turn) =>
    'assistant_${mode.name}_$turn';
```

- [ ] **Step 5:** Crear test de pipeline GenUI (ya existe patrón en repo) para un turno de cada modo con fixture JSON válido.

- [ ] **Step 6:** Documentar checklist pre-merge en el plan (sección final).

### 0C. Tests de regresión de confiabilidad (obligatorios en CI)

| Test | Qué valida |
|------|------------|
| `grounding_prompt_rules_test` | Reglas en todos los modos |
| `snapshot_grounding_validator_test` | No enviar sin datos |
| `portfolio_context_builder_test` | Snapshot portfolio correcto |
| `explore_context_builder_test` | Tickers desde Yahoo mock |
| `intent_router_test` | Sugerencias de modo |
| `catalog_widget_smoke_test` | Sin `GenUiErrorCard` por modo |
| `assistant_turn_surface_test` | SurfaceId único por turno |

---

## Fase 0 — Fundación (breaking)

### Task 1: AssistantMode y estructura base

**Files:**
- Create: `lib/features/assistant/models/assistant_mode.dart`
- Create: `lib/features/assistant/models/assistant_mode_codec.dart`

- [ ] **Step 1:** Definir enum y parse desde query string.

```dart
enum AssistantMode { portfolio, learn, explore, invest, plan }

extension AssistantModeCodec on AssistantMode {
  static AssistantMode fromQuery(String? value) => switch (value) {
    'learn' => AssistantMode.learn,
    'explore' => AssistantMode.explore,
    'invest' => AssistantMode.invest,
    'plan' => AssistantMode.plan,
    _ => AssistantMode.portfolio,
  };
  String get queryValue => name;
}
```

- [ ] **Step 2:** Test unitario de codec.

Run: `flutter test test/features/assistant/models/assistant_mode_codec_test.dart`

### Task 2: Migrar portfolio_qa → assistant

**Files:**
- Move: `lib/features/portfolio_qa/**` → `lib/features/assistant/**`
- Modify: todos los imports en el proyecto

- [ ] **Step 1:** Mover archivos manteniendo git history si es posible (`git mv`).
- [ ] **Step 2:** Renombrar `PortfolioQaScreen` → `AssistantScreen`, `PortfolioQaCatalog` → `AssistantCatalog` (portfolio mode subset).
- [ ] **Step 3:** `flutter analyze` sin errores de import.

### Task 3: Reliability module (Pilar 0)

**Files:**
- Create: `lib/features/assistant/reliability/grounding_prompt_rules.dart`
- Create: `lib/features/assistant/reliability/snapshot_grounding_validator.dart`
- Create: `test/features/assistant/reliability/`

- [ ] Implementar Steps 1–3 del Pilar 0A.
- [ ] Integrar `groundingPromptRules` en `AssistantCatalog.buildFor(mode)`.
- [ ] Integrar validador en `_sendMessage` antes de llamar OpenAI.

### Task 4: Rutas y navegación

**Files:**
- Create: `lib/features/assistant/nav/assistant_router.dart`
- Create: `lib/features/assistant/nav/assistant_nav.dart`
- Modify: `lib/config/navigation/app_router.dart`
- Delete: `genui_router.dart`, `genui_nav.dart`, `gen_ui_flow_type.dart`

- [ ] **Step 1:** Ruta `/assistant` con `GoRoute`, query `mode`, extra `initialQuestion`.

```dart
GoRoute(
  path: '/assistant',
  name: 'Assistant',
  pageBuilder: (context, state) {
    final mode = AssistantModeCodec.fromQuery(
      state.uri.queryParameters['mode'],
    );
    final question = state.extra is String ? state.extra as String : null;
    return MaterialPage(
      child: AssistantScreen(initialMode: mode, initialQuestion: question),
    );
  },
),
```

- [ ] **Step 2:** Redirect `/portfolio-qa` → `/assistant`.

- [ ] **Step 3:** `home_provider.openAssistant({AssistantMode mode, String? question})`.

### Task 5: UI modos — chips y mode switch

**Files:**
- Create: `lib/features/assistant/view/widgets/mode_chip_bar.dart`
- Create: `lib/features/assistant/view/widgets/mode_switch_suggestion.dart`
- Create: `lib/features/assistant/routing/intent_router.dart`
- Modify: `lib/features/assistant/view/assistant_screen.dart`

- [ ] **Step 1:** Barra de chips con 5 modos; tap cambia modo (confirmación si hay mensajes en vuelo).
- [ ] **Step 2:** `IntentRouter.suggestMode(message, currentMode)` — reglas keyword (testeable).
- [ ] **Step 3:** Banner de sugerencia con botón "Cambiar modo" (nunca automático).

### Task 6: Home — entrada B

**Files:**
- Create: `lib/presentation/flows/home/ui/widgets/assistant_shortcuts_section.dart`
- Modify: `lib/presentation/flows/home/ui/home_screen.dart`
- Delete: `ai_insights_section.dart` (o reemplazar contenido)
- Modify: `assets/translations/es-ES.json`, `en-EN.json`

- [ ] Card principal → `openAssistant()`.
- [ ] Tres atajos: explore, invest, plan.
- [ ] Actualizar copy de `portfolio_qa_entry_*` → `assistant_entry_*`.

### Task 7: Eliminar flujos viejos

**Files:**
- Delete: `lib/features/analysis/`, `investment/`, `planning/`
- Delete: tests/fixtures específicos si no se reusan
- Modify: `test/features/genui_core/catalog_widget_smoke_test.dart` — quitar grupos analysis/investment/planning

- [ ] `flutter analyze` + `flutter test` pasan.

### Task 8: AssistantCatalog por modo (stubs Fase 1–3)

**Files:**
- Create: `lib/features/assistant/catalog/assistant_catalog.dart`
- Modify: `lib/features/assistant/services/assistant_openai_service.dart`

- [ ] `AssistantCatalog.buildFor(AssistantMode mode)` — portfolio = catálogo actual; otros modos = shared + reglas stub hasta su fase.
- [ ] Servicio selecciona catálogo y surfaceId por modo.

---

## Fase 1 — Aprender + Explorar

### Task 9: Modo Aprender

**Files:**
- Create: `lib/features/assistant/modes/learn/learn_prompt_rules.dart`
- Modify: `assistant_catalog.dart`

- [ ] Reglas: solo educación, sin precios live, sugerir Explorar si hay ticker.
- [ ] Sin bloqueo por falta de posiciones.
- [ ] Chips de ejemplo en modo learn.

### Task 10: ExploreContextBuilder

**Files:**
- Create: `lib/features/assistant/modes/explore/explore_context_builder.dart`
- Create: `lib/features/assistant/modes/explore/ticker_extractor.dart`
- Create: `test/features/assistant/modes/explore/explore_context_builder_test.dart`

- [ ] Extraer tickers del mensaje (regex + validación formato).
- [ ] Fetch `getCurrentPrice` + `getHistoricalDaily` por ticker.
- [ ] JSON: `explore_tickers.{TICKER}.{price, periods, sector?, fetch_ok}`.
- [ ] Si `fetch_ok: false` → validador bloquea LLM o prompt de "sin datos".

```dart
// Estructura mínima del snapshot explore
{
  "mode": "explore",
  "data_source": "yahoo_finance",
  "explore_tickers": {
    "NVDA": {
      "current_price": 120.5,
      "periods": { "week": { "change_pct": -2.1, "has_sufficient_history": true } },
      "fetch_ok": true
    }
  },
  "portfolio_fit": { "has_open_positions": true, "sector_weights": { "Tech": 45.2 } }
}
```

### Task 11: Widget QaTickerSnapshot

**Files:**
- Create: widget en `assistant/catalog/shared_widgets.dart` o `explore_widgets.dart`
- Modify: `assistant_catalog.dart`
- Modify: `test/helpers/genui_test_helpers.dart`

- [ ] Schema + exampleData + smoke test.
- [ ] Regla prompt: valores solo desde `explore_tickers`.

### Task 12: Integrar Explorar en AssistantScreen

- [ ] En modo explore, armar snapshot con `ExploreContextBuilder` async.
- [ ] Atajo Home "Explorar acciones" abre `mode=explore`.

---

## Fase 2 — Invertir

### Task 13: InvestContextBuilder

**Files:**
- Create: `lib/features/assistant/modes/invest/invest_context_builder.dart`
- Create: `lib/features/assistant/modes/invest/sector_concentration_checker.dart`

- [ ] Snapshot: presupuesto (si usuario lo dio), risk profile, sector weights, candidatos con datos Yahoo.
- [ ] `fit_score` calculado en Dart (documentar fórmula en comentario + test).

### Task 14: Widgets invest

**Files:**
- Create: `QaInvestOption`, `QaBudgetSplit`, `QaInvestConfirm`

- [ ] Cada uno con guardedCatalogWidget + exampleData + smoke.
- [ ] Reglas: máx 4 opciones; siempre QaTipBanner disclaimer; sin órdenes reales.

### Task 15: Reglas modo Invertir

- [ ] Pedir presupuesto si falta (solo texto, sin widget).
- [ ] Alerta concentración >40% con `QaTipBanner` tone warning.

---

## Fase 3 — Planificar

### Task 16: PlanProjectionCalculator (Dart, no LLM)

**Files:**
- Create: `lib/features/assistant/modes/plan/plan_projection_calculator.dart`
- Migrate logic from: `lib/features/planning/models/saved_goal.dart` (mover a assistant o domain)

- [ ] Cálculo determinista: ahorro mensual, meses restantes, etc.
- [ ] Test con casos fijos — el LLM **no** calcula, solo presenta.

### Task 17: Widgets plan + persistencia SavedGoal

- [ ] `QaGoalCard`, `QaProjectionStrip`, `QaMilestoneList`
- [ ] Guardar meta en storage existente.

---

## Fase 4 — Noticias verificadas (Explorar)

### Task 18: Web search con fuentes (solo bajo demanda)

**Files:**
- Create: `lib/features/assistant/modes/explore/explore_news_enricher.dart`
- Reuse: `openai_raw_chat_client.dart`, patrón de `analysis_openai_service.dart`

- [ ] Activar solo si `NewsQueryDetector` positivo.
- [ ] Snapshot incluye `news_sources: [{title, url, snippet}]`.
- [ ] Regla prompt: **citar solo fuentes del snapshot**; si vacío → disclaimer.
- [ ] Test: sin fuentes → respuesta no debe incluir nombres de eventos inventados (golden prompt test).

---

## Checklist pre-merge (cada PR)

- [ ] `groundingPromptRules` presente en catálogo del modo tocado
- [ ] Números en widgets provienen de snapshot builders testeados
- [ ] Nuevo `CatalogItem` tiene `exampleData` + entrada en smoke test
- [ ] `guardedCatalogWidget` en todos los widgetBuilder
- [ ] `GenUiRequestTracker.sendAndWait` con surfaceId único
- [ ] `flutter test test/features/assistant/` pasa
- [ ] `flutter analyze` sin warnings nuevos
- [ ] Manual: pregunta "¿por qué cayó X?" sin Fase 4 → solo movimiento numérico

---

## Self-review (plan vs spec)

| Requisito spec | Task |
|----------------|------|
| Chat unificado + modos | Task 1, 5, 8 |
| Home B atajos | Task 6 |
| Eliminar flujos viejos | Task 7 |
| Mi portfolio sin regresión | Task 2, 8 |
| Aprender + Explorar | Task 9–12 |
| Invertir reconstruido | Task 13–15 |
| Planificar reconstruido | Task 16–17 |
| Noticias Fase 4 | Task 18 |
| Anti-alucinación fundamental | **Pilar 0A** (todas las fases) |
| Minimizar errores GenUI | **Pilar 0B** (todas las fases) |
| Intent routing manual | Task 5 |
| Redirect portfolio-qa | Task 4 |

**Gaps:** Ninguno crítico. Fase 0 debe completarse antes de 1–4.

---

## Orden de ejecución recomendado

```
Pilar 0 (Task 3) ─┐
Task 1 → Task 2 → Task 4 → Task 5 → Task 6 → Task 7 → Task 8
                    ↓
              Fase 1 (Tasks 9–12)
                    ↓
              Fase 2 (Tasks 13–15)
                    ↓
              Fase 3 (Tasks 16–17)
                    ↓
              Fase 4 (Task 18)
```
