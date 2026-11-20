# Porty en toda la app (fase 1 de "asistente integral")

**Fecha:** 2026-10-24 · **Estado:** fases 1, 2, 3, 4 y 6 implementadas y probadas en local; la 5 se descartó; nada desplegado · **Rama:** `claude/porty-next-level`

## Por qué

Porty era un lugar (la pestaña del chat), no una presencia: se entraba con `GotoAssistant(initialQuestion)` desde unas pocas pantallas y el modelo no sabía qué estaba mirando el usuario. "¿Por qué bajó?" en el detalle de NVDA obligaba a escribir "¿por qué bajó NVDA?".

## Fases del plan grande

| Fase | Qué | Estado |
|---|---|---|
| 1 | Porty en cada pantalla, con `screen_context` y preguntas de la pantalla | ✅ esta |
| 2 | Bandeja de Porty en la Home y resumen de la mañana | ✅ |
| 3 | Áreas con presupuesto y prompt lean (que el prompt no crezca con cada feature) | ✅ (lean apagado hasta medirlo) |
| 4 | Memoria de conversaciones: de qué acciones hablaron, para retomarlo | ✅ |
| 5 | ~~Patrimonio neto, flujo mensual e impuestos~~ | ❌ descartada: Porty es un asistente de nicho, de inversiones |
| 6 | Recordatorio de aporte mensual y rebalanceo guiado | ✅ |

## Fase 1: qué hace

### Contexto de pantalla (`screen_context`)

- `PortyScreenContext` (`lib/features/assistant/models/porty_screen_context.dart`): la pantalla (`PortyScreen`) y, si aplica, el ticker o la meta.
- Viaja con la pregunta: `GotoAssistant(screen:)` → `AssistantQuestionRequest.screen` → `AssistantProvider.askFromOutside(question, screen:)`.
- En el brief del turno va como `screen_context: {screen, ticker?, goal?, turns_ago}`. Vale para la pregunta que lo trajo (`turns_ago: 0`) y los dos turnos siguientes; después se descarta. Una pregunta de afuera sin pantalla (Home, una notificación) lo borra.
- Una pregunta que llega mientras corre un turno guarda su pantalla con ella (`_OutsideQuestion`): el turno en curso no se la lleva.
- Las instrucciones de cómo usarlo (`AssistantOpenAiService.screenContextGuidance`) van en el contexto fijo del turno, solo cuando hay `screen_context`: **no cambian el system prompt ni su hash**, no hace falta desplegar `ai-chat`.

### El chat como hoja sobre la pantalla (actualizado el 2026-10-25)

- `PortyAskButton` (`lib/features/assistant/view/porty_chat_sheet.dart`): una píldora con Porty (con su ropa) y "Preguntale" en la barra de arriba (antes era una chispa genérica; se eligió entre 6 diseños, ver `test/screenshots/porty_icon_options_screenshots_test.dart`). Abre `PortyChatSheet`.
- **`PortyChatSheet`:** el chat de Porty (`AssistantScreen` en modo `sheet`) en una hoja al 75 % de la pantalla (92 % con el teclado abierto), encima de donde estaba el usuario. Pregunta y lee la respuesta ahí. Al bajarla, sigue en la misma pantalla.
- **Es la misma conversación que la pestaña** (`AssistantArgs.session`, que vive toda la sesión). La pregunta con la que se abre entra por `askFromOutside`. Lo que se escribe en la hoja viaja con la pantalla (`useScreenForNextQuestion`).
- Las preguntas de la pantalla van arriba del campo, en una fila que se desliza, hasta que pregunta algo.
- Mientras la hoja está abierta (`portyChatSheetOpenProvider`), la pestaña montada debajo no abre hojas propias (paywall): así no salen dos.
- Todas las entradas a Porty desde una pantalla (pastillas, "Preguntarle a Porty", la bandeja de la Home, Metas, el aporte del plan, "Seguí con Porty") abren la hoja. Las notificaciones y las preguntas de la Home que ya existían siguen abriendo la pestaña.
- Las preguntas las arma la app (`PortyScreenSuggestions`), no el modelo, y **ninguna lleva a un paywall**: el "por qué se movió" y el análisis solo con noticias / análisis de empresa (Gold); "qué hizo desde que la vendí" solo con datos de mercado (Premium).

### Dónde está

| Pantalla | Botón en la barra | Preguntas existentes con contexto |
|---|---|---|
| Detalle de posición | ✅ | pastilla de pregunta |
| Detalle de venta | ✅ | pastilla de pregunta |
| Detalle de meta | ✅ | "Preguntarle a Porty" |
| Metas | — (sin barra) | "Armar otra meta" |
| Lista de seguimiento | ✅ (con tickers) | "Preguntarle a Porty" de un ticker |
| Plan de cartera | ✅ (con plan) | aporte y "Preguntale a Porty" |
| Informe semanal | ✅ (con informe) | "Seguí con Porty" |

## Pruebas

- `test/features/assistant/providers/assistant_submit_e2e_test.dart`: el `screen_context` llega al brief, envejece y se descarta, se borra con una pregunta sin pantalla, sobrevive a la cola y al bootstrap.
- `test/features/assistant/utils/porty_screen_suggestions_test.dart`: 2–3 preguntas por pantalla y plan, gating, textos en los dos idiomas con sus placeholders.
- `test/features/assistant/view/assistant_long_answer_reveal_test.dart` → "chat as a sheet": abre al 75 %, preguntas de la pantalla arriba del campo, responde ahí con `screen_context`, al cerrarla sigue la pantalla y la conversación. Capturas con `RUN_SCREENSHOTS=1 --plain-name screenshot`.

## Fuera de esta fase

- **Comentarios de Porty con datos dentro de cada pantalla** (detalle de posición, lista, plan): la bandeja de la fase 2 los junta en la Home; repartirlos en cada pantalla queda para después.
- Evals con el modelo real para `screen_context` (cuestan plata: correrlas con OK).

## Fase 2: qué hace

### Bandeja en la Home ("Hoy te marco 3 cosas")

- **Dónde se calcula: en la app**, no en el servidor como decía la propuesta. `PortyInsightsBuilder` (`lib/features/porty_inbox/domain/`) usa lo que la app ya tiene cargado: cartera, plan, metas (`GoalProgress`) y alertas. Así los números son exactamente los que el usuario ve en cada pantalla, sin tabla nueva y sin esperar a un job.
- **Qué marca** (puro, sin modelo, sin consulta): desvío del plan (umbral del usuario), meta vencida, meta atrasada (con cuánto por mes para llegar), meta al 90 % o más, concentración (una acción desde 25 % con al menos dos posiciones), alerta de precio fijo a menos de 3 % sin saltar, pérdida desde la compra de −20 % o peor en algo que pesa 5 % o más.
- **Orden:** meta vencida (90) > desvío (80–89) > meta atrasada (70–85) > concentración (60–80) > alerta cercana (55–64) > meta casi cumplida (50) > pérdida (40–60). Hasta 3.
- **UI:** `PortyInboxSection` reemplaza al `AllocationDriftBanner` debajo del total. Porty con una frase y la cara según lo que marca (preocupado si algo pide atención, contento si todo es bueno). Cada fila abre el chat con su pregunta y su pantalla (`screen_context`). Deslizar la oculta 7 días (SharedPreferences). Sin nada para marcar, no ocupa lugar.
- **Nunca un consejo:** cada fila es un dato y una pregunta ("¿Es mucho que NVDA pese 45 % de mi cartera?"), no "vendé".

### Resumen de la mañana (push `morning_brief`)

- `daily-jobs` a las 8 locales, para quien tiene 2 o más acciones: lo que el servidor puede calcular con los mismos umbrales que la app. Concentración (`push_holding_weights`, todos los planes) y desvío del plan (`allocation_drift_inputs`, Premium/Gold con avisos del plan prendidos; los lunes no, porque lo avisa `allocation_drift` a las 10).
- **Pocas y buenas:** la clave de duplicados es `morning_brief:<YYYY-MM>:<señales>`. La misma situación avisa una vez por mes; algo nuevo avisa ese día. Automática: tope diario, horario de silencio (se difiere, vale 6 h) y preferencia propia `morning_brief` (prendida por defecto, en Ajustes → Notificaciones).
- Texto: "Porty te marca 2 cosas hoy · VOO pesa 71% (tu objetivo: 60%). Y una cosa más. Tocá para verlo." Lleva a la Home, donde está la bandeja.

### Pruebas (fase 2)

- `test/features/porty_inbox/`: cada regla, el orden, el tope, lo oculto y que vuelve a la semana; la sección (vacía, claro y oscuro a ancho de SE, deslizar para ocultar).
- `test/screenshots/porty_inbox_screenshots_test.dart` (con `RUN_SCREENSHOTS=1`).
- Deno: `tests/daily_jobs_test.ts` (señales, lunes, Free, duplicados por mes, corrida a las 8) y `tests/notify_dispatch_test.ts` (plantilla en los dos idiomas).
- SQL: `supabase/tests/morning_brief_db_test.sql`, contra Postgres 16 con stubs de auth/vault/roles y las 38 migraciones aplicadas. También pasan los 6 tests SQL que ya existían.

## Fase 3: qué hace

Detalle y evaluación (incluidos el router previo y los subagentes, descartados para el chat): `docs/superpowers/research/2026-10-24-porty-escalable.md`.

- **Registro de áreas** (`lib/features/assistant/areas/`): cada tool y widget tiene un área dueña y cada área, un presupuesto de tokens fijos. Lo controla un test.
- **Prompt lean**, apagado (`app_config.porty_lean_prompt` en 0 %). Lo que research, inversión y metas solo necesitan después de traer sus datos viaja con el resultado de la tool (`area_spec`). Son −3.325 tokens fijos por pedido (−12 %), y un área nueva suma ~200-400 tokens fijos en vez de 1.500-3.000.
- **El prompt clásico no cambió:** mismo hash, no hay que desplegar `ai-chat` por esta fase. El hash lean ya está en el allowlist para cuando se prenda.
- **Evals:** `EVAL_PROMPT_VARIANT=lean` y `EVAL_PREFIX` para comparar A/B antes de prender.

## Fase 4: qué hace

**Memoria de conversaciones, enfocada en inversiones.** Porty recuerda de qué acciones le habló el usuario, cuándo y a qué precio estaban (`porty_topics`). Lo arma la app con las tools de cada turno: sin modelo y sin costo.

- **Qué se registra** (`PortyTopicsExtractor`): solo lo que pidió el usuario. Cuenta si el ticker está escrito en la pregunta, si salió de buscar un nombre ("¿qué pasa con Amazon?"), si es el de la pantalla o si el turno miró uno o dos tickers. No cuenta lo que eligió el modelo (candidatos de una idea, los que más movieron la cartera). Hasta 3 por turno, con el precio de `get_quote` si lo trajo. La tabla guarda una fila por ticker (la última vez), hasta 50.
- **En el chat:** `recent_topics` en el brief (últimos 30 días, hasta 6), con una guía en el contexto del turno: retomar en una frase ("la última vez que me preguntaste por AMZN, el 14/10, estaba a $182"), nunca recitarlos y nunca calcular el cambio (dice los dos precios). No cambia el hash del prompt.
- **En el chat vacío:** la primera sugerencia es "¿Cómo sigue AMZN desde la última vez?" si habló de algo en los últimos 14 días y su plan lo cubre.
- **En la bandeja:** "MELI +10% desde que me preguntaste · Hace 10 días estaba a $2.000; hoy, a $2.200". Solo para lo que no tiene (lo que tiene lo cubre la cartera), desde 5%, Premium (precios de mercado) y a partir de los 2 días.
- **Privacidad:** "Lo que Porty sabe de vos" muestra "De qué acciones hablamos" y se borran de a uno. "Olvidate de todo" (pantalla o chat) también los borra.
- **Lo que no hace:** no restaura el hilo del chat al reabrir la app (las cards de genui no se guardan). La continuidad la dan los temas y la memoria; guardar el hilo completo queda para cuando haga falta.

## Fase 6: qué hace

**Automatización: recordatorio de aporte mensual (Premium).** En el paso de avisos del plan de cartera (o pidiéndolo en el chat: "recordame el 5 de cada mes aportar 500"), el usuario elige un día del 1 al 28 y, si quiere, cuánto aporta.

- **Ese día, a las 9 locales,** `daily-jobs` manda `contribution_reminder`: "Te toca aportar $500 · Para acercarte a tu plan: $300 a VOO y $200 a BND". Usa el mismo cálculo que la pantalla del plan (solo compras) y sale una vez por mes.
- **Sin `show_amounts`,** la pantalla bloqueada no muestra dólares: "60% a VOO y 40% a BND".
- **Al tocarla,** abre Porty con "Armame el aporte de $500 según mi plan".
- **Lo pidió el usuario:** no cuenta para el tope diario y se apaga en el mismo plan.
- **Chat:** `propose_allocation_plan` acepta `contribution_day` (0 lo apaga) y `contribution_amount`, con su card de confirmación como el resto. El bloque de tools pasó de 6.800 a 6.850 tokens de presupuesto; el área planning sigue dentro del suyo. No cambia el hash del prompt.

**Flujo guiado: del reparto a las compras.** Cuando `get_allocation_plan` reparte un aporte (sin monto, usa el del recordatorio), su `answer_guide` le pide a Porty ofrecer anotar esas compras cuando el usuario las haga. Si dice que sí, sale un `propose_buy` por línea, y nunca antes de que diga que compró. Si no tiene recordatorio, ofrece crearlo, pero nunca las dos preguntas juntas. Va en el resultado de la tool: no cambia el prompt.

**Lo que no entró:** la revisión mensual de cartera en segundo plano (el primer subagente nuevo que propone `docs/superpowers/research/2026-10-24-porty-escalable.md`). Es un trabajo con modelo, costo por usuario, allowlist y cuota propios, que escribe en la bandeja: conviene hacerlo como pieza aparte y Gold.

## Despliegue (pendiente, en este orden)

1. `supabase db push`: migración `20261024000000_morning_brief.sql`. **Antes que la app**, porque la app nueva guarda `morning_brief` en `notification_preferences`.
2. `supabase functions deploy daily-jobs notify-dispatch`.
3. Publicar la app. El prompt clásico no cambia.
4. Fase 4: `20261024000200_porty_topics.sql` va con el `db push` del paso 1, antes que la app.
   Fase 6: `20261024000300_contribution_reminder.sql`, también antes que la app (la app guarda `contribution_day`), y `daily-jobs` + `notify-dispatch` en el deploy del paso 2.
5. Fase 3: la migración `20261024000100_porty_lean_prompt.sql` va con el `db push` del paso 1. Antes de prender el flag, `supabase functions deploy ai-chat` (allowlist con el hash lean) y medir con evals (ver la investigación).
