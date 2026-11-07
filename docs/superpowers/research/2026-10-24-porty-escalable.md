# Porty escalable: áreas, prompt lean y cuándo usar subagentes

**Fecha:** 2026-10-24 · **Fase 3** de `docs/superpowers/plans/2026-10-24-porty-en-toda-la-app.md` · **Sigue a:** `2026-10-16-prompt-escalable.md`

## El problema, medido

Porty creció rápido: 31 tools y 32 widgets. Cada pedido arrastra un prefijo fijo y los cuatro bloques están al límite de su presupuesto (o200k, 2026-10-24):

| Bloque | Tokens | Presupuesto | Uso |
|---|---|---|---|
| Reglas | 9.348 | 9.400 | 99 % |
| Esquemas de UI | 9.576 | 9.600 | 99 % |
| Texto de genui | 1.179 | 1.250 | 94 % |
| Tools | 6.784 | 6.800 | 99 % |
| **Total fijo** | **26.887** | | |

La fase 5 (patrimonio, flujo mensual, impuestos) sumaría unas 6-10 tools, 4-6 cards y sus reglas: con el modelo actual, entre +3.000 y +5.000 tokens fijos en **todos** los pedidos, también en "hola". El problema no es solo el costo:

- **Calidad:** más reglas compitiendo por la atención en cada respuesta. Las evals ya mostraron que dos cambios inocuos por separado bajan ~5 puntos juntos.
- **Cantidad de tools:** pasadas ~40-50, la elección de tool empeora en todos los modelos.
- **Mantenimiento:** cada cambio de redacción cambia el hash del prompt y obliga a desplegar `ai-chat` antes que la app.

## Las dimensiones de escalar

| Dimensión | Hoy | Riesgo al crecer | Respuesta |
|---|---|---|---|
| Prefijo fijo (prompt + tools) | 26,9 K tokens, todo cacheado (~99 %) | Calidad y latencia del primer pedido | **Áreas + prompt lean** (esta fase) |
| Cantidad de tools | 31 | Elección de tool | Presupuesto por área; fusionar las `propose_*` de un área antes de pasar de ~40 |
| Salida por turno | ~290 tokens; 2-3 % llega al tope de 3.000 | Latencia | Widgets que toman los datos de la evidencia (el modelo escribe prosa, no números) |
| Evals | ~67 casos, US$0,21 por corrida | Que cada cambio cueste una corrida completa | `EVAL_PREFIX` por área + `EVAL_PROMPT_VARIANT` para A/B |
| Servidor | Proxy con allowlist por hash y cuota | Desplegar `ai-chat` por cada cambio de redacción | Reglas de área en `area_spec` y `answer_guide`: cambiarlas no cambia el hash |
| Código | Tools por grupo, reglas en un archivo central | Que nadie sepa de quién es cada cosa | Registro de áreas: cada tool y widget tiene dueño (test) |

## Opciones evaluadas

| Opción | Veredicto | Por qué |
|---|---|---|
| **Router previo con LLM** (una llamada clasifica y elige un prompt especializado) | ❌ | +~1 s por turno, se equivoca con preguntas mixtas ("¿cómo va mi meta y qué pasó con NVDA?") y con seguimientos ("¿y la otra?"), y un ruteo errado deja al modelo sin las reglas que necesitaba. Ya estaba descartado en `2026-10-16-prompt-escalable.md`; nada de lo medido desde entonces lo cambia |
| Router determinístico (palabras clave, pantalla) | ❌ | Mismos problemas, más frágil. `screen_context` ya da el contexto sin elegir por el modelo |
| **Subagentes especializados en el turno del chat** (un "analista", un "planificador de metas"…) | ❌ | Ver la sección siguiente |
| Un modelo distinto por área | ❌ por ahora | Fragmenta la caché y las evals; la diferencia de calidad entre áreas no lo justifica hoy |
| **Áreas + carga progresiva (prompt lean)** | ✅ esta fase | El router es la elección de tools que el modelo ya hace en la ronda 1: lo que un área necesita después de traer sus datos llega con el resultado. Sin llamadas extra y sin ruteos errados (una pregunta mixta llama a las tools de las dos áreas y trae las dos specs) |
| Widgets desde la evidencia | ✅ próximo paso | Achica esquemas y salida; ya validado en `QaEtfHoldings` y `QaAllocationPlan` |
| Poda de reglas por ablación | ✅ proceso | Con evals por área se vuelve barato |

## Subagentes: ¿hacen falta?

**En el turno del chat, no.** Un subagente es otra conversación con su propio prompt que hace parte del trabajo y devuelve un resultado. En el chat de Porty eso significa:

- **Latencia en serie:** el agente principal decide delegar, el subagente corre sus rondas de tools, y recién ahí el principal responde. Hoy un turno es 1-2 rondas; con un subagente son 3-4, o sea que el tiempo de respuesta más o menos se duplica. Es justo lo que el trabajo de latencia del 15/10 bajó.
- **La respuesta la escribe uno solo:** las cards, el grounding y el layout guard viven en el turno principal. El subagente solo podría devolver datos o texto, y los datos ya los traen las tools.
- **Costo y cuota:** cada subagente es otra llamada con otro prefijo (otra caché). La cuota cobra una consulta por turno y el servidor tendría que atribuir varias llamadas a un turno.
- **Las preguntas cruzan áreas:** "¿llego a la meta si NVDA sigue cayendo?" mezcla metas, mercado y cartera. Partirla entre especialistas exige coordinarlos; un solo modelo con las tools de todas las áreas ya lo resuelve.

**Fuera del turno, sí, y ya los hay.** Un subagente gana cuando la tarea es larga, separable y no bloquea al usuario:

| Subagente | Estado | Por qué encaja |
|---|---|---|
| Informe semanal (`weekly_report`) | ✅ existe | Corre el sábado, prompt y allowlist propios, evals propias |
| Contexto de noticias (`news-context`) | ✅ existe | Resume y verifica fuentes; el chat consume el resultado |
| Importador de estados de cuenta (`statement-import`) | ✅ existe | Extracción estructurada, un solo uso |
| **Revisión mensual de cartera** (fase 6) | Propuesto | Lee cartera, plan, metas y perfil; escribe hallazgos en la bandeja. Tarda lo que tarde, el usuario no espera |
| **Análisis profundo de una empresa** (Gold) | Propuesto | Hoy `QaCompanyAnalysis` sale en un turno. Un informe largo (competidores, riesgos, histórico) sería un trabajo en segundo plano que avisa al terminar |
| **Categorizador de movimientos** (fase 5) | Propuesto | Si entran extractos bancarios: clasificar cientos de líneas no es una conversación |

**Criterio para crear uno:** tarea de más de ~15 s, con entrada y salida bien definidas, que no hace falta para contestar la pregunta en curso. Necesita prompt propio en un allowlist propio (como `allowed_report_prompts.json`), cuota y evals propias, y un resultado que la app muestre sin pasar por el modelo del chat: la bandeja, una notificación o una card que lee una tabla.

**Lo que sí escala dentro del chat** cuando un flujo tiene varios turnos y estado propio (armar una meta, rebalancear) es un **modo**: la app sabe que está en ese flujo y manda su módulo mientras dure. Es el piloto que quedó pendiente en `2026-10-16-prompt-escalable.md`. Con el registro de áreas, un modo es "esta área, cargada desde el principio del turno".

## Lo implementado (fase 3)

### Registro de áreas

`lib/features/assistant/areas/porty_areas.dart`: 12 áreas (conversación, cartera, mercado, research, inversión, metas, planificación, acciones, alertas, memoria, informe, web). Cada una declara sus tools, sus widgets, su presupuesto de tokens fijos y qué difiere. `test/features/assistant/areas/porty_areas_test.dart` controla que:

- cada tool del toolset y cada widget del catálogo sea de exactamente un área (una tool nueva sin área rompe el test);
- cada área entre en su presupuesto (tools + widgets no diferidos, ~5 % de margen sobre lo medido);
- lo diferido sea del área que lo difiere.

Tokens fijos por área (lean, estimado):

| Área | Fijos | Presupuesto | Diferidos (solo al usarse) |
|---|---|---|---|
| Conversación | 812 | 850 | — |
| Cartera | 1.583 | 1.650 | — |
| Mercado | 1.339 | 1.400 | — |
| Research | 1.014 | 1.060 | 1.492 de cards + reglas |
| Inversión | 776 | 820 | 386 |
| Metas | 1.619 | 1.700 | 232 |
| Planificación | 655 | 700 | — |
| Acciones | 1.339 | 1.400 | — |
| Alertas | 447 | 470 | — |
| Memoria | 513 | 540 | — |
| Informe | 115 | 150 | — |
| Web | 257 | 280 | — |

### Prompt lean (apagado; se prende por usuario)

- **Qué difiere:** las reglas de respuesta de resultados, fundamentals, ETFs y noticias, y las cards `QaEarningsCalendar`, `QaFundamentals`, `QaCompanyAnalysis`, `QaEtfHoldings`, `QaNewsSummary`, `QaInvestOption`, `QaBudgetSplit`, `QaSavingsPlan` y `QaBuyPlan`. Se quedan en el prefijo los intents (`[W:…]`: el modelo decide qué tool llamar antes de ver el resultado) y lo que se usa sin tool (`QaGoalStatus` sale del brief; `QaInvestConfirm`, de una confirmación en un turno posterior).
- **Cómo llega:** `area_spec` en el resultado de la tool, con las reglas y el esquema de cada card tal como los describe el prompt clásico. Una vez por ventana: mientras el resultado anterior siga a la vista (3 turnos), no se repite. El gancho es genérico en `genui_core` (`ResultExtra`) y no toca la evidencia ni los chequeos.
- **Lo clásico no cambia:** su hash es el mismo y no hay que desplegar `ai-chat` por esta fase. El hash lean ya está en `allowed_system_prompts.json`.

| | Clásico | Lean |
|---|---|---|
| System prompt (o200k) | 20.097 | **16.772 (−3.325)** |
| Fijo total con tools | 26.887 | **~23.560 (−12 %)** |
| `area_spec` por tool | — | 103 (`get_monthly_buy_plan`) a 1.029 (`get_fundamentals`) |

- **Costo:** casi neutro. Lo diferido sale del prefijo cacheado (US$0,02/M) y entra sin caché la primera vez (US$0,20/M), solo cuando se usa. Con research en ~25 % de los turnos, el lean es un poco más barato, y bastante más en el primer pedido de cada conversación (sin caché).
- **Lo que de verdad cambia es la pendiente:** un área nueva diseñada así suma ~200-400 tokens fijos (sus intents y tools) en vez de 1.500-3.000.

### Cómo prenderlo

1. `supabase db push` (crea `app_config.porty_lean_prompt` en 0 %) y `supabase functions deploy ai-chat` (el allowlist con el hash lean).
2. **Medir antes de prender**, con las mismas corridas intercaladas que el 16/10:
   ```bash
   RUN_ASSISTANT_EVALS=1 EVAL_PROXY_JWT=<jwt> flutter test test/evals/assistant_tool_evals_test.dart
   RUN_ASSISTANT_EVALS=1 EVAL_PROXY_JWT=<jwt> EVAL_PROMPT_VARIANT=lean flutter test test/evals/assistant_tool_evals_test.dart
   ```
   Cada corrida necesita su usuario de eval y cuesta ~US$0,21. Hacer 3 de cada una. Para iterar solo sobre lo que difiere el lean (research, inversión y metas, ~25 casos, ~US$0,08): `EVAL_PREFIX=C-,E-,F-,P-,generic-,why-,screen-,invest-,goal-,retirement-,buy-plan-`.
3. **Criterio:** lean pasa igual o mejor en la batería completa (dentro del ruido de 86-94 %), sin caer en los casos de research (`C-bac-estos-fundamentales`, análisis, earnings, noticias), y con la salida por turno igual o menor.
4. Prenderlo por usuarios (`users`), después por porcentaje. Volver atrás es poner `percent` en 0: aplica en la próxima conversación, sin publicar la app.

## Cómo crece Porty desde acá (receta para la fase 5)

1. Un área nueva en `PortyAreas.all` (ej. `finances`) con su presupuesto **antes** de escribir código.
2. Tools en su grupo, asignadas al área. Si llega a ~6 tools, una sola `propose_finance_change` con operación (como `ManageOp`) en lugar de una por acción.
3. Intents cortos (`[W:NETWORTH]`, una o dos líneas: cuándo llamar a qué tool) en el prompt. Todo lo de "cómo responder con estos datos" va en `DeferredSpec` o en `answer_guide`.
4. Cards que toman sus números de la evidencia (props mínimos) y se declaran diferidas.
5. Casos de eval con prefijo propio (`fin-…`) para correr solo esa área con `EVAL_PREFIX` (los casos de hoy no siguen un prefijo por área: los nuevos sí).

Con esto, el prefijo fijo de la fase 5 debería crecer ~400 tokens en vez de ~4.000.

## Próximos pasos

1. **Medir y prender lean** (arriba). Hasta tenerlo medido, queda en 0 %.
2. **Diferir más con evidencia:** la parte de respuesta de `[W:INVEST]` (~600 tokens; la parte de "cómo elegir candidatos" se queda) y las cards de mercado cuando pasen a tomar los datos de la evidencia (`QaPriceChart` es el esquema más grande que queda, 357).
3. **Widgets desde la evidencia** para `QaEarningsCalendar` y `QaFundamentals` (los dos esquemas más grandes): menos tokens diferidos y menos números mal copiados.
4. **Modo "armar una meta"**: el área de metas cargada desde el turno 1 mientras dure el flujo.
5. **Revisión mensual en segundo plano** (fase 6) como primer subagente nuevo, escribiendo en la bandeja.
