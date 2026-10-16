# Un prompt que no crezca con cada funcionalidad

**Fecha:** 2026-10-16 · **Estado:** piloto implementado (plan de cartera y lista de seguimiento); falta correr los evals contra el modelo real.

## El problema

Cada funcionalidad nueva sumaba reglas al system prompt de Porty, y el test `the system prompt stays small` subía su tope: 110.000 → 112.000 → 114.000 → 115.000 caracteres en una semana. Eso no escala:

- **Calidad:** más reglas compitiendo, más chance de que el modelo ignore alguna.
- **Mantenimiento:** cada cambio toca un archivo central, cambia el hash del allowlist y obliga a desplegar `ai-chat` antes que la app.
- **Costo y latencia:** acotados gracias a la caché (ver abajo), pero cada pedido que no pega en caché paga todo.

## Qué hay en cada pedido (medido, tokenizador o200k)

Estado del 2026-10-16 (commit `4c9bdc5`):

| Parte | Tokens | % |
|---|---|---|
| Esquemas JSON de la UI (catálogo, tipos comunes y mensajes A2UI) | 15.169 | 47 % |
| Reglas de Porty (`assistant_prompt_rules.dart`) | 9.901 | 30 % |
| Definiciones de las 24 tools | 6.339 | 19 % |
| Texto fijo de genui y reglas de formato | 1.179 | 4 % |
| **Total fijo por pedido** | **32.604** | |

- **Los esquemas son lo más grande, no las reglas.** Y casi la mitad es indentación: minificados bajan de 15.169 a ~9.500 tokens sin cambiar contenido.
- **El widget más pesado** es `QaEarningsCalendar` (759 tokens), seguido de `QaCompanyAnalysis` (601), `QaPriceChart` (541) y `QaFundamentals` (533).
- **La tool más pesada** es `get_goal_projection` (823 tokens), seguida de `get_invest_candidates` (589).
- **Costo:** con la caché el ~99 % del prompt sale cacheado (`2026-10-15-porty-latencia.md`). Con los precios de `model_prices` (gpt-6-luna US$ 0,20 / 0,02 por millón), son ~US$ 0,0007 por ronda cacheada y ~US$ 0,0065 sin caché.
- **El estudio de latencia hablaba de ~13.000 tokens:** el prompt se duplicó desde entonces.

## Opciones evaluadas

| Opción | Veredicto | Por qué |
|---|---|---|
| Tope global en caracteres (lo de hoy) | ❌ | No dice qué creció ni obliga a nada: se sube y listo |
| **Presupuesto en tokens por bloque** (reglas, esquemas, tools) | ✅ hacer | Cada funcionalidad entra en su presupuesto o paga sacando otra cosa |
| **Minificar esquemas y sacar lo que no se usa** (`updateDataModel`, `deleteSurface`) | ✅ hacer | −5.700 tokens (−22 %), cero cambio semántico; validar con evals |
| **Instrucciones en el resultado de la tool** (`answer_guide`) | ✅ piloto | El "router" es la elección de tools que el modelo ya hace en la ronda 1: sin llamadas extra, las preguntas mixtas traen todas sus guías, y el prompt fijo no crece |
| **Widgets que toman los datos de la evidencia** (latencia, punto A.1) | ✅ hacer | Achica los esquemas (lo más grande) y los tokens de salida (lo que más pesa en la latencia); además evita números mal copiados |
| Poda de reglas por ablación (sacar, correr evals, decidir) | ✅ proceso | Los bloques de causas ("WHY") y de estilo son los primeros candidatos |
| Router previo que elige un prompt especializado | ❌ para el chat | Una llamada más (~1 s), se equivoca con preguntas mixtas y con seguimientos ("¿y la otra?"), y un ruteo equivocado deja al modelo sin las reglas que necesitaba. No rompe la caché (la parte general sigue cacheada), pero la fragmenta |
| Subagentes especializados | ❌ para el chat, ✅ donde ya están | Llamadas en serie, más costo, y la respuesta igual la escribe uno solo. Sí sirven en tareas largas y separables: informe semanal, `news-context`, importador |
| Módulo por modo (la app sabe en qué flujo está y manda el módulo mientras dure) | ⏳ otro piloto | Tiene sentido en flujos de varios turnos. El plan y la lista no tienen uno; el candidato natural es armar una meta |

## El piloto: `answer_guide` con el plan y la lista

- **Mecanismo:** `lib/features/assistant/tools/answer_guide.dart`. El resultado de la tool lleva `answer_guide`, que dice cómo responder con ESOS datos (formato, tono, qué no decir).
- **Qué se queda en el prompt:**
  - una regla general: *"answer_guide in a result says how to answer with THAT data; follow it. These rules win if they conflict"*;
  - los intents `[W:PLAN]` y `[W:WATCHLIST]` (cuándo llamar a la tool, que se decide antes de ver el resultado);
  - lo general: grounding y estados `locked`/`failed`.
- **Qué se mueve:** la sección "PORTFOLIO PLAN AND WATCHLIST" del prompt y las instrucciones de respuesta de las descripciones de las tools pasan a `PlanGuides` (`plan_tools.dart`). Cada resultado útil trae su guía; `locked` y `failed` no, porque los resuelve el prompt.

### Resultado medido (sin el modelo)

| | Antes | Después |
|---|---|---|
| System prompt | 26.265 tokens | 26.198 (−67) |
| Definiciones de tools | 6.339 | 6.257 (−82) |
| **Fijo por pedido** | **32.604** | **32.455 (−149)** |
| Guías, solo cuando se usa la tool | — | 12-87 tokens por resultado |

- **El ahorro de hoy es chico,** porque esa sección ya se había recortado de ~260 a ~90 tokens.
- **Lo que importa es el costo marginal:** con este patrón, una funcionalidad nueva suma ~0 tokens al prefijo fijo (solo su intent, si hace falta), no requiere desplegar `ai-chat` por cada cambio de redacción y no compite con el resto de las reglas.

### Cómo compararlo con el modelo real

Los casos nuevos `plan-drift`, `plan-contribution`, `plan-free-locked`, `watchlist-list`, `watchlist-add` y `watchlist-add-held` (en `test/evals/assistant_tool_evals_test.dart`) están en un commit propio, **antes** del cambio. Así se corren los mismos casos en los dos estados:

```bash
# Antes (reglas en el prompt)
git checkout 57942bc
RUN_ASSISTANT_EVALS=1 EVAL_PROXY_JWT=<jwt> flutter test test/evals/assistant_tool_evals_test.dart

# Después (answer_guide)
git checkout claude/porty-next-level
RUN_ASSISTANT_EVALS=1 EVAL_PROXY_JWT=<jwt> flutter test test/evals/assistant_tool_evals_test.dart
```

Cada estado necesita su prompt en el allowlist del proxy local: los dos hashes ya están en `allowed_system_prompts.json`.

**Criterio para adoptarlo:**
- los casos nuevos pasan igual o mejor;
- el resto de la batería no empeora;
- los tokens de salida por turno (`ai_turn_usage.completion_tokens`) no suben;
- correrlo 2-3 veces, porque los evals no son determinísticos.

## Próximos pasos, en orden

1. **Correr el piloto** con el criterio de arriba.
2. **Presupuesto en tokens por bloque:** reemplazar el tope en caracteres por uno en tokens para reglas, esquemas y tools por separado.
3. **Minificar los esquemas** en `systemPromptFor` y sacar los mensajes A2UI que la app no permite. Correr los evals.
4. **Si el piloto sale bien,** pasar las reglas de respuesta de las secciones más acotadas a `answer_guide`: alertas, posiciones cerradas, acciones, metas. Las de elección de widget y grounding se quedan en el prompt.
5. **Widgets desde la evidencia,** empezando por los de esquema más grande (`QaEarningsCalendar`, `QaCompanyAnalysis`, `QaPriceChart`, `QaFundamentals`), junto con el plan de latencia.
6. **Ablación** de los bloques de reglas más grandes.

## Cómo se midió

- El prompt se generó con `AssistantOpenAiService.systemPromptFor(AssistantCatalog.build())`.
- Las tools salieron de `AssistantToolset.build` (plan Gold, datos falsos), en el formato `tools` de Chat Completions.
- Se contó con `gpt-tokenizer` (o200k_base, el de la familia GPT-4o/5). gpt-6-luna puede tokenizar un poco distinto: las proporciones valen, los absolutos son aproximados.
