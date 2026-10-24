# Porty en toda la app (fase 1 de "asistente integral")

**Fecha:** 2026-10-24 · **Estado:** fase 1 implementada y probada en local · **Rama:** `claude/porty-next-level`

## Por qué

Porty era un lugar (la pestaña del chat), no una presencia: se entraba con `GotoAssistant(initialQuestion)` desde unas pocas pantallas y el modelo no sabía qué estaba mirando el usuario. "¿Por qué bajó?" en el detalle de NVDA obligaba a escribir "¿por qué bajó NVDA?".

## Fases del plan grande

| Fase | Qué | Estado |
|---|---|---|
| 1 | Porty en cada pantalla, con `screen_context` y preguntas de la pantalla | ✅ esta |
| 2 | Bandeja de insights calculados en el servidor y resumen diario | pendiente |
| 3 | Enrutador por áreas (que el prompt no crezca con cada feature) | pendiente |
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
- **Comentarios de Porty con datos de cada pantalla** (`PortySays` con números reales en el detalle de posición, lista y plan): van con la fase 2, que calcula esos insights en el servidor.
- Evals con el modelo real para `screen_context` (cuestan plata: correrlas con OK).
