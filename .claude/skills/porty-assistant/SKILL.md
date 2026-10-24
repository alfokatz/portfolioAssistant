---
name: porty-assistant
description: Cómo funciona y cómo extender el chat de IA de Porty (lib/features/assistant y genui_core) - tools de datos con tool calling, widgets Qa* del catálogo GenUI, reglas del prompt [W:ID], grounding, answer_guide, gating por plan free/premium/gold y el allowlist de prompts del proxy ai-chat. Usar al agregar o cambiar una tool, una card del chat, el prompt, los checks de respuesta, la cuota o los paywalls del asistente.
---

# El asistente Porty

Cada mensaje es **un turno de tool calling**: el modelo recibe la conversación + la lista fija de tools, pide datos, la app los trae aplicando el plan, y el modelo responde en **A2UI** (JSON de UI) que genui renderiza con los widgets `Qa*`.

Flujo: `AssistantProvider.submitMessage` → `services/assistant_openai_service.dart` → `genui_core/services/openai_genui_service.dart` (`runTurn`, `ConversationLog`) → checks → sanitizer/normalizer → genui.

Referencia larga: `docs/architecture/porty-assistant-tool-calling.md` (si choca con el código, manda el código).

## Mapa

| Pieza | Dónde |
|---|---|
| Loop genérico (sin negocio) | `lib/features/genui_core/` |
| Tools por grupo | `lib/features/assistant/tools/{market,portfolio,advice,action,alert,plan,memory,web}_tools.dart` |
| Orden de tools (fijo) | `tools/assistant_toolset.dart` → `AssistantToolset.build` |
| Áreas (dueño y presupuesto de cada tool y widget; qué se difiere) | `areas/porty_areas.dart` + `areas/area_specs.dart` (prompt lean, `area_spec`) |
| Contexto, gating, paywalls | `tools/assistant_tool_context.dart` (`ctx.gate`, `ctx.lockedFeature`, `ctx.allows`) |
| Instrucciones por resultado | `tools/answer_guide.dart` → `AnswerGuide.attach(result, guide)` |
| Fetchers de datos (sin LLM) | `lib/features/assistant/data/<area>/` |
| Catálogo | `catalog/assistant_catalog.dart` (lista) + `catalog/portfolio_qa_catalog.dart` (`CatalogItem`s) |
| Widgets de las cards | `catalog/widgets/*_widgets.dart` + kit `catalog/kit/` |
| Reglas del prompt | `prompts/assistant_prompt_rules.dart` (IDs `[W:…]`) |
| Grounding | `utils/assistant_grounding_check.dart` (`_requires`, `_perTicker`) |
| Revisión y evidencia | `utils/assistant_answer_review.dart`, `utils/assistant_layout_guard.dart` |
| Planes | `lib/domain/subscription/plan_matrix.dart` (`PlanFeature`, `PlanMatrix`) |

## Principios (por qué el código es así)

1. **Los números nunca los escribe el modelo.** Salen de tools o del `PORTFOLIO_BRIEF`. En cards con muchos números, la app los inyecta desde la evidencia del turno (`QaEvidenceScope`, ej. `data/plan/allocation_plan_card_data.dart`); el modelo solo escribe prosa.
2. **El modelo elige los tickers; los datos son reales.** Sin listas precargadas de tickers, sectores ni riesgo. Dato faltante → `null` / "Sin clasificar".
3. **El plan se aplica al ejecutar la tool**, no ocultando tools. La lista de tools es siempre completa e igual (prefijo cacheado).
4. **Las tools nunca lanzan.** Devuelven `status`: `ok` | `empty` | `failed` | `locked` (+ `required_plan`) | `needs_retry`, más `as_of`. `locked` nunca se redacta como "no hay datos".
5. **Lo que el prompt no garantiza, lo garantiza código** (grounding, layout guard, normalizer). Cada guarda salió de una falla medida en evals.
6. **Instrucciones específicas van en el resultado de la tool** (`answer_guide`), no en el system prompt, que debe ser determinístico (sin fechas ni datos del usuario).
7. **Crecer sin agrandar el prefijo.** Cada tool y widget es de un área con presupuesto de tokens fijos (`test/features/assistant/areas/porty_areas_test.dart`). Lo que solo hace falta después de traer los datos (reglas de respuesta, esquema de la card) se declara como `DeferredSpec`: con el prompt lean (`app_config.porty_lean_prompt`) viaja con el resultado de la tool. Sin router previo ni subagentes en el chat: ver `docs/superpowers/research/2026-10-24-porty-escalable.md`.

## Flujos

- Agregar una **tool**: [references/add-tool.md](references/add-tool.md)
- Agregar una **card** (widget del catálogo): [references/add-catalog-widget.md](references/add-catalog-widget.md)
- Diseño visual de cards (kit `QaText`/`QaColors`/`QaSpace`): skill **porty-ui-design**, `references/genui-kit.md`

## Paso obligatorio si tocaste prompt, reglas, catálogo o widgets del catálogo

El hash del system prompt cambia y el proxy rechazará la app. Regenerar:

```bash
UPDATE_PROMPT_ALLOWLIST=1 flutter test test/security/system_prompt_allowlist_test.dart
```

Agrega el hash nuevo y conserva los viejos en `supabase/functions/ai-chat/allowed_system_prompts.json`. Avisar al usuario: **hay que desplegar `ai-chat` antes de publicar la app**. No desplegar sin que lo pida.

Luego correr: `flutter test test/features/assistant test/features/genui_core test/security`.

## Planes y cuota

- Free = su propia cartera. Premium = cualquier ticker, gráficos, comparar, simulaciones, metas. Gold = + análisis de empresa, noticias, earnings, fundamentals.
- Cuota mensual 20 / 500 / 1000 (`PlanMatrix`, espejada en el servidor `_monthly_quota`). Un turno cortado por paywall o fallido no consume.
- Datos Gold bloqueados no abortan el turno: la respuesta sigue y la app agrega `QaGoldTeaser`. Máximo **un** bloque bloqueado por card (`QaGoldLock`).
- Capacidad paga nueva → `PlanFeature` en `PlanMatrix` primero, después `ctx.gate(...)` en la tool.

## Evals (cuestan plata)

`test/evals/assistant_tool_evals_test.dart` llama al modelo real. **Antes de correrlas, preguntar al usuario con el costo estimado** (corrida completa ≈ US$0,15–0,30). Detalle: skill **porty-testing**, `references/evals-and-guards.md`.
