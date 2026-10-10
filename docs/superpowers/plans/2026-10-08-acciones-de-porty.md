# Acciones de Porty: registrar operaciones desde el chat

**Fecha:** 2026-10-08 · **Estado:** F1–F6 hechas (2026-10-08, sin commit ni deploy); quedan 2 decisiones abiertas de F6 (ver "Resultados de F6") · **Rama de referencia:** `feature/ui_redesign`

## Resumen

El usuario le cuenta a Porty una operación ("compré 10 de Apple el lunes", "vendí todas mis TSLA") y Porty le muestra una **card de confirmación** con los datos completados y editables. **Nada se guarda hasta que el usuario toca Confirmar.** Si faltan datos (empresa, fecha, cantidad en acciones o USD), Porty los pide antes de proponer.

Decisiones tomadas con el usuario:

| Tema | Decisión |
|---|---|
| Acciones de v1 | Comprar, cerrar total o parcial, borrar una posición cargada por error |
| Varias operaciones en un mensaje | Una card por operación, cada una con su Confirmar |
| Planes | Premium y Gold. Free recibe el paywall de Premium, como el resto de lo de Premium |
| Edición | Porty completa todos los campos (precio, fecha, cantidad); el usuario puede editarlos en la card |

Fuera de v1: acciones sobre cosas que no son la cartera (ajustes, perfil, navegación). La arquitectura de abajo las admite sin cambios de fondo.

---

## Principio: el modelo propone, la app ejecuta

```
usuario ──► modelo ──► propose_buy(...)  (tool que NO escribe)
                          │ valida, resuelve ticker, trae precio
                          ▼
                      ActionProposal {id, datos}  ──► evidencia del turno
                          │
modelo responde A2UI: QaAnswerText + QaActionProposal{proposalId}
                          │
                          ▼
card lee la propuesta desde la evidencia (no del texto del modelo)
usuario edita → Confirmar ──► AssistantProvider.executeAction ──► use case
                                                                 ──► home refresh
```

- **Las tools nuevas nunca escriben.** Validan y devuelven una propuesta, así una alucinación o un reintento del modelo no puede tocar la cartera.
- **La card no confía en los números del modelo.** Recibe solo `proposalId` y lee los datos del resultado de la tool, con el mismo patrón que `QaCompanyAnalysis` usa vía `QaEvidenceScope`.
- **Confirmar no pasa por el modelo.** No consume cuota y no depende de la red de OpenAI.
- `SaveGoalTool` hoy sí escribe directo desde la tool. Queda como está: guardar una meta es reversible y de bajo riesgo. Las operaciones de cartera no lo son.

---

## Qué ya existe y se reutiliza

| Pieza | Dónde | Uso |
|---|---|---|
| Alta de posición | `AddPositionUseCase` | Ejecutar la compra |
| Cierre por ticker con FIFO | `ClosePositionUseCase` con `positionId = ticker` → `_closeByTicker` en `closed_position_repository_impl.dart` | Ejecutar la venta. Ya valida "no podés vender más de lo que tenés" y deshace si falla a mitad |
| Borrado | `DeletePositionUseCase` / `DeletePositionsByTickerUseCase` | Borrar posición cargada por error |
| Precio de un día | `GetPriceOnDateUseCase` | Completar el precio |
| Resolver "Apple" → AAPL | `CompanyTickerResolver.resolve` (detecta ambigüedad, hasta 4 candidatos) | Ticker de la propuesta |
| Cálculo USD ↔ acciones, precio autocompletado vs. editado | `AddPositionProvider` / `ClosePositionProvider` | Extraer la lógica pura para que la card y las pantallas usen la misma |
| Gating por plan | `PlanMatrix` + `AssistantToolContext.lockedFeature` + `AssistantTurnPolicy.paywallFor` | `locked` → paywall de Premium |
| Canal card → pantalla | `QaFollowUpScope` (InheritedWidget) | Modelo para el nuevo `QaActionScope` |
| Refresh de la cartera | `homeProvider.notifier.refresh(silent: true)` | Después de ejecutar |

---

## Fases

### F1 — Dominio y plan

1. `PlanFeature.portfolioActions` en `_premium` de `plan_matrix.dart`, más `labelKey` y la traducción (`plan_feature_portfolio_actions`). Se puede sumar a `highlights` de Premium si negocio quiere promocionarlo.
2. Modelo `ActionProposal` en `lib/features/assistant/models/action_proposal.dart`:
   - `id`, `kind` (`buy | sell | delete`), `ticker`, `companyName`;
   - `shares`, `amountUsd`, `inputMode` (`shares | usd`), `price`, `priceSource` (`close_on_date | user | current`), `date`;
   - venta: `heldShares` y `lotsPreview` (FIFO, con P&L estimado);
   - borrado: `lots`, la lista para elegir.
3. Estado de cada propuesta: `pending → saving → done | failed | cancelled`. Se guarda en `AssistantState` (`Map<String, ActionProposalStatus>`) y no en el `State` del widget, por lo mismo que `hasRevealed`: la card se desmonta al hacer scroll y no puede volver a "pendiente" ni ofrecer Confirmar de nuevo.
4. Extraer de `AddPositionProvider` / `ClosePositionProvider` un helper puro (`PositionDraftMath`) con:
   - cálculo de acciones desde USD;
   - validación de cantidad y precio;
   - regla de "precio autocompletado salvo que el usuario lo haya editado".

   Las dos pantallas pasan a usarlo, sin cambiar su comportamiento.

### F2 — Tools de propuesta (`lib/features/assistant/tools/action_tools.dart`)

Las tres implementan `DataTool` y se suman al final de `AssistantToolset.build`. El orden es fijo por el caché de prefijo de OpenAI.

**`propose_buy`**: args `company` (ticker o nombre), `shares` o `amount_usd` (uno de los dos), `date` (`YYYY-MM-DD`) y `price_usd` (opcional, solo si el usuario lo dijo).

**`propose_sell`**: args `ticker`; `shares`, `amount_usd` o `all: true`; `date`; `price_usd` opcional.

**`propose_delete_position`**: args `ticker`. Devuelve los lotes; la card deja elegir cuál borrar si hay más de uno.

Comportamiento de `run`, en este orden:

1. `ctx.gate(PlanFeature.portfolioActions, [])` → `locked` si es Free.
2. **Faltan datos** → `{status: needs_input, missing: ['date', 'quantity']}`. El modelo pregunta todo lo que falta **en una sola pregunta**. El schema también marca los campos como requeridos, pero el modelo a veces inventa, así que el chequeo real es este.
3. Ticker: `CompanyTickerResolver`. Si es ambiguo → `{status: ambiguous, candidates: [...]}` y el modelo pregunta cuál.
4. Validaciones de dominio, cada una con `status: invalid` y un `reason` que el modelo explica:
   - fecha futura o anterior a 1970;
   - venta de algo que no tiene (`ctx.heldTickers`);
   - venta de más de lo que tiene;
   - venta con fecha anterior al primer lote;
   - monto ≤ 0.
5. Precio: el que dijo el usuario o, si no, `GetPriceOnDateUseCase`. Si no se pudo traer, igual se propone con el precio vacío; la card lo pide y Confirmar queda deshabilitado hasta completarlo.
6. Registrar la propuesta con un `proposal_id` nuevo y devolver `{status: ok, proposal_id, ...datos}`.

Hace falta acceso al resolver, a los precios por fecha y a los lotes: se agregan a `AssistantDataSources` como lazies (mismo patrón que los fetchers).

**Cómo quedó (2026-10-08), con diferencias respecto de lo de arriba:**

- **Ticker:** las tools reciben un `ticker` y no resuelven nombres. Para "Apple" el modelo primero llama a `search_symbol`, que ya existe y ya resuelve la ambigüedad (ambiguous → pregunta). Resolver adentro de la tool no servía: "APPLE" en mayúsculas pasa como ticker válido.
- **Ticker no verificable:** si no se pudo traer el histórico y el usuario no dijo el precio, la compra devuelve `failed` / `price_unavailable` en vez de proponer sin precio. Sin histórico no se puede saber si el ticker existe.
- **Fecha anterior a todo el histórico:** la propuesta sale sin precio (`price_source: missing`) y la card lo pide. No se usa el primer cierre disponible, como hace `GetPriceOnDateUseCase`.
- **Un mes suelto** ("en marzo") cuenta como fecha faltante: solo se acepta `YYYY-MM-DD`.
- **Lotes y tenencia:** salen de `ctx.summary.lots` / `valuations`. No hizo falta tocar `AssistantDataSources`.
- **Registro:** las tools están en `lib/features/assistant/tools/action_tools.dart` (`ActionTools.build`) y **todavía no están en `AssistantToolset`**. Se registran en F5, junto con la card y la regla del prompt; antes, el modelo recibiría propuestas que no puede mostrar.

### F3 — Card `QaActionProposal`

- Catálogo: `CatalogItem` en `portfolio_qa_catalog.dart` con schema `{proposalId}` y nada más; nombre en `AssistantCatalog.widgetNames` / `items`. El widget va en `catalog/widgets/action_widgets.dart`.
- Toma los datos de `QaEvidenceScope` (resultado `ok` de `propose_*` con ese `proposal_id`). Si no lo encuentra, no se renderiza (guard igual al de las demás cards).
- Diseño con el kit (`QaCardShell`, `qa_tokens`, `qa_identity` para el logo):
  - **Compra:** logo + ticker (no editable), fecha (date picker; al cambiarla se vuelve a traer el precio salvo que el usuario lo haya editado), cantidad con toggle Acciones/USD, precio, total calculado.
  - **Venta:** lo mismo, más "Tenés X acciones", un atajo "Vender todo" y el P&L estimado (FIFO).
  - **Borrado:** lista de lotes (fecha, cantidad, precio) con selección. Texto claro: borrar no registra una venta.
- Botones: **Confirmar** (`ButtonSpinner` mientras guarda) y **Cancelar**.
- Estados:
  - `done`: la card queda en solo lectura con "Registrado ✓" y el link "Ver en cartera";
  - `failed`: el mensaje del `HttpError` y Reintentar;
  - `cancelled`: la card se ve atenuada.
- Si no hay scope (tests aislados), los botones aparecen deshabilitados, igual que `QaFollowUpScope`.

**Cómo quedó F3 (2026-10-08):**

- **Archivos:** card en `catalog/widgets/action_widgets.dart` (`ActionWidgets.qaActionProposal`, `QaActionProposalCard`); scope en `catalog/kit/qa_action_scope.dart`. El `CatalogItem` `qaActionProposalItem` está en `portfolio_qa_catalog.dart`, pero **todavía no está en `AssistantCatalog`**: registrarlo cambia el hash del prompt, así que va en F5 junto con las tools.
- **`QaActionScope` (lo implementa la pantalla en F4):**
  - `proposals`: el mapa de `AssistantState.actionProposals`;
  - `onConfirm(ActionDraft)` y `onCancel(id)`;
  - `priceOn(ticker, fecha)`: para la fecha nueva;
  - `onOpenPosition(ticker)`: opcional, para "Ver en cartera".
- **Lo que se mostró guardado:** `ActionProposalProgress.confirmed` guarda el borrador que se mandó a guardar. Así la card guardada muestra lo confirmado aunque se haya desmontado. F4 tiene que llenarlo al pasar a `saving`.
- **Textos:** en español fijo, como el resto del catálogo, sin claves de traducción.
- **Borrado:** con varias compras no viene ninguna marcada; el usuario elige cuáles. Con una sola, viene marcada.
- **Cambios en el kit:** `QaTickerHeader(tappable: false)`, para que tocar el ticker no pregunte "¿Cómo viene X?", y `QaTime.day` ("5 oct 2026").

### F4 — Ejecución

1. `QaActionScope` (InheritedWidget, en `catalog/kit/`) con `Future<ActionResult> Function(String proposalId, ActionDraft draft)`. Lo provee la pantalla del asistente alrededor de cada surface, junto a `QaFollowUpScope`.
2. `AssistantProvider.executeAction(proposalId, draft)`:
   - **Idempotencia:** si el estado no es `pending`/`failed`, no hace nada. El estado se pone en `saving` de forma **sincrónica**, antes del primer `await` (mismo criterio que `_sendGuard`), así un doble toque no crea dos posiciones.
   - Revalida el plan (`subscription.refresh()` y `PlanMatrix.allows`) y los datos editados con `PositionDraftMath`.
   - Llama al use case que corresponda.
   - Si sale bien: `homeProvider.refresh(silent: true)`, el toast de éxito del rediseño (`0900b58`) y haptics.
   - Si falla: `failed` con el mensaje del error.
3. **Memoria del modelo:** `PortfolioBrief.build` agrega `actions_this_conversation: [{proposal_id, kind, ticker, status}]`. Como el brief va en el `pinnedContext` y se reemplaza cada turno, el modelo sabe qué se confirmó o canceló sin meter turnos falsos en `ConversationLog`. La cartera del brief ya llega actualizada por el refresh de Home.

**Cómo quedó F4 (2026-10-08):**

- **Métodos nuevos en `AssistantProvider`:**
  - `executeAction(draft)`: pone `saving` sincrónico; revalida el plan (si ya no lo incluye: nada se guarda, la propuesta vuelve a pendiente y se abre el paywall); revalida el borrador; ejecuta con los use cases (`AddPositionUseCase`; `ClosePositionUseCase` con el ticker para FIFO; `DeletePositionUseCase` por cada lote elegido). Si sale bien: `done`, toast (`assistant_action_saved_*`) y `homeProvider.refresh(silent: true)`. Si falla: `failed` con el mensaje del error.
  - `cancelAction(draft)`.
  - `actionPriceOn(ticker, date)`.
- **Precio de otra fecha:** sale de `ActionPrices.closeOn` (en `action_tools.dart`), compartido con las tools. No usa `GetPriceOnDateUseCase`, que con una fecha anterior al histórico devuelve el primer cierre disponible.
- **`draft` en vez de `confirmed`:** `ActionProposalProgress.confirmed` pasó a llamarse `draft`, porque también guarda lo que había en la card al cancelar.
- **Pantalla:** `AssistantScreen` provee `QaActionScope` junto a los demás scopes. "Ver en cartera" usa `GotoPositionDetail`.
- **Brief:** `PortfolioBrief` agrega `actions_this_conversation` (vía `AssistantToolContext.actionsThisConversation`) cuando hay propuestas resueltas. El prompt lo explica en F5.
- **Ediciones de una card pendiente:** sobreviven a que la card se desmonte al scrollear (agregado el 2026-10-08 a pedido del usuario). La card manda cada cambio como `ActionForm` (textos, unidad, fecha, precio editado, lotes marcados) por `QaActionScope.onFormChanged`, y al volver a montarse arranca desde `formOf`. El provider los guarda en un mapa propio (`saveActionForm` / `actionFormOf`), **no** en `AssistantState`: emitir estado con cada tecla reconstruiría todo el chat.
- **Sin haptics propios al confirmar:** el toast ya es la confirmación.

### F5 — Prompt, revisión y layout

1. Sección nueva en `assistant_prompt_rules.dart` (en inglés, como el resto):
   - Llamar a `propose_*` cuando el usuario **cuenta** una operación hecha ("compré", "vendí", "cargá…") o pide registrarla. Una llamada por operación.
   - **No es una acción:** pedidos de consejo ("¿compro AAPL?") ni hipótesis ("si comprara…"); eso sigue yendo a simulación o análisis.
   - Nunca decir que quedó guardado: decir que revise y confirme.
   - `needs_input` / `ambiguous` → una sola pregunta corta con todo lo que falta. Sin card.
   - Fechas relativas ("ayer", "el lunes") se resuelven con el `as_of` del brief. Si el usuario no menciona ninguna fecha, **se pregunta**, no se asume hoy.
   - Respuesta: `QaAnswerText` corto + un `QaActionProposal` por propuesta `ok`.
2. `AssistantGroundingCheck._requires`: `'QaActionProposal': {'propose_buy', 'propose_sell', 'propose_delete_position'}`, más un chequeo de que el `proposalId` exista entre las tool calls del turno.
3. `AssistantLayoutGuard`: excepción para hasta 4 `QaActionProposal` cuando el primario es `QaActionProposal`, igual que `maxInvestOptions`.
4. **Allowlist del proxy:** cambiar el prompt y el catálogo cambia el hash. Hay que correr `UPDATE_PROMPT_ALLOWLIST=1 flutter test test/security/system_prompt_allowlist_test.dart` y desplegar `ai-chat` antes de publicar (ver `docs/runbooks/ai-proxy-cutover.md`). El deploy lo hace el usuario.

**Cómo quedó F5 (2026-10-08):**

- **Registro:** las tools `propose_*` están al final de `AssistantToolset` (después de `save_goal`, así no cambia el prefijo cacheado de las demás) y `QaActionProposal` está en `AssistantCatalog`.
- **Prompt:** `propose_*` en la lista de DATA TOOLS; `[W:ACTION]` va segunda, después de `[W:CONCEPTUAL]` y antes de las de precio, para que "compré 10 AAPL" no caiga en un gráfico; excepción de LAYOUT (hasta 4 cards); sección PORTFOLIO ACTIONS, que incluye `actions_this_conversation`.
- **Tamaño del prompt:** 101.992 → 104.432 caracteres (+600 tokens aprox.). El límite del test subió a 106.000, con nota.
- **Grounding:** `QaActionProposal` exige un resultado `ok` de `propose_*` con **ese** `proposal_id`.
- **Otros cambios:**
  - `AssistantLayoutGuard`: hasta `maxActionProposals = 4`;
  - intro de fallback en `AssistantAnswerReview`;
  - header: "Preparando la operación…" (`porty_status_action`).
- **Allowlist:** regenerada con `UPDATE_PROMPT_ALLOWLIST=1 flutter test test/security/system_prompt_allowlist_test.dart`, que agrega el hash nuevo en `supabase/functions/ai-chat/allowed_system_prompts.json`. **Hay que desplegar `ai-chat` antes de publicar** (lo hace el usuario). Sin el deploy, los turnos de esta versión vuelven `prompt_not_allowed`.
- **E2E en `assistant_submit_e2e_test.dart`:**
  - con Premium, la propuesta llega a la evidencia de la card sin guardar nada y el turno siguiente ve `"status":"cancelled"` en el brief;
  - con Free, `locked` → paywall de Premium.

### F6 — Tests y evals

Correr archivo por archivo. **No** usar `dart format` sobre carpetas.

- `test/features/assistant/tools/action_tools_test.dart`:
  - `needs_input` por cada campo faltante;
  - `ambiguous`;
  - USD → acciones;
  - fecha futura;
  - venta de algo que no tiene y venta de más de lo que tiene;
  - `locked` en Free;
  - precio del usuario respetado;
  - la tool nunca llama a un use case que escribe (fake que falla si se llama).
- `test/features/assistant/catalog/qa_action_proposal_test.dart`:
  - prefill desde la evidencia;
  - editar la fecha vuelve a traer el precio, pero no si el usuario lo editó;
  - toggle USD;
  - Confirmar deshabilitado con datos inválidos;
  - el estado `done` sobrevive a desmontar y volver a montar.
- `test/features/assistant/providers/`:
  - `executeAction` con doble toque → un solo alta;
  - falla → `failed` → reintento;
  - refresh de Home;
  - `actions_this_conversation` en el brief.
- Grounding y layout guard: casos nuevos en sus tests.
- `PositionDraftMath`: unit tests. Los tests actuales de las pantallas de alta y cierre tienen que seguir pasando sin cambios.
- Evals (`test/evals/assistant_tool_evals_test.dart`), casos nuevos:

| Mensaje | Esperado |
|---|---|
| "Compré 10 acciones de Apple el lunes" | `propose_buy` AAPL, 10, fecha correcta → 1 card |
| "Compré Apple" | Sin propuesta `ok`; pregunta cantidad y fecha juntas |
| "Metí 500 dólares en NVDA ayer" | `propose_buy` con `amount_usd: 500` |
| "Compré Alphabet" (GOOG/GOOGL) | Pregunta cuál |
| "Vendí todas mis TSLA hoy" | `propose_sell` con `all: true` |
| "Compré AAPL y vendí TSLA ayer" (con cantidades) | 2 llamadas → 2 cards |
| "¿Debería comprar AAPL?" | **Ninguna** `propose_*` |
| "Si compro 10 MSFT, ¿cuánto pesaría?" | **Ninguna** `propose_*` |
| Igual que el primero, con tier Free | `locked` → paywall Premium |

---

## Cuota

- El turno en el que Porty propone cuesta una consulta, como cualquier turno.
- Cada repregunta por datos faltantes también cuesta una, porque es un turno más. Para minimizarlo, el prompt pide **todo lo que falta en una sola pregunta**.
- Editar en la card, confirmar y cancelar no cuestan nada.

## Riesgos

- **Que el modelo confunda consejo con acción.** Mitigación: reglas explícitas, evals negativas y el hecho de que, aun si se equivoca, el resultado es solo una propuesta que el usuario puede cancelar.
- **Fines de semana y feriados:** `GetPriceOnDateUseCase` define qué precio devuelve. Verificarlo en F2; si devuelve error, la card pide el precio.
- **Propuestas viejas:** si el usuario confirma una card de hace varios turnos y entre medio vendió esas acciones por otra vía, el repositorio igual rechaza vender de más (`invalid_close_quantity`), y eso se muestra como `failed`.
- **La conversación no se persiste:** al cerrar el chat, las propuestas pendientes se pierden. Es aceptable en v1.

## Pendientes de decisión (con default)

1. **Deshacer después de confirmar.** Default: no en v1. Si se quiere, un toast con "Deshacer" unos segundos; borrar la posición recién creada es simple, deshacer una venta es más delicado.
2. **Ticker editable en la card.** Default: no. Si está mal, se cancela y se le dice a Porty.

## Orden sugerido

F1 → F2 (con tests) → F3 → F4 → F5 → F6 evals. F2 y F3 se pueden hacer en paralelo una vez fijado el formato del resultado de las tools.

## Resultados de F6 (2026-10-08)

Los evals de acciones son 11 casos `action-*` en `test/evals/assistant_tool_evals_test.dart`. Corrieron contra el proxy local con `gpt-4.1-mini` y una búsqueda de símbolos fake (`_Symbols`: Apple, Microsoft, Nvidia y "Alphabet", ambigua entre GOOGL y GOOG).

**Cambios al prompt que salieron de los evals** (cada uno regeneró la allowlist; los hashes intermedios, que nunca se publicaron, se sacaron):

- **No decir que ya se guardó:** el modelo escribía "Registré tu compra… para que la confirmes". Ahora la regla nombra "registré / guardé / agregué" y da el texto a usar: "Preparé…, revisala y confirmala".
- **Una fecha para todo el mensaje:** en "Ayer compré X y vendí Y", el "ayer" no se aplicaba a las dos operaciones y el modelo preguntaba la fecha.
- **Hipótesis:** en 1 de 4 corridas, "si compro 10 MSFT, ¿cuánto pesaría?" disparaba `propose_buy`. La regla ahora lo dice explícitamente.

**Última corrida completa** (la segunda se cortó porque la key de desarrollo se quedó sin créditos):

- 9/11 pasan;
- layout correcto en 11/11;
- **compra, compra en USD con "ayer", venta total, dos operaciones con dos cards, venta de más (explica que tiene 2), borrado, datos faltantes (pide cantidad y fecha juntas), consejo y hipótesis**: OK.

**Abierto:**

1. **"Alphabet":** con el último prompt, el modelo propone GOOGL directo, sin `search_symbol` (2/2). Antes buscaba y preguntaba (4/4). No se guarda nada sin confirmar y la card muestra el ticker, pero no es lo planeado. **Decidir:** aceptarlo, o hacer que el ticker se resuelva en la tool cuando el usuario nombró una empresa.
2. **Free:** en 1 corrida el modelo respondió con texto sin llamar a la tool, así que no apareció el paywall (nada se guarda). Falta medirlo con más corridas cuando haya créditos.

**Cambios en el runner de evals:**

- un turno que termina en error **siempre** falla (antes, los casos negativos pasaban con el turno caído);
- con `EVAL_DEBUG=1`, imprime el stack del error y el cuerpo de las respuestas sin `id`.

**Pendiente previo, ajeno a esta feature:** a veces `dart_openai` falla con `Null is not a subtype of String` al parsear una respuesta sin `id` (`OpenAIChatCompletionModel.fromMap`). Pasó 2 veces y no se pudo reproducir con la instrumentación. Probablemente es un JSON de error del runtime local que no trae `error`. En la app termina en el texto de fallback.

**Proxy local:** `supabase functions serve` no recarga `allowed_system_prompts.json` cuando cambia solo el JSON. Para que lo tome hay que hacer `touch supabase/functions/ai-chat/handler.ts` o reiniciar el `serve`.

