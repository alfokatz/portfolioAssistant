# Asistente unificado — plan para prender el flag y borrar el pipeline por modos

**Fecha:** 2026-09-28
**Rama:** `feature/ui_redesign`
**Alcance:** plan nada más. No se toca código de producción en esta tarea.
**Fuentes:** código actual (incluidos los cambios sin commitear de `intent_router.dart` / `explore_prompt_rules.dart`), los commits `0509793`, `11625ee`, `fc720f5`, `7529b18`, `a3a0acc` y `30b3a32`, los tests de caracterización y del pipeline unificado, y una corrida descartable de `MessageNeedsAnalyzer` + `IntentRouter` sobre ~40 mensajes (ver A.1).

---

## 0. Estado verificado hoy (antes de empezar)

Tres cosas del punto de partida no coinciden con lo que se venía asumiendo:

- [ ] **La suite del pipeline unificado está en rojo.** `flutter test test/features/assistant/{unified,characterization,routing}` → 238 tests pasan, 3 fallan. Los tres fallos vienen de `30b3a32` (fundamentals):
  - `unified_submit_e2e_test.dart` **no compila**: `UnifiedPipelineDeps` pasó a exigir `createFundamentalsEnricher` y el harness del test no lo pasa (línea 211).
  - `unified_explore_migration_test.dart` › EX-13: busca `"Only if step 8 applies…"`, pero al insertar el paso 4 (fundamentals) el ranking se renumeró y ahora es el paso 10 (ver gap G7).
  - `mode_context_characterization_test.dart` › CTX-SHARED-1: `buildSnapshotJson` construye un `ExploreFundamentalsEnricher` real, que lee `dotenv` → `NotInitializedError`.
- [ ] **El test e2e de `submitMessage` con el flag prendido ya existe** (`test/features/assistant/unified/unified_submit_e2e_test.dart`, 9 tests, entró en `7529b18`). La tarea no es escribirlo de cero: es repararlo y sumarle los escenarios que le faltan (sección C).
- [ ] **Con el flag prendido, `IntentRouter.detectEngine` sigue corriendo en cada mensaje.** Decide si el mensaje va a Invest/Plan o al pipeline unificado (`assistant_provider.dart:175-187`). Invest y Plan quedaron fuera de la unificación a propósito (decisión del 2026-09-25). Consecuencias:
  - cualquier keyword de Invest/Plan que se dispare mal le **roba** el mensaje al unificado (gap G5);
  - `lib/features/assistant/routing/` y `modes/invest|plan` **no se pueden borrar** al hacer el cutover (sección E.4).
- [ ] **Los cambios sin commitear del router** (fundamentals, "Meta" la empresa vs. "meta" objetivo, "explicame cada uno de ellos", "mis dividendos") tocan el pipeline viejo. Aun así, el fix de `'meta'` **también es requisito para el unificado**: sin ese fix, "¿Cómo viene Meta?" matchea la keyword de Plan y nunca llega al unificado. Hay que commitearlos antes del cutover.

---

## A. Auditoría de paridad

### A.1 Método

- Recorrí `message_needs.dart`, `unified_context_builder.dart`, `unified_prompt_rules.dart`, `unified_access_policy.dart`, `unified_turn_history.dart` y el cableado `_sendUnified` de `assistant_provider.dart`, y los comparé con el router, `ExploreContextBuilder`, `explore_prompt_rules.dart`, `learn_prompt_rules.dart`, las reglas de Portfolio (casos PF-* de la caracterización), `AdviceNoticePolicy` y `sendMessage` (el pipeline por modos).
- Corrí un test descartable (ya borrado) con una batería de ~40 mensajes. Para cada uno pasé el `lastEngine` y el ticker de seguimiento. Salida: el motor que elige el router y los `MessageNeeds` del unificado. Usé dos variantes de Finnhub `/search`:
  - una **difusa**: devuelve 2 matches para cualquier palabra desconocida, parecido al comportamiento real de `/search`;
  - una **optimista**: devuelve 0 matches.
- Invest y Plan no se auditan por paridad: con o sin flag corren **el mismo código**. Lo que sí se audita es el router que decide cuándo llegan ahí (G5).

### A.2 Casos cubiertos por el unificado ✅

| Caso (origen) | Legacy | Unificado |
|---|---|---|
| Motor pegajoso: precio después de un turno de Learn/Portfolio (ROUTE-FIXED, `11625ee`). "¿cómo le ha ido a mi Portfolio?" → "y a AAPL como le ha ido en el último año?" | router → explore por señal de ticker | `tickers=[AAPL]`, sin herencia de modo ✅ |
| Invest/Plan pegajosos (`0509793`) | router por contenido | mismo router con flag o sin flag ✅ |
| Stop words de una letra: "¿Y las noticias?" no extrae el ticker "Y" (`0509793`) | `TickerExtractor` | mismo extractor; el seguimiento resuelve AAPL y marca `isExplicitNewsRequest=true` ✅ |
| Palabra de pregunta con tilde: "¿Cómo viene Meta?" (`0509793`) | `CompanyNameCandidateExtractor` | `tickers=[META]` ✅ (necesita el fix de `'meta'` sin commitear; si no, se va a Plan en los dos pipelines) |
| Nombre de compañía: "¿Qué métricas tiene Apple?" | resolver + keyword de fundamentals (sin commitear) | `tickers=[AAPL]`; fundamentals se piden siempre que haya ticker y plan Gold ✅ |
| Superlativo sobre la cartera propia con período: "¿cuál de mis acciones subió más esta semana?" (B4) | portfolio mode | `needsAllPositionPeriods=true` ✅ |
| Superlativo de mercado: "¿qué acción subió más hoy en el mercado?" (B5) | explore trae SPY | no trae el proxy, responde solo con texto ✅ (mejora) |
| Mercado general: "¿Cómo está el mercado hoy?" | SPY | `proxy=SPY` ✅ |
| Conceptual con ticker de ejemplo: "¿Qué es un ETF, como SPY?" (ROUTE-1) | learn | `isConceptual=true`, sin precios ✅ |
| "qué es" sobre la cartera propia: "¿qué es lo que tiene más riesgo en mi portfolio?" | portfolio | `own=true`, no es conceptual ✅ |
| Seguimientos con palabra clave de seguimiento: "¿Y las noticias?", "¿Por qué?", "¿y en el último año?", "¿y qué expectativas hay sobre estos resultados?" | `_lastExploreTicker` | `usedFollowUpTicker=true` ✅, **solo si el resolver no devuelve ambigüedad antes** (ver G3) |
| Gating de noticias explícitas (Gold) y peso 3 en la cuota (`0509793`) | `isExplicitNewsRequest` | igual, cubierto por el e2e (cuando vuelva a compilar) ✅ |
| Estimación de EPS del próximo reporte (`a3a0acc`) | regla en explore | misma regla en el unificado ✅ |
| GAP-PF-1..5 y GAP-LN-1..2 de la caracterización | — | cerrados en el **texto** de las reglas (`unified_rules_contract_test.dart`); falta confirmarlo contra el modelo (B) |
| Cada id de caso de Portfolio/Learn y los 23 de Explore | — | migrados con chequeo de cobertura (a nivel texto) ✅ |
| Seguimiento conceptual ("¿y cómo se aplica eso?") | historial del motor learn | un solo historial para todo ✅ (mejora) |

### A.3 Casos del legacy que el unificado NO cubre todavía ❌

Severidad: **alta** bloquea el cutover. **media** conviene resolverla antes del cutover o aceptarla por escrito. **baja** alcanza con cubrirla en QA.

- [ ] **G1 (alta): seguimientos sin ticker y sin palabra de seguimiento pierden el ticker.**
  Mensajes después de hablar de AAPL: "¿cuánto subió?", "¿cómo le fue el último año?", "¿y sus márgenes?", "¿y el dividendo?", "¿cuáles son las ganancias esperadas?", "analizame los fundamentals", "Dame el P/E y los márgenes de esta empresa".
  - Legacy: el router los manda a explore (verbo de precio, keyword de fundamentals o herencia) y `ExploreContextBuilder` usa `_lastExploreTicker` para **cualquier** mensaje de explore sin ticker.
  - Unificado: `_followUpCueWords` (`message_needs.dart:142`) solo reconoce noticias/por qué/reporta/resultados/precio/cotiza/a cuánto y "y + período". En la corrida, incluso con Finnhub optimista, estos mensajes terminan con `tickers=[]` → el modelo responde sin datos.
  - Dirección del fix: que las palabras de seguimiento incluyan los verbos de precio del router (`_priceMoveWords`), las keywords de fundamentals y las de earnings ("esperad", "eps", "consenso", "expectativa").
- [ ] **G2 (alta): "explicame cada uno de ellos" / "¿qué significan esos valores?" después de QaFundamentals.**
  - El unificado los clasifica como **conceptuales** (`isConceptual=true`) → no pide ticker ni usa el de seguimiento → no hay datos.
  - `unified_prompt_rules.dart` no tiene la sección `EXPLAINING FUNDAMENTALS` ni la excepción de líneas con "• ". Su RESPONSE STYLE dice "at most 2 short sentences… No markdown".
  - El legacy lo resuelve en los cambios sin commitear: la regla del router `lastEngine == explore && referencia a la respuesta anterior`, más la sección nueva en `explore_prompt_rules.dart`.
  - Hay que portar las dos partes: una señal de "referencia a la respuesta anterior" que gane sobre la de conceptual cuando existe un ticker de seguimiento, y la sección de reglas.
- [ ] **G3 (alta): el resolver de nombre de compañía corre en casi todos los mensajes.**
  - En el unificado, `CompanyTickerResolver` (Finnhub `/search`) corre para **todo** mensaje no conceptual, que no menciona la cartera propia y no trae ticker en mayúsculas. En legacy solo corría para lo que el router mandaba a explore.
  - Corrida con Finnhub difuso:
    - "Hola", "Gracias!", "Sos un héroe" y "Dame un resumen" consultan `/search` con esa palabra;
    - "¿Cuál es mi mejor posición?" consulta con "Cuál mejor posición";
    - "¿cuánto cobré de mis dividendos?" consulta con la frase entera.
  - Consecuencias:
    - (a) con 2+ matches, `ticker_ambiguous` gana en el paso 2 del ranking → Porty le pregunta "¿a qué empresa te referís?" a un "Hola";
    - (b) con un único match (por ejemplo, "Sos" → un ticker real), el mensaje pide datos de mercado → **paywall `marketDataLocked` para un usuario Free** por un saludo;
    - (c) la ambigüedad **bloquea el ticker de seguimiento** (`ambiguousCandidate == null` es condición), lo que empeora G1;
    - (d) más llamadas a Finnhub contra un límite de 60 req/min **por API key, compartida por todos los usuarios**.
  - Dirección del fix: pedir una señal de mercado antes de resolver (corrida capitalizada que no esté al principio de la oración, o keywords de precio/fundamentals/noticias), filtrar saludos e imperativos, y no dejar que el fallback de "mensaje entero" pise al ticker de seguimiento.
- [ ] **G4 (media): la lista de palabras de "cartera propia" está incompleta.**
  - "mi mejor/peor posición", "mi peor acción este mes" y "mis dividendos" dan `mentionsOwnPortfolio=false`.
  - Consecuencias: (a) disparan el resolver (G3); (b) un superlativo con período sobre la cartera ("¿cuál fue mi peor acción este mes?") no pide `position_periods` de todas las tenencias, y B4 queda sin datos. En legacy, Portfolio siempre traía `position_periods` (CTX-SHARED-1).
- [ ] **G5 (alta, bug compartido): el router le roba preguntas de cartera al unificado.**
  - La keyword de Invest `'invert'` es substring de "invertido" e "invertí". Así, "¿cuánto tengo invertido?", "¿en qué estoy invertido?" y "¿cuánto invertí en AAPL?" van a **Invest**. Un usuario Free recibe paywall `modeLocked`.
  - Justamente son ejemplos de las propias reglas unificadas (YOUR PORTFOLIO — CURRENT STATE), y figuran en `_ownPortfolioWords` como "tengo invertido" / "estoy invertido": se esperaba que llegaran al unificado.
  - No hay ningún test del router con "invertido".
  - No es una regresión (legacy hace lo mismo), pero prender el flag no lo arregla y el router se queda.
- [ ] **G6 (media, bug compartido): siglas financieras en mayúsculas que se extraen como tickers.**
  - "¿Cuál es el ROE de Nvidia?" → `tickers=[ROE]`. Nvidia nunca se resuelve y, si falla el fetch de "ROE", el mensaje se corta antes del modelo con `assistant_explore_fetch_failed`.
  - "¿Cuál es el EPS de AAPL?" → `[EPS, AAPL]` → aplican las reglas de **comparación de 2 tickers** (C5 → QaMetricStrip).
  - "¿Qué ETF me conviene?" → `[ETF]`.
  - Candidatas para sumar a `_stopWords` (ojo, algunas son tickers reales): ETF, EPS, ROE, ROA, PEG, PE, IPO, CEO, USD, TTM, YTD, EEUU, FED, IA, AI, SP.
- [ ] **G7 (media): referencias cruzadas desfasadas en `unified_prompt_rules.dart`.** Al insertar el paso 4 (fundamentals), el ranking se renumeró, pero el cuerpo sigue apuntando a los números viejos. El modelo recibe punteros que se contradicen:
  - línea 191 "use QaPriceChart instead (step 8)" → ahora es el 9;
  - línea 192 "is step 8: QaPriceChart" → 9;
  - línea 276 "(step 7-9)" → 8-10;
  - línea 358 "following step 8 like any single ticker" → 9 (el 8 ahora es HELD + PERIOD).

  Es lo que rompe EX-13. Conviene que las reglas se refieran a las secciones por **nombre** y no por número.
- [ ] **G8 (baja): seguimiento después de un turno de Invest/Plan.** `UnifiedTurnHistory.followUpTicker` saltea los mensajes de Invest (no tienen `subjectTickers`). "¿y las noticias?" después de una recomendación de Invest termina en el último ticker de un turno *unificado*, que puede ser viejo. Legacy hace lo mismo con `_lastExploreTicker`: hay paridad, pero hay que verificarlo en QA.
- [ ] **G9 (cambio intencional, verificar):** se eliminaron dos cortes previos al modelo.
  - Cartera vacía + pregunta de cartera: legacy mostraba el banner de error `portfolio_qa_no_positions`; ahora responde el modelo.
  - Explore sin ticker: legacy mostraba `assistant_explore_no_ticker`; ahora responde el modelo.

  Hay que validar el texto en evals y en QA.
- [ ] **G10 (cambio intencional, verificar):** el aviso de asesoramiento y el nudge de perfil (`AdviceNoticePolicy`) solo aplican a Invest/Plan, y siguen ahí. Hay que confirmar en QA que no aparecen en turnos unificados y que sí aparecen al pasar a Invest en la misma conversación.

### A.4 Tareas que salen de la auditoría

- [ ] Commitear los cambios sin commitear del router y de `explore_prompt_rules.dart` (el fix de 'meta' es requisito para los dos pipelines).
- [ ] Reparar los 3 tests rojos (sección 0).
- [ ] Resolver G1, G2, G3, G5 y G7. Decidir G4 y G6 (resolverlos o aceptarlos por escrito).
- [ ] Llevar cada caso de A.2 y A.3 a un test de tabla determinístico `message_needs_parity_test.dart` (mensaje + historial → `MessageNeeds` + motor del router). Es la "capa 0" de B y corre sin modelo.

---

## B. Harness de evals contra el modelo real

### B.1 Qué se evalúa y en qué capa

| Capa | Qué prueba | Modelo | Dónde corre |
|---|---|---|---|
| **0: needs** | mensaje (+ historial) → motor del router + `MessageNeeds` + paywall | no | `flutter test` en cada PR |
| **1: widget** | snapshot fijo + pregunta (+ turnos previos) → JSON A2UI del modelo → widget elegido y props | gpt-4.1-mini real | script manual / job con filtro de paths |
| **2: calidad de texto** (opcional) | tono, 2 oraciones, locked vs. empty vs. failed bien redactados | LLM juez | manual, no bloqueante |

La capa 1 usa **el mismo system prompt que producción**: el texto que devuelve `AssistantOpenAiService.unified()` y el cuerpo de `portfolioQaUserMessageBody`. También usa **snapshots reales** armados con `UnifiedContextBuilder` sobre repos fake (Yahoo/Finnhub con fixtures). Así se evalúa modelo + reglas + forma del contexto, sin depender de la red de datos.

### B.2 Formato de un caso

Un archivo por categoría en `test/evals/unified/cases/*.yaml` (o JSON):

```yaml
id: G1-price-followup
source: "auditoría A.3 G1 / 11625ee"
tier: gold
portfolio: fixture_three_positions   # AAPL, MSFT, KO + 1 cerrada
tickers: { AAPL: { fetch_ok: true, chart: true } }
statuses: { news: skipped, earnings: ok, fundamentals: ok }
history:
  - user: "¿A cuánto está AAPL?"
message: "¿cuánto subió?"
expect:
  needs: { tickers: [AAPL], used_follow_up: true }     # capa 0
  primary_widget: QaPriceChart                         # capa 1
  props: { ticker: AAPL }
  forbidden_widgets: [QaMetricStrip, QaTickerSnapshot]
  text_must_not: [invent_numbers]
```

### B.3 Qué cuenta como "correcto" (capa 1)

Para que un caso pase tienen que cumplirse los cuatro chequeos:

1. **Estructura:** JSON válido, raíz `Column`, `QaAnswerText` primero, como máximo un widget de datos (única excepción: QaNewsSummary en WHY con `news_enrichment: ok`) y el `SURFACE_ID` correcto.
2. **Widget:** el widget principal es el esperado, o está en un set permitido cuando las reglas admiten dos (por ejemplo, QaAnswerText solo o QaAnswerText + QaTipBanner en conceptual). Ningún widget prohibido.
3. **Datos anclados al snapshot:** cada número de las props de los widgets existe en el snapshot, normalizando formatos ("+1,2%", "\$4,98T", "38,6x"). Cada ticker de las props está en `tickers`. El texto no trae números que no estén en el snapshot (extracción por regex).
4. **Estado del dato:** si `*_status` es `locked`, el texto menciona el plan y nunca "no encontré / no tengo información". Si es `failed`, dice que no se pudo obtener. Si es `empty`, dice que no hay datos. Se chequea por keywords.

Cada caso corre **N = 3** veces:

- **crítico:** pasa si pasa 3/3 veces;
- **normal:** pasa si pasa al menos 2/3.

El reporte guarda la tasa por caso para detectar casos inestables.

### B.4 Casos (≈60, agrupados)

- [ ] **Regresiones de ruteo documentadas** (críticos): ROUTE-1/2/3, ROUTE-FIXED, la secuencia de `11625ee`, los casos de `0509793` ("¿Y las noticias?", "¿Cómo viene Meta?", la respuesta de meta "En 40 años quiero tener 1 millón" que debe ir a Plan) y los del router sin commitear (métricas, Meta, "cada uno de ellos", "mis dividendos").
- [ ] **Gaps G1–G8** como casos de varios turnos (críticos G1, G2, G3, G5).
- [ ] **Charla / adversariales** (críticos por G3): "Hola", "Gracias!", "Sos un héroe", "Dame un resumen", "👍". Esperado: sin `ticker_ambiguous`, sin paywall, solo QaAnswerText.
- [ ] **Portfolio** (un caso por id PF-*): TEMP day…year, NOT-ALLTIME, NO-HISTORY, CLOSED-*, GUIDE-*, B2, B3, B4, B6.
- [ ] **Explore** (EX-01…EX-23): precio, held con y sin período, fallback sin histórico, 2 y 3 tickers (C1–C6), mercado/SPY, B5.
- [ ] **Learn** (LN-*): conceptual, conceptual con consejo práctico, ticker de ejemplo, "qué es" sobre la cartera propia.
- [ ] **Matriz de datos externos**: {earnings, fundamentals, news} × {ok, empty, failed, locked}, más el EPS estimado (`a3a0acc`) y un solo dato de fundamentals vs. el resumen general (`30b3a32`).
- [ ] **Por plan**: Free con ticker propio (sin paywall), Free con ticker ajeno (paywall, **capa 0**: no llega al modelo), Premium con noticias explícitas (paywall Gold), Premium con fundamentals (`locked` en el texto).
- [ ] **Línea base legacy:** los mismos casos corridos contra el pipeline por modos (router → prompt del modo → snapshot del modo). Criterio de salida: **el unificado ≥ legacy en cada categoría**.

### B.5 Cómo se corre, contra qué y cuánto cuesta

- **Modelo:** el de producción, `OPENAI_MODEL=gpt-4.1-mini` (`assets/env/.env.*`), con la misma temperatura que usa `OpenAIGenUiService`. El id del modelo queda registrado en el reporte.
- **Tamaño del prompt:** el system prompt unificado mide **~174K caracteres (≈45–50K tokens)**, medido con `AssistantOpenAiService.unified().systemPrompt.length`. Cada llamada son unos 50–55K tokens de entrada y unos 0,5K de salida.
- **Costo estimado** (verificar la lista de precios vigente de OpenAI): con gpt-4.1-mini, ~\$0,02 por llamada sin cache y ~\$0,005–0,01 con el cache automático de prefijo. Una corrida completa (60 casos × 3 repeticiones × ~1,3 turnos ≈ 240 llamadas, más la línea base legacy) sale **~\$3–10**. Tiempo: ~5–10 min con 6–8 llamadas en paralelo.
- **Frecuencia:** el repo **no tiene CI** (no hay `.github/workflows` ni equivalente).
  - [ ] Capa 0: en `flutter test` local. Si se suma CI, ahí.
  - [ ] Capa 1: script manual (`tool/run_unified_evals.sh` o `flutter test --tags eval` con la `OPENAI_API_KEY` del entorno). Obligatorio **antes del cutover** y en cada PR que toque `unified_prompt_rules.dart`, `unified_assistant_catalog.dart`, `message_needs.dart`, `unified_context_builder.dart` o `OPENAI_MODEL`. No corre en cada PR (costo + no determinismo).
  - [ ] Reporte: JSON + resumen markdown con la tasa de acierto por categoría y el diff contra la corrida anterior, commiteado en `test/evals/unified/reports/`.
- **Nota aparte:** ~50K tokens por turno es mucho para costo y latencia. El harness sirve también para medir un recorte del prompt más adelante (fuera de alcance acá).

---

## C. Test end-to-end de `submitMessage` con el flag prendido

### C.1 Qué capa mockear

- **Se mantiene el diseño actual:** el único fake es la llamada HTTP a OpenAI (`handleSend`), que devuelve A2UI canned y pasa por el normalizador y el dispatch reales. Yahoo, Finnhub, Supabase y RevenueCat son fakes. **LLM real no:** no es determinístico, cuesta y necesita secretos. Eso lo cubre B.
- **Lo que asegura el e2e es el cableado:** flag → router → needs → gating → contexto → servicio → surface → mensajes/cuota. Que el modelo elija bien no es su trabajo.

### C.2 Arreglos previos

- [ ] Pasar `createFundamentalsEnricher` en el harness (con `FakeCompanyFundamentalsRepository`, ya existe en `unified_test_fakes.dart`).
- [ ] Evitar que se repita: una fábrica `UnifiedPipelineDeps.fakes(...)` en `unified_test_fakes.dart` que la usen todos los tests. Así, sumar una dependencia rompe en un solo lugar.
- [ ] Arreglar CTX-SHARED-1 (inyectar el enricher o `dotenv.testLoad`).

### C.3 Escenarios

Ya existen (se mantienen): prompt de producción unificado · Free con ticker propio y el chart renderizado · Free con ticker ajeno → `marketDataLocked` antes de cualquier fetch · conceptual sin precios · seguimiento "¿y las noticias?" con peso 3 · todos los tickers fallaron → corte previo · generación rota → fallback · Invest/Plan por su pipeline · flag apagado.

Imprescindibles antes de prod (faltan):

- [ ] **Fundamentals:** Gold, "¿Qué métricas tiene Apple?" → el resolver da AAPL → `fundamentals_status: ok` → se renderiza QaFundamentals. Premium → `fundamentals_status: locked`, **sin** paywall.
- [ ] **Earnings:** Gold, "¿cuándo reporta NVDA?" → `earnings_calendar` ok. Premium → `locked`.
- [ ] **Premium + noticias explícitas** → `newsRequiresGold` antes de pedir nada. **Premium + ticker ajeno** → sin paywall, snapshot con `market_data: true`.
- [ ] **Secuencia de `11625ee`:** "¿cómo le ha ido a mi Portfolio?" → "y a AAPL como le ha ido en el último año?" → el 2.º snapshot trae AAPL.
- [ ] **G1:** "¿A cuánto está AAPL?" → "¿cuánto subió?" → el 2.º snapshot trae AAPL (hoy falla; queda como test del fix).
- [ ] **G3:** "Hola" con resolver difuso (2 matches) → sin `ticker_ambiguous`, sin paywall, el modelo se llama (hoy falla).
- [ ] **G5:** Free, "¿cuánto tengo invertido?" → va al unificado, sin `modeLocked` (hoy falla).
- [ ] **Pipelines mezclados:** unificado → Invest → unificado. Servicios separados, historial unificado intacto, `serviceForMessage` resuelve cada surface a su servicio y el seguimiento se comporta como se decida para G8.
- [ ] **Cuota agotada** → `quotaExceeded`, sin llamada al modelo ni mensaje agregado.
- [ ] **Falla de conexión** → banner de error + placeholder removido. **Timeout** → fallback.
- [ ] **Resolución tardía:** la surface se resuelve después del fallback → `applySurfaceReady` revive el mensaje.
- [ ] **B4:** "¿cuál de mis acciones subió más esta semana?" → `position_periods` de **todas** las tenencias en el snapshot.
- [ ] **Cartera vacía** + "¿cómo está mi cartera?" → sin corte previo, el modelo se llama (G9).
- [ ] **Reintento** (`clearErrorAndRetry`) después de un corte previo → vuelve a pasar por el unificado.
- [ ] **Envío concurrente** mientras hay uno en vuelo → se ignora (guard).
- [ ] Con el flag prendido, no se instancia **ningún** servicio de modo para portfolio/learn/explore (`serviceFor(mode) == null`).

---

## D. Checklist de QA manual en dispositivo real

**Preparación:**

- [ ] Build **debug** con `--dart-define=UNIFIED_ASSISTANT=true` en iOS y Android. Debug hace falta para ver los logs `[Unified/needs]`, que solo salen con `kDebugMode`. Al final, repetir un smoke en **profile/release**.
- [ ] Cuentas: Free, Premium y Gold con cartera (≥3 posiciones abiertas, entre ellas AAPL, y ≥1 cerrada), más una cuenta con cartera vacía.
- [ ] Anotar por cada flujo: widget que salió, número correcto, tiempo aproximado. Si algo falla, el log de `[Unified/needs]`.

**1. Básicos / UX**

- [ ] Saludo inicial y los 4 chips de sugerencia (cada uno responde algo coherente).
- [ ] Reveal, typewriter y haptics. Scroll con respuestas largas. Respuesta angosta alineada arriba a la izquierda (fix de `assistant_screen.dart` sin commitear).
- [ ] App a segundo plano en mitad de un pedido y vuelta. Modo avión en mitad de un pedido (banner + reintento).

**2. Cartera propia (Free)**

- [ ] "¿Cómo está mi cartera?" → QaPositionsSnapshot · "¿Qué posiciones tengo?" → QaPositionList · "¿Cuánto gané desde que compré?" → QaPnLBreakdown · "¿Qué tan concentrada está mi cartera?" → QaConcentrationBar.
- [ ] "¿Cómo me fue esta semana?" → QaPeriodChange (período, no all-time).
- [ ] "¿Cuál es mi mejor posición?" (G3/G4) · "¿Cuál de mis acciones subió más esta semana?" → QaTopMovers con changePct.
- [ ] Posiciones cerradas: total, mejor/peor, lista, comparar dos.
- [ ] **G5:** "¿Cuánto tengo invertido?" / "¿En qué estoy invertido?" → no debe aparecer el paywall de Invest.
- [ ] "¿Cuánto cobré de mis dividendos?" (G4).
- [ ] Cuenta vacía: "¿Cómo está mi cartera?" → texto amable, sin error técnico (G9).

**3. Tickers**

- [ ] Ticker propio sin período ("¿Cómo va mi AAPL?") → QaPriceChart · con período ("¿Cómo fue AAPL esta semana?") → QaTickerMove.
- [ ] Ticker ajeno: Free → paywall · Premium → QaPriceChart con el rango correcto (1D/1W/1M/3M/1Y/ALL).
- [ ] Minúsculas "¿cómo está nvda?" · nombre "Apple", "Meta", "Nvidia" · nombre ambiguo → pregunta de aclaración con candidatos.
- [ ] 2 tickers ("Comparame AAPL y MSFT", los dos propios → QaComparisonRow; con uno ajeno → QaMetricStrip) · 3 tickers → QaMetricStrip.
- [ ] Mercado: "¿Cómo está el mercado hoy?" → SPY aclarado como referencia · "¿Qué acción subió más hoy?" → solo texto.
- [ ] Ticker inválido "ZZZZ" → error de fetch · siglas: "ROE de Nvidia", "EPS de AAPL", "¿Qué ETF me conviene?" (G6).

**4. Datos externos × plan** (Premium y Gold)

- [ ] "¿Cuándo reporta NVDA?", "¿Cómo le fue a MSFT en su último reporte?", "¿Cuáles son las ganancias esperadas de AAPL?".
- [ ] "¿Cuál es el P/E de AAPL?" (1 dato) · "Fundamentals de MSFT" (4–6 datos).
- [ ] "¿Qué noticias hay de AAPL?" · "¿Por qué bajó TSLA esta semana?" (con y sin noticias).
- [ ] Premium: cada uno de los anteriores dice "no está en tu plan", nunca "no hay datos". Solo las noticias explícitas disparan el paywall.
- [ ] Sin `FINNHUB_API_KEY`: mensajes honestos de "no se pudo obtener".

**5. Seguimientos** (todos después de "¿A cuánto está AAPL?")

- [ ] "¿Y las noticias?" · "¿Por qué?" · "¿y en el último año?" · "¿cuánto subió?" (G1) · "¿cómo le fue el último año?" (G1).
- [ ] Después de "Fundamentals de AAPL": "¿y sus márgenes?" · "¿y el dividendo?" · "¿me explicás cada uno de ellos?" (G2, debe explicar con los valores y líneas "• ").
- [ ] "Hola" / "Gracias" en el medio no rompe el siguiente seguimiento (G3).
- [ ] Cambio de tema: después de AAPL, "¿Cómo está mi cartera?" no arrastra AAPL.

**6. Conceptual**

- [ ] "¿Qué es un ETF?", "¿Qué es un ETF, como SPY?", "Explicame el interés compuesto", "¿Qué significa el P/E?" → sin widgets de datos ni precios.
- [ ] "¿Y cómo se aplica eso?" como seguimiento conceptual.

**7. Charla**

- [ ] "Hola", "Gracias!", "Sos un héroe", "Dame un resumen", "👍" → sin pregunta de "¿qué empresa?" y sin paywall (G3).

**8. Convivencia con Invest/Plan**

- [ ] "Tengo \$500 para invertir" (Premium/Gold) → Invest con disclaimer y, si falta el perfil, el nudge. Después, "¿A cuánto está AAPL?" → vuelve al unificado sin disclaimer (G10).
- [ ] "En 40 años quiero tener 1 millón" → Plan · "¿Cómo va mi meta?" → Plan · "¿Cómo viene Meta?" → unificado.
- [ ] "¿Y las noticias?" justo después de un turno de Invest (G8): anotar a qué ticker se refiere.
- [ ] Free: "Tengo \$500 para invertir" → paywall de modo.

**9. Cuota**

- [ ] Agotar la cuota diaria → paywall `quotaExceeded`. Una noticia explícita en Gold descuenta 3.

**10. Regresión con el flag apagado**

- [ ] Smoke de 5 flujos (cartera, ticker, conceptual, Invest, noticias) con un build sin dart-define.

---

## E. Plan de cutover

### E.1 Condiciones para arrancar (gate 0)

- [ ] Suite verde, incluido el e2e extendido (C).
- [ ] G1, G2, G3, G5 y G7 resueltos. G4 y G6 resueltos o aceptados por escrito.
- [ ] Evals: el unificado ≥ legacy en cada categoría, 100 % de los críticos en 3/3 y ≥ 90 % global.
- [ ] Checklist D completa en iOS y Android.
- [ ] Los cambios del router sin commitear, commiteados.

### E.2 Mecanismo del flag: pasar a runtime

Hoy el flag es `bool.fromEnvironment` (compile-time). **Hacer rollback exige un build nuevo y pasar la revisión de las tiendas (días)**, y no se puede segmentar por usuario.

- [ ] Leer el flag de **Firebase Remote Config**, que ya está en `pubspec.yaml` y se usa para las traducciones (`remote_config_asset_loader.dart`), con default `false`. `--dart-define` queda como override local para desarrollo y tests (`debugOverride` sigue igual).
- [ ] Evaluarlo **una vez por conversación** (al construir `AssistantProvider`), nunca por mensaje: los dos pipelines tienen historiales distintos y cambiar a mitad de chat pierde contexto.
- [ ] Segmentar con la condición de percentil aleatorio de Remote Config, o con un hash estable del user id de Supabase.

### E.3 ¿Por porcentaje o todo-o-nada?

**Recomendación: por porcentaje, con kill switch remoto.** Etapas:

1. equipo/TestFlight;
2. 10 %;
3. 50 %;
4. 100 %.

Cada etapa dura ≥ 5 días o ≥ 500 turnos unificados, lo que tarde más. Si la base de usuarios activos es chica (menos de unos cientos por día), el porcentaje no da señal estadística. En ese caso: beta interna → 100 % directo, con el kill switch listo.

**Telemetría (hoy no existe: no hay SDK de analytics):**

- [ ] Un evento por turno en una tabla de Supabase (`assistant_turn_events`), **sin el texto del mensaje**, con estos campos:
  - `pipeline` (unified/legacy), `engine`, `tier`;
  - flags de needs (`ticker_count`, `used_follow_up`, `ambiguous`, `conceptual`, `own`);
  - `paywall_reason`, `pre_model_error`, `is_fallback`, `connection_error`;
  - `latency_ms`, widget principal de la surface, `quota_weight`;
  - `finnhub_status` (incluido 429).

**Métricas para decidir rollback** (cohorte unificada vs. legacy en el mismo período):

| Métrica | Umbral de rollback |
|---|---|
| Tasa de fallback (`is_fallback`) | > legacy + 2 pp o > 5 % |
| Turnos con `ticker_ambiguous` | > 3 % de los turnos (canario de G3) |
| Paywall por turno en Free (`marketDataLocked` + `modeLocked`) | > legacy × 1,5 |
| Re-pregunta: el usuario repite el ticker dentro de los 2 turnos siguientes (proxy de seguimiento perdido, G1) | > legacy + 5 pp |
| Latencia p95 | > legacy + 30 % |
| Respuestas 429 de Finnhub | cualquier aumento sostenido |
| Errores previos al modelo (`assistant_explore_fetch_failed`) | > legacy + 2 pp |

- [ ] Revisar el tablero (una query SQL sobre la tabla alcanza) al final de cada etapa. Además, leer los reportes cualitativos del equipo/beta.

### E.4 Cuándo es seguro borrar el pipeline viejo y qué se puede borrar

Se borra cuando se cumplen todas estas condiciones:

- [ ] 100 % durante ≥ 2 semanas, **o** un ciclo de release completo, sin haber usado el kill switch;
- [ ] ninguna métrica de E.3 fuera de umbral en ese período;
- [ ] el borrado va en un **PR separado** (según la decisión del 2026-09-25).

Las versiones viejas instaladas siguen teniendo su propio código, así que borrar solo afecta a los builds nuevos.

**Se puede borrar:**

- [ ] `modes/learn/`;
- [ ] `explore_prompt_rules.dart`;
- [ ] el `build()` de `ExploreContextBuilder` (antes, mover `buildTickerEntry`);
- [ ] las reglas y catálogos por modo de portfolio/learn/explore (`AssistantCatalog.buildFor` para esos modos);
- [ ] las ramas portfolio/learn/explore de `sendMessage`, `_buildSnapshotJson`, `buildSnapshotJson` y `SnapshotGroundingValidator`;
- [ ] `_lastExploreTicker` y `_exploreTickerResolver`;
- [ ] los logs TEMP `[Assistant/route]` y `[Explore/context]`, y `[Unified/needs]` si no se lo convierte en telemetría;
- [ ] `unified_assistant_flag.dart` y la lectura de Remote Config;
- [ ] los tests de caracterización de modos (quedan los contract tests del unificado).

**NO se puede borrar** (contradice el "borrar `routing/` y `modes/`" de la consigna):

- [ ] `routing/intent_router.dart`: sigue decidiendo Invest/Plan. Se reduce a un detector Invest/Plan vs. resto y se eliminan las ramas portfolio/learn/explore y `lastEngine` para esos modos.
- [ ] `modes/invest/` y `modes/plan/`: fuera de la unificación.
- [ ] Los helpers de `modes/explore/` que usa el unificado: `ticker_extractor`, `company_name_candidate_extractor`, `company_ticker_resolver`, `news_query_detector`, `broad_market_query` y los tres enrichers. Antes de borrar la carpeta hay que moverlos (por ejemplo a `lib/features/assistant/market_data/`).
- [ ] `AssistantMode.explore` como llave de gating: `UnifiedAccessPolicy.hasMarketData` usa `SubscriptionPolicy.isModeAllowed(tier, AssistantMode.explore)`. Hay que renombrarlo a un permiso por dato (`isMarketDataAllowed`) antes de eliminar los valores del enum.
