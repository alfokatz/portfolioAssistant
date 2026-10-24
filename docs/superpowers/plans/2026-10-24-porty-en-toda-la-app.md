# Porty en toda la app (fase 1 de "asistente integral")

**Fecha:** 2026-10-24 · **Estado:** fases 1, 2 y 3 implementadas y probadas en local; nada desplegado · **Rama:** `claude/porty-next-level`

## Por qué

Porty era un lugar (la pestaña del chat), no una presencia: se entraba con `GotoAssistant(initialQuestion)` desde unas pocas pantallas y el modelo no sabía qué estaba mirando el usuario. "¿Por qué bajó?" en el detalle de NVDA obligaba a escribir "¿por qué bajó NVDA?".

## Fases del plan grande

| Fase | Qué | Estado |
|---|---|---|
| 1 | Porty en cada pantalla, con `screen_context` y preguntas de la pantalla | ✅ esta |
| 2 | Bandeja de Porty en la Home y resumen de la mañana | ✅ |
| 3 | Áreas con presupuesto y prompt lean (que el prompt no crezca con cada feature) | ✅ (lean apagado hasta medirlo) |
| 4 | Conversaciones guardadas y memoria episódica | pendiente |
| 5 | Patrimonio neto, flujo mensual e impuestos | pendiente |
| 6 | Automatizaciones y flujos guiados | pendiente |

## Fase 1: qué hace

### Contexto de pantalla (`screen_context`)

- `PortyScreenContext` (`lib/features/assistant/models/porty_screen_context.dart`): la pantalla (`PortyScreen`) y, si aplica, el ticker o la meta.
- Viaja con la pregunta: `GotoAssistant(screen:)` → `AssistantQuestionRequest.screen` → `AssistantProvider.askFromOutside(question, screen:)`.
- En el brief del turno va como `screen_context: {screen, ticker?, goal?, turns_ago}`. Vale para la pregunta que lo trajo (`turns_ago: 0`) y los dos turnos siguientes; después se descarta. Una pregunta de afuera sin pantalla (Home, una notificación) lo borra.
- Una pregunta que llega mientras corre un turno guarda su pantalla con ella (`_OutsideQuestion`): el turno en curso no se la lleva.
- Las instrucciones de cómo usarlo (`AssistantOpenAiService.screenContextGuidance`) van en el contexto fijo del turno, solo cuando hay `screen_context`: **no cambian el system prompt ni su hash**, no hace falta desplegar `ai-chat`.

### Hoja "Preguntale a Porty"

- `PortyAskSheet` + `PortyAskButton` (`lib/features/assistant/view/widgets/porty_ask_sheet.dart`): la chispa de Porty en la barra de arriba abre una hoja con Porty ("¿Qué querés saber de NVDA?"), hasta 3 preguntas de la pantalla y el campo del chat. Elegir o escribir abre el chat con la pregunta y su pantalla.
- Reusa `PortySays`, `AssistantStarterSuggestions`, `AssistantComposerField` y `AssistantSendButton`: mismo lenguaje visual que el chat.
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
- `test/features/assistant/view/porty_ask_sheet_test.dart`: render en claro y oscuro a ancho de SE, elegir, escribir y cerrar sin elegir.
- `test/screenshots/porty_ask_sheet_screenshots_test.dart` (con `RUN_SCREENSHOTS=1`).

## Fuera de esta fase

- **Responder dentro de la hoja**, sin ir a la pestaña del chat: hoy la pregunta abre el chat. Requiere que la conversación se pueda mostrar en dos lugares (la pantalla del chat es de ~1.400 líneas); conviene hacerlo junto con la fase 4 (conversaciones guardadas).
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

## Despliegue (pendiente, en este orden)

1. `supabase db push`: migración `20261024000000_morning_brief.sql`. **Antes que la app**, porque la app nueva guarda `morning_brief` en `notification_preferences`.
2. `supabase functions deploy daily-jobs notify-dispatch`.
3. Publicar la app. El prompt clásico no cambia.
4. Fase 3: la migración `20261024000100_porty_lean_prompt.sql` va con el `db push` del paso 1. Antes de prender el flag, `supabase functions deploy ai-chat` (allowlist con el hash lean) y medir con evals (ver la investigación).
