# Asistente unificado — diseño v3

**Fecha:** 2026-06-09  
**Estado:** aprobado para planificación  
**Reemplaza:** flujos GenUI separados (`analysis`, `investment`, `planning`) y evoluciona `portfolio_qa` v2

## Resumen

Un **solo chat** (`/assistant`) con **modos** (chips) que cambian catálogo, contexto y reglas del LLM. La Home tiene **una card principal** más **atajos** que abren el asistente en un modo concreto. Los tres flujos GenUI actuales se **eliminan y reconstruyen desde cero** dentro del asistente.

Decisiones acordadas:
- **Arquitectura B+C:** chat unificado + modos visibles + routing de intención entre modos.
- **Home B:** card principal + atajos a modos (no tres pantallas distintas).

---

## Objetivo de producto

Que el usuario pueda, desde un mismo lugar:
1. Consultar **su** portfolio (abierto y cerrado) con datos reales.
2. **Aprender** conceptos de inversión sin necesitar posiciones.
3. **Explorar** cualquier ticker (precio, variación, comparación, encaje con cartera).
4. Recibir **orientación para invertir** (educativa, sin órdenes reales).
5. **Planificar** metas financieras con proyecciones simples.

El asistente **no** es asesor financiero: sin órdenes de compra/venta, sin recomendaciones como verdad absoluta, sin inventar datos.

### Requisitos fundamentales (no negociables)

1. **Anti-alucinación:** todo número, precio, P&L y causa de mercado proviene del snapshot inyectado por la app (Yahoo, portfolio, calculadoras Dart). El LLM explica y compone UI, no inventa datos.
2. **Minimizar errores GenUI:** JSON válido, dispatch síncrono, espera de surface con `root`, widgets guarded, smoke tests por modo, validación pre-envío si faltan datos, fallback graceful ante timeout.

Ver plan de implementación: [`docs/superpowers/plans/2026-06-09-unified-assistant.md`](../plans/2026-06-09-unified-assistant.md) — **Pilar 0**.

---

## Qué se elimina

| Eliminar | Motivo |
|----------|--------|
| `lib/features/analysis/` | Reemplazado por modo Explorar (+ noticias en Fase 4) |
| `lib/features/investment/` | Reemplazado por modo Invertir |
| `lib/features/planning/` | Reemplazado por modo Planificar |
| Rutas `/genui/analysis`, `/genui/invest`, `/genui/plan` | Una sola ruta `/assistant` |
| `GenUiFlowType`, `genui_router`, `genui_nav` | Sustituidos por `AssistantMode` + `assistant_router` |
| `AiInsightsSection` con 3 cards a flujos GenUI | Reemplazada por sección de atajos al asistente |

## Qué se conserva

| Conservar | Uso |
|-----------|-----|
| `lib/features/genui_core/` | OpenAI GenUI, dispatch A2UI, trackers, guards |
| Dominio + infra | Positions, closed positions, quotes Yahoo, historial |
| Widgets y lógica de `portfolio_qa` v2 | Base del modo **Mi portfolio** |
| `SavedGoal` / persistencia de metas | Reusar en modo Planificar si encaja |

---

## Arquitectura

```
lib/features/assistant/
├── models/
│   ├── assistant_mode.dart          # enum de modos
│   └── assistant_message.dart       # evolución de portfolio_qa_message
├── modes/
│   ├── portfolio/                   # snapshot, position_periods, reglas actuales
│   ├── learn/                       # educación, sin bloqueo por posiciones
│   ├── explore/                     # tickers externos, Yahoo, comparación
│   ├── invest/                      # flujo inversión reconstruido
│   └── plan/                        # flujo planificación reconstruido
├── catalog/
│   ├── assistant_catalog.dart       # composición por modo
│   ├── shared_widgets.dart          # QaAnswerText, QaTipBanner, etc.
│   └── mode-specific items
├── services/
│   └── assistant_openai_service.dart
├── routing/
│   └── intent_router.dart           # sugiere cambio de modo (no automático)
├── utils/
│   ├── portfolio_context_builder.dart   # migrado desde portfolio_qa
│   ├── explore_context_builder.dart
│   └── ...
├── nav/
│   ├── assistant_router.dart        # /assistant?mode=explore
│   └── assistant_nav.dart
└── view/
    ├── assistant_screen.dart
    └── widgets/
        ├── mode_chip_bar.dart
        ├── mode_switch_suggestion.dart
        └── ...
```

**Migración:** `portfolio_qa/` se renombra/refactoriza a `assistant/`; la ruta `/portfolio-qa` redirige a `/assistant` (o se depreca en una release).

---

## Modos del asistente

| Modo | ID | Requiere posiciones | Contexto principal |
|------|----|---------------------|-------------------|
| Mi portfolio | `portfolio` | No (abiertas o cerradas) | Snapshot actual v2 |
| Aprender | `learn` | No | Glosario + reglas educativas |
| Explorar | `explore` | No | Ticker(s) consultados vía Yahoo |
| Invertir | `invest` | No (mejor con portfolio) | Presupuesto, riesgo, sectores, cartera |
| Planificar | `plan` | No | Metas, horizonte, ahorro mensual |

### Patrón de respuesta (todos los modos)

Igual que QA v2:
1. Texto conciso (`QaAnswerText` o equivalente)
2. **Como máximo un** widget de datos
3. Tip educativo opcional (`QaTipBanner`)

### Modo: Mi portfolio

- Comportamiento actual de Portfolio Q&A v2 sin regresiones.
- Snapshot: `positions`, `closed_positions`, `period_returns`, `position_periods`.
- Reglas anti-alucinación para preguntas de causa (Fase 1 implementada).

### Modo: Aprender

- Sin bloqueo si no hay posiciones.
- Solo texto + tip; sin widgets de datos salvo que aporte claridad (ej. ejemplo numérico genérico).
- Temas: diversificación, P/E, volatilidad, cost basis, P&L realizado vs no realizado, etc.
- Si el usuario menciona un ticker concreto, sugerir modo **Explorar**.

### Modo: Explorar

- Usuario pregunta por ticker(s) que **no** necesita tener en cartera.
- App fetchea vía `QuoteRepository`: precio actual, velas para períodos, sector si disponible.
- Snapshot `explore_context`: tickers pedidos + métricas + opcional `portfolio_fit` (concentración sectorial si hay cartera).
- Widgets nuevos (propuesta):
  - `QaTickerSnapshot` — precio, variación día/semana/mes
  - `QaComparisonRow` — comparar dos tickers
  - Reusar `QaTickerMove` para movimiento en período
- **Fase 4:** noticias verificadas (web search del viejo análisis) solo con fuentes citadas.

### Modo: Invertir (reconstruido)

Flujo conversacional en el chat, no pantalla wizard separada:

1. Detectar o pedir **presupuesto** si falta.
2. Perfil de riesgo (slider o pregunta) si no definido.
3. Mostrar **2–4 opciones** con widgets simples (evolución de `InvestmentOpportunityCard` simplificado).
4. `AlertBanner` / `QaTipBanner` si concentración sectorial > 40%.
5. Cierre con confirmación **educativa** (sin ejecutar trade).

Widgets a diseñar (simples, estilo QA):
- `QaInvestOption` — ticker, tesis breve, fit score, pro/con
- `QaBudgetSplit` — reparto sugerido del presupuesto
- `QaInvestConfirm` — resumen + disclaimer

### Modo: Planificar (reconstruido)

1. Meta (ej. jubilación, fondo de emergencia) + monto objetivo + horizonte.
2. Proyección simple (ahorro mensual sugerido o tiempo estimado).
3. Milestones opcionales.
4. Guardar meta (`SavedGoal`).

Widgets propuestos:
- `QaGoalCard` — meta, monto, fecha
- `QaProjectionStrip` — ahorro mensual / tiempo estimado
- `QaMilestoneList` — hitos

---

## Routing de intención (B)

`IntentRouter` analiza el mensaje del usuario **en el modo actual** y puede devolver una sugerencia de cambio de modo. **Nunca** cambia de modo sin acción explícita del usuario.

| Mensaje (ejemplo) | Modo actual | Sugerencia |
|-------------------|-------------|------------|
| "Quiero invertir $500 en tech" | portfolio | → Invertir |
| "¿Qué es el P/E?" | portfolio | → Aprender |
| "¿Cómo está NVDA?" | portfolio | → Explorar |
| "¿Cómo va mi cartera?" | explore | → Mi portfolio |
| "Armame un plan para jubilarme" | learn | → Planificar |

UI: banner/chip debajo del mensaje del usuario: *"Esta pregunta encaja mejor en Explorar"* + botón **Cambiar modo**.

---

## Home — entrada B

### Card principal (existente, actualizada)

- Título: *"Asistente"* / *"Preguntame"*
- Subtítulo: menciona modos (portfolio, aprender, explorar)
- Tap → `/assistant` modo por defecto `portfolio` (o último usado)

### Atajos (reemplazan `AiInsightsSection`)

Tres cards compactas debajo de la principal (o en la misma sección):

| Atajo | Modo | Ejemplo copy ES |
|-------|------|-----------------|
| Explorar acciones | `explore` | "Consultá cualquier ticker" |
| Ayudame a invertir | `invest` | "Orientación con tu presupuesto" |
| Planificar mi futuro | `plan` | "Metas y proyecciones" |

Los atajos **no** abren otra pantalla: abren `/assistant` con `initialMode` en query/extra.

Modo **Aprender** se descubre por chip dentro del chat (no atajo obligatorio en Home).

---

## Navegación

```
/assistant
/assistant?mode=explore
/assistant?mode=invest&initialQuestion=...
```

`AssistantScreen` parámetros:
- `initialMode` (default: `portfolio`)
- `initialQuestion` (opcional)

Redirect: `/portfolio-qa` → `/assistant` (compatibilidad).

---

## Servicio OpenAI

Un `AssistantOpenAiService` que:
- Recibe `AssistantMode` por turno
- Selecciona `Catalog` compuesto (items del modo + shared)
- Inyecta system prompt del modo + reglas globales
- Usa surface dinámico: `assistant_{mode}_{turnIndex}` (evolución de `portfolio_qa_N`)

Modo Explorar Fase 4: sub-clase o estrategia con web search (como `AnalysisOpenAiService`), solo cuando hay query de noticias y con citas.

---

## Fases de implementación

### Fase 0 — Fundación (breaking)
- Crear módulo `assistant/`, migrar `portfolio_qa/`
- `AssistantMode`, chips, ruta `/assistant`, Home B
- Eliminar `analysis/`, `investment/`, `planning/`, rutas `/genui/*`
- Redirect `/portfolio-qa`
- Tests de humo del catálogo unificado

### Fase 1 — Aprender + Explorar
- Modo Aprender sin bloqueo de posiciones
- `ExploreContextBuilder` + widgets `QaTickerSnapshot`
- Atajo Home "Explorar acciones"
- Tests de context builders

### Fase 2 — Invertir
- Catálogo y reglas modo invest
- Widgets `QaInvestOption`, `QaBudgetSplit`, `QaInvestConfirm`
- Atajo Home "Ayudame a invertir"
- Integración concentración sectorial desde cartera

### Fase 3 — Planificar
- Catálogo y reglas modo plan
- Widgets meta/proyección
- Persistencia `SavedGoal`
- Atajo Home "Planificar mi futuro"

### Fase 4 — Noticias y contexto (ex-análisis)
- Web search con fuentes en Explorar
- Reglas estrictas anti-alucinación
- Solo cuando el usuario pide causa/noticias

---

## Fuera de alcance

- Ejecución real de órdenes de compra/venta
- Asesoramiento personalizado regulado
- Recomendaciones garantizadas de rentabilidad
- Mantener compatibilidad con pantallas GenUI viejas

---

## Testing

- Smoke por modo: cada widget del catálogo renderiza sin `GenUiErrorCard`
- `PortfolioContextBuilder` / `ExploreContextBuilder` unit tests
- `IntentRouter` unit tests con casos de sugerencia
- Integración: cambio de modo preserva historial de chat o reinicia según diseño (ver nota)

### Nota: historial al cambiar modo

**Recomendación:** al cambiar modo manualmente, **mantener** el historial visual pero el LLM recibe solo el turno actual + snapshot del modo nuevo (evita confusión de contexto). Documentar en implementación.

---

## Criterios de éxito

1. Usuario sin posiciones abiertas puede usar Aprender y Explorar.
2. Usuario solo con cerradas puede usar Mi portfolio.
3. Atajos de Home abren el modo correcto en una sola pantalla.
4. No existen rutas `/genui/*` en la app.
5. Preguntas de causa no inventan noticias hasta Fase 4; después solo con fuentes.

---

## Referencias

- [Portfolio Q&A v2](./2026-06-03-portfolio-qa-design.md) — base del modo Mi portfolio
- `lib/features/genui_core/` — infra compartida GenUI
