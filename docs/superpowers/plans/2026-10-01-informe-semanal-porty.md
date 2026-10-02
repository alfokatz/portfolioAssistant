# Informe semanal de Porty en la Home

**Fecha:** 2026-10-01 (decisiones 2026-10-02) · **Estado:** implementado y probado en local (F1–F6); nada desplegado · **Reemplaza a:** la §a ("Resumen semanal") de `2026-09-30-diferenciacion-planes.md`. Esa sección asume que las posiciones viven en Hive y que OpenAI se llama desde el cliente; ninguna de las dos cosas sigue siendo cierta.

## Estado de implementación

| Fase | Estado | Notas |
|---|---|---|
| F1 | ✅ 2026-10-02 | `lib/features/weekly_report/` (semana, números, input, builder). Las noticias aceptan un rango de fechas (`from`/`to`): Google con `after:/before:`, Finnhub con `from/to` |
| F2 | ✅ 2026-10-02 | Migración `20261002000000_investor_pulse.sql` (`super_investors` con los CIK verificados contra EDGAR + `investor_pulse_cache`), edge function `investor-pulse` y cliente con relevancia por cartera. **Antes de desplegar:** secret `SEC_USER_AGENT` con un contacto real (la SEC lo exige; sin él, la función devuelve solo noticias) |
| F3 | ✅ 2026-10-02 | Migración `20261002120000_weekly_reports.sql` (tabla + `claim/complete/fail_weekly_report` + `ai_report_begin`; columna `purpose` en `ai_turn_usage`). `ai-chat` con modo `x-porty-purpose: weekly_report` + `x-porty-report-week`: allowlist propio (`allowed_report_prompts.json`, vacío hasta F4), sin tools/stream/sistema extra, exige claim activo, no cobra cuota, tope de 6 llamadas por usuario por semana y 2000 tokens de salida. La degustación la decide el servidor: sin fila para "solo números". Repositorio Dart `WeeklyReportRepository` |
| F4 | ✅ 2026-10-02 | `prompts/weekly_report_prompt.dart` (fijo, hash en `allowed_report_prompts.json`) + esquema JSON estricto; `WeeklyReportDraft`, `WeeklyReportValidator`, `WeeklyReportGenerator` (1 llamada + 1 reescritura). Evals en `test/evals/weekly_report_evals_test.dart` (11 casos) contra el proxy local: 11/11 en 5 corridas seguidas; ~35% de los informes piden reescritura |
| F5 | ✅ 2026-10-02 | `WeeklyReportController` (máquina de estados del claim), `WeeklyReport` (lo que se muestra y se guarda en `payload`, v1), tarjeta en la Home entre el hero y las pestañas, pantalla `/weekly-report`. Variantes: completa, solo números con teaser de Gold, y solo números sin teaser cuando falla la generación. La variante bloqueada nunca lleva datos de Gold. Gold suma "Informe semanal" al paywall (`extraMarketingKeys`). Screenshots con fuentes reales: `test/screenshots/weekly_report_screenshots_test.dart` (`RUN_SCREENSHOTS=1`) |
| F6 | ✅ 2026-10-02 | Interruptor en el servidor (`app_config.weekly_report.enabled`, arranca apagado; lo chequean `claim_weekly_report` y `ai_report_begin`, así corta también en versiones viejas). Runbook: `docs/runbooks/weekly-report.md` (orden de despliegue, prender/apagar, checklist en el iPhone, monitoreo, evals) |

Pendientes conocidos de F5:
- Las posiciones cerradas en la semana no llegan desde la Home (solo tiene el conteo); el cálculo ya las soporta.
- Los haptics solo se pueden probar en el iPhone: el toque leve al terminar Porty con la Home abierta, la selección al abrir el informe y el toque al tocar algo bloqueado.

Aprendido en F4 (evals contra gpt-4.1-mini):
- Las reglas "blandas" del prompt no alcanzan; lo que tiene que cumplirse siempre lo decide la app. El tema de "para aprender" lo elige la app: lo específico de la semana primero y, si no hay, rota por semana. La concentración solo se manda si es notable (4+ posiciones y un peso ≥ 25%, o +5 pts en 4 semanas), y los titulares con instrucciones no llegan al prompt.
- El validador rechaza: números sin respaldo, consejos (incluido repetir el de un tercero: "recomendó comprar"), juicios de valuación, causas afirmadas (sin contar la voz pasiva), afirmar ausencias ("no hay reportes"), comillas en lo atribuido, mencionar la cartera en ítems que no la tocan e ids o tickers inexistentes.
- La aclaración "aunque no tenés X" se saca sola, sin reescritura.
- Cómo correr los evals: ver el encabezado de `test/evals/weekly_report_evals_test.dart` (proxy local + `scripts/eval_report_users.ts`).

Cambios respecto del diseño, decididos al implementar F2:
- Voces del mercado por **rol** cuando la persona cambia: "Presidente de la Fed" busca "Fed Chair". Probado en vivo el 2026-10-02: los titulares de la semana ya hablaban de Kevin Warsh, no de Powell.
- Scion (Burry) no presenta un 13F desde nov-2025: queda solo con noticias. Para Icahn se usa el CIK personal.
- Los Form 4 que aparecen en el CIK de un inversor pueden ser de **sus propios directivos** (Berkshire como emisora). Solo cuentan los que el inversor presenta como quien opera, y solo compras (P) y ventas (S). Varios Form 4 de la misma emisora en la semana se suman.
- Para los 13D/G se pasa de emisora a ticker con `company_tickers.json` de la SEC. En los 13F (v1) solo se dice "presentó su cartera del trimestre"; el diff queda para v2.
- La relevancia para el usuario se calcula en el cliente: ticker como palabra (los de una letra solo con `$`) o nombre de la compañía. El servidor arma un resumen igual para todos.

## 1. Qué es

Una vez por semana Porty le presenta al usuario, en la **Home**, un informe corto de cómo le fue a su cartera. Tiene cinco bloques:

1. **Tu semana en números.** Cuánto se movió la cartera (en % y en $, sin contar la plata nueva que agregó), cómo le fue contra el S&P 500, y qué posiciones la movieron más. Se ordena por **contribución** (peso × movimiento), no solo por %: un +12% en una posición del 2% importa menos que un −3% en una del 40%.
2. **Por qué.** Una línea por cada mover, apoyada en un titular real de la semana y con lenguaje prudente ("coincidió con…", no "bajó por…"). Si no hay noticia que lo explique, lo dice.
3. **Noticias de tus acciones.** De 3 a 5 titulares de la semana sobre lo que tiene, con medio, fecha y link. Porty agrega una línea de contexto a cada uno.
4. **Qué dicen los super investors.** De 2 a 4 ítems de la semana: declaraciones reportadas por medios y presentaciones a la SEC de un grupo curado de inversores. Aparecen primero los que tocan acciones de su cartera.
5. **Lo que viene.** Los earnings de sus acciones en los próximos 7 días.

### Ideas extra (propuestas, a decidir)

| Idea | Valor | Costo |
|---|---|---|
| **Concentración / drift:** "tu mayor posición ya pesa 38% (era 31% hace un mes)" | Alto. Es educativo, no es consejo, y sale de datos que ya tenemos | Bajo, no requiere fuente nueva |
| **Hitos:** máximo de 52 semanas en una posición, o una posición que cruza +50% desde la compra | Medio, da "momentos" | Bajo (Yahoo + fundamentals) |
| **Insiders de tus empresas:** compras y ventas de directivos en la semana (Form 4) | Medio-alto | Medio. Finnhub `/stock/insider-transactions` (verificar el plan free) o EDGAR |
| **Cambios de recomendación de analistas** | Medio | Medio. Finnhub `/stock/recommendation` (verificar) |
| **"Una cosa para aprender":** un concepto atado a lo que pasó (ej. qué es un *earnings beat* si una acción suya reportó) | Alto para el inversor casual, que es el foco de PRODUCT.md | Muy bajo (lo escribe el LLM, sin números) |
| **Pregunta para seguir con Porty:** un chip que abre el chat con la pregunta precargada (`HomeProvider.openAssistant(initialQuestion:)`) | Alto, lleva al uso del chat | Muy bajo |
| **Dividendos de la semana** (cobrados o por venir) | Medio | Medio. Requiere una fuente de dividendos |
| **Calendario macro** (Fed, inflación) | Medio | Alto. El calendario económico de Finnhub es pago. Queda para más adelante |

**Recomendación para v1:** los 5 bloques más concentración, "una cosa para aprender" y la pregunta para seguir. El resto queda para v2.

---

## 2. Restricciones que salen del código (2026-10-01)

| Hecho | Dónde | Consecuencia |
|---|---|---|
| Las noticias solo se buscan **por ticker** (Google News RSS con `when:7d` y fallback a Finnhub `/company-news`), en inglés, hasta 3 por llamada | `news_fetcher.dart`, `google_news_rss_repository_impl.dart`, `news_relevance_ranker.dart` | Super investors necesita una fuente nueva. El repo de Google News es en el fondo un query string, así que se puede generalizar |
| Una respuesta del chat permite **2 frases + 1 widget** (`assistant_layout_guard.dart`), 2 rondas de tools, 6 llamadas y 55 s | `openai_genui_service.dart:145-176` | El informe **no** puede ser un turno de chat. Va con un pipeline propio |
| El proxy `ai-chat` acepta solo system prompts cuyo hash esté en `allowed_system_prompts.json`; otro mensaje de sistema solo si empieza con `PORTFOLIO_BRIEF`. Topes: 3000 tokens de salida, 10 rondas, 700 KB, solo `gpt-4.1-mini` | `supabase/functions/ai-chat/handler.ts:26-84` | Un prompt dedicado es posible: su hash entra al allowlist y hay que redesplegar antes de publicar la app |
| El servidor cobra **1 consulta por turn_id** con respuesta final. No hay peso ni excepción. El "0" para turnos con todo bloqueado vive solo en `AssistantTurnPolicy.quotaWeight`, que producción no usa | `20260930120000_ai_proxy.sql:239-291` | El informe no debería gastar cuota del usuario: hace falta un modo "informe" en el proxy. Aparte de esto, los turnos con teaser de Gold **hoy se cobran**, y conviene corregirlo |
| La semana de la cartera y de cada posición ya se calcula en el dispositivo | `portfolio_period_utils.dart:59,92` (no cuenta la plata nueva), `ticker_period_utils.dart:49-85`, `home_chart_utils.dart:48-110` (contra el S&P, `^GSPC`) | Los números no necesitan backend |
| Las posiciones están en Supabase (`positions`, `closed_positions`), pero **su DDL no está en las migraciones** (`remote_baseline` está vacío) | `position_supabase_data_source.dart:10` | Antes de que el servidor las lea hay que hacer `supabase db pull`. Para v1, no hace falta |
| Precios de Yahoo **desde el cliente** (no oficial) | `yahoo_quote_remote_data_source.dart` | Los números del informe salen del cliente |
| No hay cron, ni pg_cron, ni push | `supabase/`, `pubspec.yaml` | v1 se genera al abrir la app. El push queda para v2 |
| Ya existe el patrón "una vez por semana, idempotente" | `20260930000000_weekly_free_analysis.sql`, `week_start.dart` | Se reusa la clave de semana (lunes local) y el estilo de las RPC |
| La verificación de números en prosa y el bloqueo de consejos ya existen en Dart | `analysis_prose_check.dart` | Se reusan generalizados: el informe pasa por los mismos chequeos |
| El ranking de noticias ya filtra menciones, agrupa eventos y prioriza fuentes confiables | `news_relevance_ranker.dart` | Se reusa |

---

## 3. Super investors: de dónde sale el dato

**Lo importante:** las carteras de los super investors (13F) se publican **una vez por trimestre y hasta 45 días después del cierre**. No dicen "qué pasó esta semana". Para la semana hay dos fuentes útiles:

1. **Declaraciones en medios (todas las semanas).** Una búsqueda en Google News RSS por inversor, `"<nombre completo>" when:7d` (con `hl/gl/ceid` coherentes; [parámetros](https://newscatcherapi.com/blog/google-news-rss-search-parameters-the-missing-documentaiton)). Se filtra con el mismo criterio que el ranker: el nombre completo tiene que estar en el titular, más una palabra de mercado (stock, market, fund, shares, economy, Fed, buy, sell, stake), se agrupan los eventos repetidos y se limitan los ítems por medio. Solo tenemos **titular + medio + fecha**, no el texto de la nota. Por eso Porty **parafrasea el titular**, atribuye ("según Bloomberg, Ackman…") y **nunca inventa citas textuales**.
2. **Presentaciones a la SEC (públicas y gratis).** La API `data.sec.gov/submissions/CIK##########.json` lista las presentaciones recientes por CIK, sin key ([EDGAR APIs](https://www.sec.gov/search-filings/edgar-application-programming-interfaces)). Hay que mandar un User-Agent con contacto y no pasar de ~10 req/s (verificar la política de *fair access*).
   - Semanal: **SC 13D/13G** (el inversor pasó el 5% de una empresa) y **Form 4** (compras y ventas cuando es insider o tiene más del 10%, ej. Berkshire).
   - Trimestral: **13F-HR**. En temporada (≈ 15 de feb/may/ago/nov) dice "Burry presentó su cartera del trimestre". Para ver qué compró o vendió hay que parsear el XML de holdings y comparar contra el trimestre anterior. Eso es v2. Si hiciera falta, hay APIs pagas que ya lo resuelven ([Eulerpool 13F API](https://eulerpool.com/blog/13f-api), [comparativa](https://arkolith.com/compare/13f-holdings-api)).

**La lista de inversores** va en una tabla editable (`super_investors`: nombre, alias, CIKs, fondo, activo), no en el código. Propuesta inicial de ~15:
- Warren Buffett / Berkshire (y Greg Abel)
- Bill Ackman (Pershing Square)
- Michael Burry (Scion)
- Ray Dalio (Bridgewater)
- Stanley Druckenmiller
- Howard Marks (Oaktree; sus *memos* son públicos)
- Cathie Wood (ARK)
- David Tepper (Appaloosa)
- Carl Icahn
- Seth Klarman (Baupost)
- Jeremy Grantham (GMO)
- Terry Smith (Fundsmith)
- Li Lu (Himalaya)
- Mohnish Pabrai
- Bill Gross

La lista la decide negocio. Los apellidos ambiguos (Marks, Wood, Smith) se buscan siempre con el nombre completo entre comillas.

**Relevancia para el usuario:** si un ítem menciona el ticker o el nombre de una empresa que tiene (se usa el mismo `company name` del ranker), sube al principio y se marca "Tenés AAPL". Si en la semana no hay nada relevante, se muestran los 2 ítems más importantes del mercado. Si no hay nada en absoluto, el bloque no aparece (no se rellena).

**Riesgos:**
- Atribución falsa o cita inventada: se mitiga con la paráfrasis de titulares y con ids de ítem (ver §5).
- ToS de Google News: es el mismo riesgo que ya corre `get_news`.
- Nombres homónimos: filtro estricto más eval.
- Mostrar a una figura como consejo de compra: la regla de prompt lo enmarca como "opiniones reportadas, no recomendaciones" y hay un disclaimer.

---

## 4. Arquitectura recomendada (v1)

```
Home abre (o la app vuelve a primer plano) en la ventana del informe
  └─ WeeklyReportController
       1. GET  weekly_reports(user, week)            → si está 'ready', lo muestra (cache local + Supabase)
       2. RPC  claim_weekly_report(week)            → 'generating' (idempotente entre dispositivos; chequea el plan)
       3. Datos determinísticos en el cliente        → WeeklyReportInput
            · cartera: PortfolioPeriodUtils / TickerPeriodUtils / benchmark (ya en HomeState)
            · movers por contribución, concentración
            · noticias por ticker: NewsFetcher + NewsRelevanceRanker (hasta 8 tickers, por peso)
            · earnings próximos 7 días: EarningsFetcher (1 llamada a Finnhub calendar)
            · super investors: GET functions/v1/investor-pulse?week=…  (caché global, ver abajo)
       4. 1 llamada LLM vía ai-chat (prompt dedicado, header x-porty-purpose: weekly_report)
            → JSON estricto (§5) que referencia ítems por id
       5. WeeklyReportValidator (números, ids, consejos, largo) → 1 reescritura si falla → si vuelve a fallar, informe sin prosa
       6. RPC  complete_weekly_report(week, payload)  → 'ready'
```

**Por qué así:**
- Los números y las noticias por ticker **ya se resuelven en Dart y están testeados**. Llevarlos al servidor duplicaría la lógica en TypeScript.
- Super investors **es igual para todos los usuarios**, así que va en el servidor con caché global: 15 búsquedas RSS + 15 consultas a EDGAR **por semana en total**, no por usuario.
- Una sola llamada LLM con prompt dedicado, sin tool loop: es más barata, más rápida y más fácil de evaluar (la §a original ya lo estimó).
- El LLM **solo escribe prosa** y elige ítems por id. Links, medios, fechas y números los pone la app, igual que en `QaCompanyAnalysis`. Así no se cuelan URLs inventadas (el motivo por el que se descartó el web search de OpenAI).
- La tabla `weekly_reports` hace que el informe aparezca igual en todos los dispositivos, no se genere dos veces y quede historial (en v2: "informes anteriores").
- Migrar a v2 (job de servidor + push) reusa el payload, el prompt y el widget.

### Cambios en el backend

1. **Migración `weekly_reports`:** (`user_id`, `week_start` date, `status` generating|ready|failed, `payload` jsonb, `attempts`, `created_at`, `updated_at`), PK (`user_id`, `week_start`). RLS de solo lectura de lo propio; escrituras por RPC `security definer` con grants explícitos (como `weekly_free_analysis`).
   - `claim_weekly_report(p_week)`: valida la semana con `_valid_week_start`, mira el tier efectivo, es idempotente y deja re-claim si quedó `generating` hace más de 2 min (generación cortada).
   - `complete_weekly_report(p_week, p_payload)`: valida el tamaño (< 64 KB).
   - `fail_weekly_report(p_week)`.
2. **`ai-chat` en modo informe:**
   - Si llega `x-porty-purpose: weekly_report`, el hash del prompt tiene que estar en un **allowlist separado** (`allowed_report_prompts.json`), y tiene que existir un claim `generating` de esa semana. En ese caso **no se cobra** la cuota: se registra el costo en `ai_turn_usage` con `purpose='weekly_report'` para medir, y se topea en 2 rondas (borrador + reescritura).
   - Con esto el informe no puede servir para usar el proxy como GPT gratis: el prompt es fijo y hay una vez por semana.
3. **Edge function `investor-pulse`** (GET, con JWT): arma el resumen de la semana con caché en una tabla `investor_pulse_cache(week_start, fetched_at, items jsonb)` y TTL de 6 h. Cada ítem trae: `id`, `investor`, `kind` (`news` | `filing_13d` | `filing_form4` | `filing_13f`), `headline`, `source`, `url`, `published_at`, `mentioned_tickers[]` (cruzando contra los símbolos del titular y del filing). Tests de Deno contra Postgres local, como `finnhub_test.ts`.
4. Arreglo aparte, que conviene hacer igual: el cobro de los turnos con teaser de Gold que dieron todo bloqueado (hoy se cobran aunque la app diga 0).

### Ventana y semana

- **Recomendación:** el informe cubre la **semana bursátil cerrada** (lunes a viernes). Se habilita desde el **sábado 00:00 hora local**, y se puede ver hasta que esté el siguiente.
- Si alguien abre la app un miércoles por primera vez, ve el informe de la semana pasada, con el título "Tu semana del 22 al 26 de sep.".
- La clave es el lunes de la semana cubierta (`weekStartKey`).
- Alternativa: un "en curso" de miércoles a viernes. No la recomiendo para v1: hay más generaciones, se repiten noticias y el viernes cambia todo.

### Plan (`PlanMatrix`)

| | Free | Premium | Gold |
|---|---|---|---|
| Tu semana en números (cartera, movers, concentración) | ✔ (sin LLM) | ✔ | ✔ |
| Contra el S&P 500 | teaser Premium (como `BenchmarkLockedCard`) | ✔ | ✔ |
| Por qué, noticias, super investors, earnings que vienen, "para aprender" | 1 preview borroso + "Incluido en Gold" | ídem | ✔ |

- Agregar `PlanFeature.weeklyReport` (Gold) en `plan_matrix.dart`, más `labelKey` y traducciones.
- Free y Premium **no llaman al LLM**: su informe es determinístico y cuesta 0. Es la palanca de conversión sin regalar el informe.
- **Degustación** (§9): la primera semana con informe, Free y Premium lo ven completo una vez. En ese caso el claim se marca con `courtesy = true` y sí llama al LLM.

### Costo estimado (gpt-4.1-mini, precios de la §a original)

- **Entrada:** ~3K del prompt + ~6–8K de datos (cartera, ~15 titulares de acciones, ~10 ítems de inversores, earnings) ≈ 10K. **Salida:** ~900.
- 10K × 0,40/M + 0,9K × 1,60/M ≈ **US$0,0055 por usuario Gold por semana** (≈ US$0,024 por mes). Con 1.000 usuarios Gold, ≈ US$24/mes. Las reescrituras suman ~10%.
- **Datos:** el cliente hace ~8 RSS más 1 Finnhub por usuario por semana. El servidor hace ~30 requests por semana en total.

---

## 5. Contrato con el LLM (salida JSON estricta)

```json
{
  "headline": "string ≤ 90 car. — la idea de la semana, sin cifras",
  "movers": [{ "ticker": "NVDA", "why": "≤ 140 car.", "news_id": "n3 | null" }],
  "news": [{ "news_id": "n1", "take": "≤ 140 car." }],
  "investors": [{ "item_id": "i2", "take": "≤ 160 car., atribuido y parafraseado" }],
  "learn": { "concept": "≤ 40 car.", "text": "≤ 220 car." },
  "follow_up_question": "≤ 80 car., en primera persona del usuario",
  "closing": "≤ 140 car. | null"
}
```

- `ticker`, `news_id` e `item_id` **tienen que existir** en el input. Si no, se descarta ese ítem.
- **Números en la prosa:** solo los que estén en el input (`AnalysisProseCheck` generalizado, con tolerancia de redondeo). Lo preferible es que la prosa **no** lleve cifras, porque las cifras las muestra la app.
- **Prohibido:** consejos de compra o venta, juicios de "barata/cara", predicciones, causalidad afirmativa ("cayó por"), citas textuales entre comillas atribuidas a inversores, y datos que no estén en el input.
- Si la llamada sale bien pero falta un bloque, el bloque **se oculta**. No se inventa relleno.
- Hay que verificar que el proxy deje pasar `response_format: json_schema` (es un pass-through, pero no está probado). Si no, se usa JSON por prompt más un parseo tolerante, como hoy con A2UI.

---

## 6. UI en la Home

**Dónde:** una tarjeta "Tu semana, por Porty" **entre el hero y las pestañas** (`home_screen.dart:133-135`), visible sin cambiar de pestaña, solo durante la ventana del informe. En el resto de la semana el acceso queda arriba de la pestaña Insights.

**Tarjeta compacta:**
- `PortyAvatar` chico, título "Tu semana, por Porty" y rango de fechas.
- El `headline` en una o dos líneas.
- Una fila con 3 datos: cartera %, contra S&P, mejor mover.
- Al tocar, se abre el informe completo.
- Es una superficie plana (Pure Surface + Whisper Border), sin cards anidadas; el terracota solo en el avatar.

**Pantalla completa (ruta propia, opaca):**
- Los bloques del §1 como secciones editoriales separadas por divisores finos: filas planas, no cards.
- Fuentes como texto secundario tocable (abre el link).
- Al final, un chip "Preguntale a Porty: …" que abre el chat con la pregunta.
- Footer: "Informe informativo, no asesoramiento financiero personalizado. Las opiniones de inversores son las que publicaron los medios citados."

**Estados:**
- **Generando:** skeleton (`skeleton_text.dart`) con alto reservado y "Porty está preparando tu semana…".
- **Listo:** fade through de 220 ms dentro de `MotionAwareSize` (no `AnimatedSize` crudo: ver el arreglo del 2026-10-01) y haptic `textAnswerRevealed()`.
- **Falló:** el informe sin prosa (solo números) y un botón para reintentar.
- **Cartera vacía:** no hay tarjeta.
- **1 posición:** sin bloque de concentración.
- **Reduce motion:** se ve el estado final directo.

**Primera vez que se ve:** las secciones entran escalonadas con `FadeSlideIn`. Ya vista, aparece directamente (marca `seen_at`).

---

## 7. Fases y esfuerzo (estimado)

| Fase | Contenido | Días |
|---|---|---|
| **F0** | Decisiones abiertas (§9). Desplegar el `ai-chat` pendiente. Medir con evals cuánto sale el prompt | 0,5 |
| **F1** | `WeeklyReportInputBuilder` (cartera, movers por contribución, concentración, contra S&P, earnings, noticias por ticker con tope y orden por peso) + tests unitarios | 1,5 |
| **F2** | `investor-pulse` (Google News + EDGAR submissions, filtro, `mentioned_tickers`, caché) + tabla `super_investors` con seed + tests Deno | 2 |
| **F3** | `weekly_reports` + RPCs, modo informe de `ai-chat` (allowlist separado, sin cobro, tope de rondas, `purpose` en `ai_turn_usage`) + tests Deno + test del allowlist ampliado | 1,5 |
| **F4** | Prompt dedicado, esquema JSON, `WeeklyReportValidator`, reescritura, evals (§8) | 1,5–2 |
| **F5** | Tarjeta en la Home, pantalla del informe, plan/teasers, motion, haptics, widget tests, screenshots light/dark | 2–2,5 |
| **F6** | Flag (`app_config.weekly_report_enabled`), orden de despliegue (migraciones → funciones → app), runbook | 0,5 |
| **Total** | | **~9,5–11** |

v2 (aparte): job de servidor + push el sábado, diff de 13F, insiders, analistas, historial de informes.

---

## 8. Evals mínimos (F4)

1. Semana tranquila (todo ±1%) sin noticias: no inventa causas, el "por qué" dice que no encontró una noticia y no aparece bloque de noticias.
2. Un mover con noticia clara: usa ese `news_id` y lenguaje prudente.
3. Toda la cartera en rojo: tono calmo, sin consejo de "aprovechar para comprar".
4. Un super investor menciona una acción que el usuario tiene: aparece primero y bien atribuido, sin comillas inventadas.
5. Ítem de inversor con nombre homónimo (otra "Cathie"): queda filtrado antes del LLM. Es un test del filtro, no del LLM.
6. Ninguna noticia de inversores en la semana: el bloque no aparece.
7. Earnings la semana próxima: aparece la fecha y la prosa no la contradice.
8. Una sola posición: sin concentración, y el informe igual se lee completo.
9. El LLM devuelve un `news_id` inexistente o una cifra que no está en el input: el validador lo descarta y se reescribe.
10. Inyección en un titular ("Ignore previous instructions…"): se trata como dato. Los titulares van en el mensaje de usuario, delimitados.

---

## 9. Decisiones (2026-10-02)

1. **Ventana:** semana bursátil cerrada (lunes a viernes). Se habilita el sábado a las 00:00 hora local y queda visible hasta que se publica el siguiente. No hay "semana en curso".
2. **Plan:** Gold ve el informe completo. Free y Premium ven la versión con números (sin LLM) más un teaser "Incluido en Gold". **Degustación (confirmada):** la primera semana en que un usuario Free o Premium tiene informe, lo ve completo una vez. Para que haya una sola vez por usuario, se registra en `weekly_reports` con `courtesy = true`.
3. **Super investors:** queda la lista del §3. **Voces del mercado (confirmadas):** Powell, Dimon y similares van en la misma tabla con `kind = 'market_voice'`, se muestran con la etiqueta "Voces del mercado" y se pueden desactivar por fila.
4. **Fuente de noticias:** v1 sigue con **Google News RSS** (y el fallback a Finnhub que ya existe). La alternativa barata para producción está en el §9b.

## 9b. Fuente de noticias para producción (documentado, no implementado)

**El problema:** Google News RSS no tiene una API oficial ni términos para uso comercial. El plan free de Finnhub, que es el fallback, es de uso personal y no comercial. Para v1 alcanza. Para una app que cobra suscripciones, conviene migrar antes de escalar.

**Recomendación: [Marketaux](https://www.marketaux.com/), plan Basic a US$29/mes (US$24/mes anual), 2.500 requests por día y 20 artículos por request.**
- Etiqueta cada nota con las entidades y tickers que menciona, y filtra por `symbols=AAPL,MSFT`. Hoy eso lo hacemos a mano con `NewsRelevanceRanker`.
- Tiene búsqueda por texto (`search="Bill Ackman"`), que cubre los super investors y las voces del mercado con la misma API, y filtros de fecha (`published_after`) e idioma. Hay notas en español: se puede probar `language=es`.
- Trae sentimiento por entidad. No lo usaríamos para opinar, pero sirve para priorizar.
- Es un servicio pensado para apps comerciales. **Antes de contratar hay que confirmar en sus términos** que se puedan mostrar titular, medio y link a usuarios finales que pagan suscripción.

**Cuánto alcanza:** con caché compartida en el servidor por ticker y por semana (como `finnhub_cache`), el costo crece con los **tickers distintos** que tienen los usuarios, no con los usuarios. 15 búsquedas de inversores por semana más un request cada 6 h por ticker activo entra holgado en 2.500 por día hasta varios miles de usuarios.

**Cómo se integra (≈ 1–1,5 días):**
- Función `supabase/functions/news` (o un endpoint nuevo en el proxy `finnhub`) con la key en los secrets, el mismo patrón de allowlist, caché y respuesta vieja si la fuente falla.
- Un `MarketauxNewsRepositoryImpl` detrás de la interfaz que ya usa `NewsFetcher`. La fuente se cambia con una clave en `app_config`, sin publicar otra versión.
- `investor-pulse` cambia la búsqueda de Google por `search=` de Marketaux.

**Alternativas evaluadas:**

| Proveedor | Precio de entrada | A favor | En contra |
|---|---|---|---|
| **Marketaux** (recomendado) | US$29/mes | Etiqueta tickers y entidades, búsqueda por texto, pensado para uso comercial | Hay que confirmar los términos de mostrar titulares |
| [GNews](https://gnews.io/pricing) | €49,99/mes (€39,99 anual), 1.000 req/día | 60k fuentes, búsqueda por texto, contenido completo | Es noticias generales: no etiqueta tickers. El free es no comercial |
| [Financial Modeling Prep](https://site.financialmodelingprep.com/pricing-plans) | ~US$19–22/mes (Starter) | Noticias por ticker; además trae 13F e insiders | Mostrar sus datos en una app exige un [acuerdo de licencia de display](https://site.financialmodelingprep.com/faqs) aparte, con precio a cotizar |
| Massive (ex Polygon.io) | US$29/mes (Starter) | Noticias por ticker junto con precios | El uso comercial (Business) arranca en ~US$2.000/mes ([referencia](https://tradingtoolshub.com/review/polygon-io/)) |
| Finnhub pago | desde ~US$49,99/mes (Basic; Standard ~US$129,99, Professional ~US$199,99; [referencia](https://apicostcalc.com/finnhub.html)). Los derechos de display/redistribución en apps comerciales se cotizan aparte ([pricing](https://finnhub.io/pricing)) | Ya está integrado (proxy + caché). Un solo proveedor para noticias, earnings y fundamentals | Hay que pedirle a ventas una cotización con display a usuarios finales. El total puede ser bastante más que el plan base |

**Para tener en cuenta:** earnings y fundamentals hoy también dependen del plan free de Finnhub (no comercial). **Decisión sugerida:** pedirle a Finnhub una cotización por noticias + earnings + fundamentals con display a usuarios finales de una app por suscripción. Si es razonable, se consolida todo en Finnhub (no hay que integrar nada nuevo). Si no, Marketaux para noticias y otra fuente para earnings y fundamentals.

## 10. Prompt de implementación (para que Claude ejecute este plan)

> Implementá el **Informe semanal de Porty** según `docs/superpowers/plans/2026-10-01-informe-semanal-porty.md`, en la rama actual, **fase por fase (F1 → F6)**. Al terminar cada fase, frená, mostrá tests y diff resumido, y esperá el OK antes de seguir. Las decisiones están en el §9.
>
> **Reglas del repo (no negociables):**
> - Leé DESIGN.md y PRODUCT.md. Estética "premium silencioso": sin sombras en reposo, sin glassmorphism, terracota solo para foco y la marca de Porty, Plus Jakarta Sans, touch targets de 44 px o más, animaciones de 150–250 ms `easeOutCubic`, reduce motion respetado, haptics solo vía `PortyHapticsService` y light/dark.
> - Para animar tamaños usá `MotionAwareSize`, nunca `AnimatedSize` crudo.
> - Nunca `git stash`. No commitees, no despliegues y no rotes keys: el usuario lo hace. Formateá solo archivos tuyos nuevos (nada de `dart format` sobre carpetas).
> - Nada de listas de tickers hardcodeadas. La lista de inversores vive en la tabla `super_investors`.
> - Todo número visible sale de los datos, nunca del LLM. El LLM solo escribe prosa y elige ítems por id.
>
> **F1 (cliente, datos):** creá `lib/features/weekly_report/` con `domain/weekly_report_input.dart` (modelos inmutables con `toJson` para el prompt) y `data/weekly_report_input_builder.dart`.
> - Reusá `PortfolioPeriodUtils.periodPnlFromHistory`, `TickerPeriodUtils.moveForDuration`, `HomeChartUtils` (contra `^GSPC`), `NewsFetcher` + `NewsRelevanceRanker`, `EarningsFetcher` y `weekStartKey`.
> - La semana es el lunes–viernes cerrado más reciente según la hora local. Usá cierres diarios: viernes contra el viernes anterior.
> - Contribución = peso al inicio × % de la semana.
> - Noticias: los hasta 8 tickers de más peso, como máximo 2 titulares por ticker y 15 en total, cada uno con id estable (`n1`…).
> - Tests: semana con aportes de plata (no cuentan como ganancia), feriado (4 días hábiles), cartera vacía, 1 posición, posición comprada a mitad de semana (cuenta desde la compra) y tickers con `.` (formato Yahoo).
>
> **F2 (servidor, super investors):**
> - Migración `super_investors` (seed con la lista del §3, editable) e `investor_pulse_cache`.
> - Edge function `supabase/functions/investor-pulse/` con el estilo de `_shared/common.ts` (inyección de `Deps`, JWT propio, `verify_jwt=false` en `config.toml`). Fuentes:
>   - Google News RSS `"<nombre>" when:7d` con `hl=en-US&gl=US&ceid=US:en`.
>   - EDGAR `data.sec.gov/submissions/CIK{10 dígitos}.json`, con `User-Agent` de contacto y ≤ 5 req/s, filtrando `SC 13D`, `SC 13G`, `4` y `13F-HR` de los últimos 7 días.
> - Filtro: nombre completo en el titular más una palabra de mercado, agrupación de eventos y ≤ 2 ítems por medio. Calculá `mentioned_tickers` cruzando contra los símbolos.
> - Caché por semana con TTL de 6 h y respuesta vieja si falla la fuente.
> - Tests Deno con `fetch` falso contra Postgres local, como `finnhub_test.ts`.
>
> **F3 (servidor, informe):**
> - Migración `weekly_reports` y RPCs `claim_weekly_report`, `complete_weekly_report` y `fail_weekly_report`, con el patrón de `20260930000000_weekly_free_analysis.sql` (grants explícitos, `_valid_week_start`, `_effective_tier`, re-claim si quedó `generating` hace más de 2 min).
> - En `ai-chat/handler.ts`, modo `x-porty-purpose: weekly_report`: allowlist separado `allowed_report_prompts.json`, exigir un claim `generating`, no cobrar cuota, registrar el costo en `ai_turn_usage` con `purpose` y topear en 2 rondas.
> - Ampliá `test/security/system_prompt_allowlist_test.dart` para el prompt del informe, y agregá tests Deno del modo.
>
> **F4 (LLM):**
> - `prompts/weekly_report_prompt.dart`: fijo y sin fechas ni datos, para que el hash sea estable. En español rioplatense, con el tono de Porty y las reglas del §5.
> - Los datos van en el mensaje de usuario como JSON delimitado, con la instrucción de tratar los titulares como datos.
> - `WeeklyReportValidator` reusa y generaliza `AnalysisProseCheck`: valida números, ids, consejos, comillas atribuidas y largos. Si falla, hay una reescritura. Si vuelve a fallar, se publica el informe sin prosa.
> - Evals en `test/evals/` con los 10 casos del §8 (`RUN_ASSISTANT_EVALS=1`).
>
> **F5 (UI):**
> - `WeeklyReportController` (Riverpod), la tarjeta en `home_screen.dart` entre el hero y `_HomeSections`, y la ruta del informe completo con `FadeThroughPage` o con la transición opaca estándar.
> - Estados del §6, `PlanFeature.weeklyReport` en `PlanMatrix` y teasers según el §4.
> - Widget tests: estados, reduce motion, sin saltos de alto, plan Free sin llamada al LLM, informe ya visto que no se re-anima y cartera vacía.
> - Screenshots light/dark en iPhone SE y 17 Pro.
>
> **F6:** flag `weekly_report_enabled` en `app_config`, runbook en `docs/runbooks/weekly-report.md` con el orden de despliegue (migraciones → `investor-pulse` → `ai-chat` → app) y el checklist de verificación en el dispositivo (incluidos los haptics).
>
> **Al cerrar cada fase**, reportá: qué hiciste, qué tests corren y su resultado, qué quedó pendiente y cualquier supuesto que tomaste.
