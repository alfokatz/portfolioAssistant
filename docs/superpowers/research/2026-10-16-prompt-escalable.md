# Un prompt que no crezca con cada funcionalidad

**Fecha:** 2026-10-16 · **Estado:** piloto medido con el modelo real (recomendado adoptar); pasos 2-4 implementados y medidos: juntos empeoran la batería, ver "Pasos 3 y 4 con el modelo real".

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

### Resultado con el modelo real (2026-10-16)

Proxy local, gpt-6-luna, 57942bc (ANTES) vs. 744a51f (DESPUÉS).

| | ANTES | DESPUÉS |
|---|---|---|
| Casos del piloto, 3 corridas (sin `watchlist-add`, ver abajo) | 13/15 | **15/15** |
| Batería completa, 1 corrida | 57/67 | 57/67 |
| Salida por turno, casos del piloto | 209 | **156** |
| Salida por turno, toda la batería (sin turnos cortados por el tope) | ~281 | ~290 |

- **Las cuatro "regresiones" de la batería no son del piloto.** `chat-hola` y `chat-gracias` pasaron 2/2 al repetir. `portfolio-now` y `generic-es-bueno-fundamentals` también fallan en ANTES (1/3 y 2/3).
- **`watchlist-add` fallaba siempre por el chequeo:** medía el stream crudo de A2UI, no el texto. Arreglado en `c3f24cb`.
- **El 2-3 % de los turnos llega al tope de 3.000 tokens de salida** (`maxOutputTokens` del proxy), en los dos estados y en casos distintos cada vez. Esos turnos tardan ~14,5 s y se llevan el 20-25 % de toda la salida. Ver el paso 7.
- **Costo de una corrida completa:** ~US$ 0,21. Cada corrida completa necesita su propio usuario de `eval_user.ts` (100 consultas por día).

### Pasos 3 y 4 con el modelo real (2026-10-16)

Batería completa, corridas intercaladas, un usuario de eval por corrida. Base = `c3f24cb`.

| Variante | Corridas | Pasan | Entrada por caso | Salida por caso | Turnos en el tope |
|---|---|---|---|---|---|
| Base | 3 | 182/201 (90,5 %) | 89.413 | 411 | 4 |
| Solo esquemas minificados | 2 | 119/134 (88,8 %) | 73.407 | 351 | 0 |
| Solo guías nuevas | 2 | 118/134 (88,1 %) | 90.183 | 370 | 1 |
| Las dos juntas | 3 | 171/201 (85,1 %) | 75.936 | 373 | 1 |

- **Cada cambio solo queda dentro del ruido** (la base va de 86,6 % a 94 % entre corridas). **Juntos bajan ~5 puntos:** sus tres corridas quedan en el piso de la base o por debajo.
- **La minificación rompe un caso concreto:** `C-bac-estos-fundamentales` ("analizame estos fundamentales" después de mostrarlos) pasa 0/5 con esquemas minificados y 4/5 sin ellos. El modelo no llama a `get_news` y no arma `QaCompanyAnalysis`. `conceptual-etf-spy` también empeora (0/2).
- **Las guías no rompen su propio dominio:** metas, acciones y alertas no empeoran. Las fallas de esa variante son de charla (`chat-hola`, `chat-gracias`, `chat-heroe` 0/2), que no usan esas tools: probablemente ruido.
- **Lo que ahorra cada uno:** la minificación baja ~18 % la entrada y es la que importa en costo. Las guías casi no ahorran tokens (−900 fijos); su valor es que el prompt no crezca.
- **El turno cortado por el tope** escribe una respuesta A2UI completa y válida y después repite `"}` hasta los 3.000 tokens. Pasa el chequeo porque la app ignora la basura del final.

## Próximos pasos, en orden

1. ✅ **Correr el piloto** con el criterio de arriba.
2. ✅ **Presupuesto en tokens por bloque** (`test/features/assistant/catalog/prompt_budget_test.dart`): reemplazó al tope global en caracteres. Los tokens se estiman con caracteres por token medidos con o200k en cada bloque; `supabase/functions/scripts/prompt_tokens.ts` los mide de verdad.
3. ⚠️ **Esquemas minificados** en `systemPromptFor`, sin `updateDataModel` ni `deleteSurface`: de 15.147 a 9.149 tokens. Medido: rompe `C-bac-estos-fundamentales`. No adoptar tal cual.
4. ⚠️ **Acciones, alertas y metas pasaron a `answer_guide`** (`ActionGuides`, `AlertGuides`, `GoalGuides`). Medido: dentro del ruido solo, peor junto con el paso 3. Posiciones cerradas se quedó en el prompt: casi todo se responde desde PORTFOLIO_BRIEF, sin tool, y el resto es elección de widget.

   | Bloque | Al empezar | Ahora |
   |---|---|---|
   | Reglas | 9.868 | 9.126 |
   | Esquemas | 15.147 | 9.149 |
   | Texto de genui | 1.190 | 1.190 |
   | Tools | 6.271 | 6.088 |
   | **Total fijo por pedido** | **32.476** | **25.553 (−21 %)** |

5. **Widgets desde la evidencia,** empezando por los de esquema más grande (`QaEarningsCalendar`, `QaCompanyAnalysis`, `QaPriceChart`, `QaFundamentals`), junto con el plan de latencia.
6. **Ablación** de los bloques de reglas más grandes.
7. **Respuestas cortadas por el tope:** la app ya registra `finish_reason: length` (`TurnRecord.truncatedRounds`, `[GenUI/truncated]` en el log de debug) y los evals lo reportan (`truncated_rounds`). Con `EVAL_DUMP_DIR` guardan el texto crudo de esos turnos. Mirar qué escribe el modelo antes de decidir: bajar el tope rompería respuestas legítimas de hasta ~2.200 tokens (análisis de empresa).

## Cómo se midió

- El prompt se generó con `AssistantOpenAiService.systemPromptFor(AssistantCatalog.build())`.
- Las tools salieron de `AssistantToolset.build` (plan Gold, datos falsos), en el formato `tools` de Chat Completions.
- Se contó con `gpt-tokenizer` (o200k_base, el de la familia GPT-4o/5). gpt-6-luna puede tokenizar un poco distinto: las proporciones valen, los absolutos son aproximados.
