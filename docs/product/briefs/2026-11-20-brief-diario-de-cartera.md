# Brief de producto: Brief diario de tu cartera

**Fecha:** 2026-11-20 · **Autor:** porty-product-owner · **Estado:** aprobado para desarrollar desde ya, detrás de interruptor (decisión del usuario del 20/11) · **Nombre de trabajo:** "Brief diario" (el nombre visible lo decide el usuario, ver §13)

**Pedido del usuario:** "un Lisa pero para noticias de finanzas". Es una **funcionalidad clave que refuerza el centro del producto** (Porty como asistente integral de finanzas e inversiones), no un pivot a app de noticias.

---

## 1. Problema y para quién

**Problema.** El inversor casual de `PRODUCT.md` abre la app "a la mañana, el fin de semana o después de una noticia". Hoy Porty le da un motivo para volver **una vez por semana** (el informe del sábado) y avisos sueltos (movimientos grandes, `morning_brief` con concentración o desvío, como mucho una vez por mes por señal). Entre sábado y sábado se entera de lo que pasó con lo suyo por otro lado (medios, X, grupos de WhatsApp) y tiene que hacer él solo el cruce "¿esto me toca?". Ese cruce es justo lo que Porty sabe hacer y no está haciendo todos los días.

**Evidencia (y su fuerza):**

| Evidencia | Qué dice | Fuerza |
|---|---|---|
| Lisa (Lisa AI), #1 en Noticias del App Store de Argentina desde el 30/09/2026 (Nieman Lab, oct. 2026) | Hay demanda en Argentina de un resumen diario armado por IA, personalizado por temas y con fuentes citadas | Media: es otra categoría (noticias generales, audio de ~10 min, gratis); no sabemos su retención ni su modelo |
| Roadmap de noviembre, apuesta #5 | El único gancho recurrente de Free es el informe semanal; "Gold necesita valor recurrente"; las apps con IA retienen peor | Media (diagnóstico propio, sin datos de retención todavía) |
| Decisión del 02/11 (posicionamiento frente al MCP de IOL) | El "chat que ve tu cartera" se regala; diferenciamos por multi-bróker, números exactos con fuente y **contenido recurrente** | Alta como dirección |
| Decisión del 05/11 (planes v2) | Premium = "por qué se movió lo tuyo" | El brief diario es la forma más natural y frecuente de entregar ese valor |
| Datos propios de hábito | **No existen.** No hay evento de apertura de app (`app_opened` propuesto el 05/11) y la lectura de `weekly_report_opened` W2–W4 llega en diciembre | Hueco: es la principal incertidumbre de este brief |

Lo que **no** sabemos y no hay que suponer: si el usuario de Porty quiere algo **diario** (Lisa prueba que hay gente que quiere noticias diarias, no que el inversor casual quiera mirar su cartera todos los días; `PRODUCT.md` dice que "no vive pegado al mercado").

**Para quién.** Usuario **recurrente** con cartera cargada (cualquier método de carga) y, para el push, con notificaciones prendidas. Los tres planes, con contenido distinto (§7). No es para el usuario nuevo sin cartera: sin posiciones no hay cruce y el brief sería un noticiero genérico, que es justo lo que no queremos.

## 2. Job-to-be-done

> "Cuando me levanto y antes de que abra el mercado, quiero saber en un minuto si pasó algo que toque lo que tengo, para quedarme tranquilo o saber qué mirar, sin tener que leer diarios ni hacer yo el cruce con mi cartera."

Trabajos secundarios: "no enterarme por un amigo de que una empresa mía presentó resultados" y "entender qué significa para mí una noticia macro (BCRA, Fed, dólar)".

## 3. Por qué Porty y no Lisa ni ChatGPT

- **Lisa sabe qué temas te interesan; Porty sabe qué tenés y cuánto pesa cada cosa.** "Tu cartera cerró ayer +0,8 %; lo que más pesó fue NVDA, que subió 4 % el día que presentó resultados" no lo puede decir nadie que no tenga la cartera consolidada.
- **Multi-bróker:** IOL + eToro + Binance + capturas en un solo número. El MCP de IOL en ChatGPT ve un solo bróker.
- **Números calculados, no generados:** el porcentaje, el monto y "lo que más pesó" salen del cálculo de la app (como en el informe semanal); la IA solo redacta alrededor, y un validador determinístico tira lo que no está respaldado.
- **Cero configuración y llega solo:** un usuario podría armarse una tarea programada en ChatGPT con su cartera de IOL, pero tiene que saber hacerlo, no recibe push nativo, no tiene validador y no cruza brókers.
- **Formato:** Lisa son ~10 min de noticias generales; lo nuestro es ~1 minuto sobre lo tuyo. No competimos con Lisa: el que escucha Lisa también puede leer esto.

## 4. Qué es la v1 (alcance mínimo que prueba la hipótesis)

**Hipótesis:** si cada mañana hábil Porty le cuenta al usuario, en un minuto, qué pasó con **su** cartera y por qué noticias, el usuario vuelve a abrir la app más días por semana, y el "por qué" que ve recortado en Free lo lleva a Premium.

### Contenido (de arriba a abajo, lectura ≤ 60 s, prosa ≤ ~120 palabras)

1. **Cómo cerró tu cartera ayer** (determinístico, sin IA): variación del día en % y monto, respetando "ocultar montos". Si ningún mercado operó, no hay brief.
2. **Lo que más pesó** (determinístico): las 2–3 posiciones que más aportaron al movimiento, con su variación.
3. **Por qué, con fuente** (IA + validador): para cada una de esas posiciones, una línea que la vincula con un titular del día, **sin afirmar causa** (regla vigente del validador: "subió 4 % el día que presentó resultados", nunca "subió por los resultados"), con medio y link.
4. **Lo que pasó en lo tuyo** (IA + validador): hasta 3 titulares de tickers en cartera que no aparecieron arriba, parafraseados, con medio y link.
5. **Mercado y macro** (IA sobre una búsqueda compartida): 1–2 hechos del día (BCRA, Fed, dólar, riesgo país), y solo si el usuario tiene ese tipo de activo, la frase que lo conecta, informativa ("tenés bonos en pesos que ajustan por inflación; hoy se publica el dato de octubre"). En v1 el cruce macro → cartera se limita a un mapeo fijo y chico de temas a clases de activo (dólar/tasas, inflación/CER, riesgo país/bonos soberanos, tasas de EE. UU.); nada de inferencias libres.
6. **Hoy** (Gold): resultados que presentan hoy empresas en cartera o en la watchlist.
7. **Pie:** fuentes, hora de los datos, "Información, no una recomendación" (una línea discreta) y "Preguntale a Porty" (abre el chat con el brief como contexto; gasta consulta como cualquier turno).

Señales que hoy manda `morning_brief` (concentración, desvío del plan) pasan a ser una línea dentro del brief cuando aparecen, en lugar de un push aparte.

### Reglas de redacción (no negociables, heredadas del informe semanal)

- Informar, nunca recomendar: nada de comprar/vender/entrar/salir/mantener, ni repetir el consejo de un tercero (`_relayedAdvice`).
- Sin causas afirmadas, sin juicios de valuación, sin jerga, sin comillas (se parafrasea, no se cita).
- Toda cifra de la prosa está respaldada por los datos de entrada o por el titular citado; lo que falla el validador se reescribe una vez o se saca.
- Toda noticia lleva medio y link; nunca se copia texto de un artículo (hoy `headlines` devuelve solo título, medio, fecha y link).
- "No hay noticias" no se afirma: si no hay nada, la sección no aparece.

### Dónde vive

- **Pantalla propia** del brief del día (estilo editorial, filas, sin cards apiladas; `DESIGN.md`).
- **Fila en la Home** "Tu brief de hoy" mientras sea del día (como la tarjeta del informe semanal).
- **Push** (§8) que abre la pantalla.
- Historial: solo el de hoy y el de ayer en v1.
- Idiomas: es y en (el validador y el prompt del semanal ya soportan ambos); confirmar costo con el arquitecto.

### Queda afuera de la v1

- **Audio / TTS** (ver §5).
- Elegir temas y "nivel de interés" como Lisa: Porty ya sabe qué te interesa (lo que tenés).
- Fines de semana (el sábado es del informe semanal; no se canibaliza) y cripto 24/7 como brief aparte.
- Noticias de cualquier ticker fuera de cartera y watchlist.
- "Super investors" (sigue siendo del sábado).
- Integración con el widget (v1.1: el widget ya muestra `heldNews`).
- Elegir la hora, mail, compartir, historial largo, agenda macro (calendario económico): no tenemos fuente confiable hoy.
- Recomendaciones de cualquier tipo, obviamente.

## 5. Texto o audio: recomendación

**Recomiendo v1 en texto.** Audio neural (TTS) no entra en la v1; se valida la demanda en v1.1 con lectura en el dispositivo antes de pagar TTS.

Por qué:

1. **La hipótesis es el cruce con tu cartera, no el formato.** Lanzar texto + audio a la vez mezcla dos variables y no sabríamos qué funcionó.
2. **El formato es corto.** Lisa justifica audio con ~10 min de noticias; nuestro brief dura un minuto y se lee más rápido de lo que se escucha. Hay que mirar números y fuente.
3. **Los números son el contenido** (`PRODUCT.md`, principio 4). "Más cero coma ocho por ciento, ciento veinte dólares" se escucha peor de lo que se lee, y el link a la fuente no existe en audio. La fuente citada es parte del diferencial.
4. **El grounding se controla sobre texto.** El validador revisa texto; en audio hay que sumar control de pronunciación de tickers, montos y siglas.
5. **Costo y caché:** el audio lleva los números del usuario, así que se genera **por usuario y por día**, sin caché compartida, y además hay que guardarlo y servirlo. Sale 10 a 20 veces lo que cuesta el texto (§6).
6. **Licencias:** leer en voz alta un resumen de artículos de terceros es un uso más expuesto que mostrar título + medio + link.

**Camino al audio (v1.1, si la v1 funciona):** botón "Escuchar" con la voz del sistema (iOS/Android, costo cero), evento `daily_brief_listen_tapped`. Si una parte relevante de los lectores lo usa con frecuencia (umbral a definir con `porty-data-analyst`), se evalúa TTS neural con su costo real para Premium/Gold.

## 6. Costo estimado por usuario y día (supuestos)

**Todo esto es supuesto:** sale de los precios cargados en `news-context/handler.ts` (`gpt-6-luna` US$0,10/0,50 por millón de tokens; búsqueda web US$0,01) y de la decisión del 02/11 (informe semanal ~US$0,004). Hay que validarlo con `ai_turn_usage` en la primera semana.

| Parte | Cómo | Costo |
|---|---|---|
| Números de la cartera | Cálculo de la app, sin IA | US$0 |
| Titulares de tickers en cartera | `headlines` (GDELT, caché compartida) | US$0 |
| Macro del día | 1–2 búsquedas `news-context` **compartidas por mercado y por día** (no por usuario) | ~US$0,02–0,05 por día **en total** |
| Redacción del brief | ~3k tokens de entrada + ~0,5k de salida, 30 % con una reescritura | **~US$0,001–0,004 por brief** |
| Push | FCM | US$0 |
| **Texto, por usuario** | 21 días hábiles, abriéndolo todos los días | **~US$0,02–0,08 por mes** |
| Audio neural (si se hiciera) | ~1,5 min por día, por usuario; supuesto de ~US$0,015 por minuto (precio público de TTS de 2025, verificar) + almacenamiento | **~US$0,02 por día, ~US$0,45 por mes por oyente diario** |

**Regla de costo para el arquitecto:** el "por qué" de cada posición sale de `headlines` (gratis y con caché), **no** de una búsqueda web por usuario. Una búsqueda `news-context` por posición y por usuario costaría hasta ~US$0,05 por día (~US$1 por mes por Premium), que es lo que los topes del 05/11 quieren evitar. Si el arquitecto propone generar el brief **cuando se abre** (como el semanal) y no para todos a las 8, el costo solo lo pagan los que lo leen; lo prefiero.

## 7. Gating por plan (coherente con la decisión del 05/11)

| | Free | Premium | Gold |
|---|---|---|---|
| Cómo cerró tu cartera y lo que más pesó (sin IA) | Sí | Sí | Sí |
| Por qué, con fuente, de tus posiciones ("por qué se movió lo tuyo") | No: una fila tranquila al plan siguiente, **sin ticker** (misma regla que el widget del 05/11), `source: daily_brief` | Sí | Sí |
| Titulares de lo tuyo | No | Sí (tickers en cartera, `heldNews`) | Sí |
| Mercado y macro (1–2 hechos generales, sin ticker) | 1 hecho | Sí | Sí |
| Watchlist (noticias de tickers que no tenés) | No | No | Sí (`news`) |
| Hoy: resultados de tus empresas y de tu watchlist | No | No | Sí (los resultados ya son Gold) |
| Consumo de cupos | El brief **no** gasta consultas ni el cupo mensual de `news-context` del usuario (la macro es compartida) | Igual | Igual |

- El macro general en Free no choca con el 05/11: lo que se gatea son las noticias **de tickers**; un hecho de mercado sin ticker es el equivalente a lo que ya regala cualquier medio. Sin eso, el brief Free sería solo un número.
- **Propuesta que decide el usuario:** a las altas nuevas, los primeros 7 días hábiles con el brief completo de Premium (N en `app_config`, mismo patrón que los 3 informes del sábado). Una degustación de un día no forma hábito. Costo ~US$0,01–0,03 por alta (supuesto). Cambia lo que incluye Free, por eso no lo decido yo.
- El servidor valida el plan (como `claim_weekly_report`); la app no decide sola qué mostrar.

## 8. Frecuencia y momento

- **Días hábiles (lunes a viernes)**, si opera NYSE o BYMA. Sábado: informe semanal. Domingo: nada.
- **8:00 hora local**, antes de la apertura. Ojo con el ejemplo del pedido: a las 8 la cartera **no abrió todavía**; el brief habla del cierre anterior, de lo que pasó a la noche y de lo que viene hoy. "Abrió +0,8 %" requeriría un segundo envío después de las 11:30 y no lo recomiendo (más ruido, más trader UX).
- **Push:** absorbe al `morning_brief` actual (mismo horario, misma preferencia): **un solo push a la mañana**, no dos. Sale solo si hay algo que contar (movimiento de la cartera por encima de lo habitual, una noticia de una posición o una señal de concentración/desvío). Los días sin nada, el brief está en la Home pero no se notifica. Premium silencioso: mejor 2 pushes útiles por semana que 5 de relleno.
- Texto del push sin IA, armado con plantillas a partir de los números, y respetando "ocultar montos" ("Tu cartera se movió más que de costumbre ayer. Hay 2 noticias de lo tuyo."). El push nunca dice nada que no esté calculado.
- Cuenta para el tope de 3 automáticos por día (`dailyAutomaticCap`); el arquitecto define la prioridad frente a `big_move` y `portfolio_move` para no saturar.
- Depende de que el usuario haya hecho F0 (Firebase/APNs) en noviembre. Sin push, el brief vive solo en la Home y el alcance baja mucho.

## 9. Qué se reutiliza del informe semanal

| Pieza | Para qué |
|---|---|
| `weekly_report_input_builder.dart` + `weekly_portfolio_numbers.dart` | Números del día en lugar de la semana (variación, aportes por posición) |
| `investor_pulse_relevance.dart` | Decidir qué noticia toca qué posición (relevancia contra la cartera) |
| `weekly_report_validator.dart` | Mismas reglas (causas, consejo, consejo de terceros, jerga, comillas, cifras respaldadas, ausencias, "tu cartera" en ítems que no la tocan), con largos propios del brief |
| `prompts/weekly_report_prompt.dart` | Base del prompt y de la salida estructurada (mover → news_id; headlines → news_id) |
| `weekly_report_generator.dart` + `weekly_report_repository.dart` | Generación con reescritura y guardado del resultado del día |
| `claim_weekly_report` | Patrón para que el servidor decida qué contenido corresponde por plan y los días de cortesía |
| Edge functions `headlines` (GDELT + `news_source_allowlist`) y `news-context` (macro compartida) | Fuentes; no se agrega proveedor nuevo |
| `daily-jobs` (`jobHours.morningBrief = 8`) + `notify-dispatch` (`morning_brief`) | Disparo y push, ya por hora local, con silencio y tope diario |
| `investor-pulse` | **No** se usa en el diario (los super investors siguen siendo del sábado) |

## 10. Métricas

**Métrica norte:** % de usuarios con cartera cargada que abren el brief **3 o más días hábiles por semana** (lectores habituales), por plan. Fuente: `product_events`.

**Eventos nuevos (a confirmar con `porty-data-analyst`):** `daily_brief_opened{source: push|home|widget, tier}`, `daily_brief_item_tapped{kind: why|headline|macro|earnings|source}`, `daily_brief_ask_porty`, `daily_brief_feedback{useful}` (un "¿te sirvió?" discreto), `daily_brief_listen_tapped` (v1.1); `paywall_viewed{source: daily_brief}`. Y `app_opened{source}`, propuesto el 05/11: sin él no se puede medir si el brief suma días de uso o solo reemplaza otras aperturas.

**Secundarias:** apertura del push (abiertos / enviados); compras con `source: daily_brief` a 30 días; días activos por semana de la cohorte.

**Guardarraíles:**

- Retención D7 y D30 de la cohorte expuesta contra la cohorte previa (sin A/B, como todo; interruptor `daily_brief` en `app_config`).
- Bajas de notificaciones: % que apaga `morning_brief` o todas las notificaciones en los 14 días siguientes. Si sube claramente frente a la línea de base, se baja la frecuencia del push antes que nada.
- Costo de IA por usuario: brief ≤ US$0,10 por mes por lector diario (supuesto de §6 con margen); se mira en `ai_turn_usage`.
- Exactitud: % de briefs con partes sacadas por el validador y reportes de "esto está mal". Cualquier cifra equivocada que llegue al usuario es un incidente, no una métrica.
- No canibalizar el sábado: `weekly_report_opened` no cae en los lectores del brief.

**Umbral para seguir invirtiendo (propuesto, a validar con data):** a las 4 semanas, al menos 1 de cada 4 usuarios con push abre el brief 3+ días por semana y las bajas de notificaciones no suben. Si no, se reduce a "solo los días con algo" o se discute la frecuencia con el usuario.

## 11. Criterios de aceptación de usuario

1. Un día hábil, con cartera cargada y push prendido, si hubo algo que contar, recibo a las 8 (mi hora) un push sin montos si los tengo ocultos, y al tocarlo veo el brief del día.
2. Veo cuánto se movió mi cartera ayer y qué posiciones pesaron más, con los mismos números que en la Home.
3. Con Premium, al lado de cada posición que pesó veo una línea que la vincula con una noticia y puedo abrir la fuente; nunca dice "por" ni "debido a" como causa.
4. Con Free, veo los números y un hecho del mercado; donde iría el "por qué" hay una fila tranquila que lleva al paywall de Premium, sin ticker y sin modal.
5. Con Gold, además veo noticias de mi watchlist y quién de lo mío presenta resultados hoy.
6. Ninguna frase me dice que compre, venda o mantenga algo, ni repite que alguien lo recomendó.
7. Todo titular tiene medio y link; ninguna cifra contradice lo que muestra la app.
8. Si no tengo cartera, no recibo el brief. Si un día no hubo nada, no recibo push, pero el brief está en la Home.
9. Puedo apagarlo desde Notificaciones (la preferencia del `morning_brief`) y sigo viéndolo en la Home.
10. Desde el brief puedo tocar "Preguntale a Porty" y el chat arranca con ese contexto.
11. Leerlo entero me lleva un minuto o menos.

## 12. Prioridad (RICE) y roadmap

Misma escala que `roadmap.md` (R = % de la cohorte expuesta, supuesto; E en días-persona).

| Ítem | R | I | C | E | Score |
|---|---|---|---|---|---|
| Brief diario v1 (texto) | 50 | 2 | 40 % | 13 | **3,1** |
| Referencia: Hábito del sábado (#5) | 50 | 1 | 40 % | 2,5 + ops | 8 |
| Referencia: Prueba de Gold (diciembre) | — | — | — | — | ~18,7 |

- **R 50:** usuarios con cartera y push (no tenemos el número; se confirma con data en diciembre).
- **I 2:** apunta a retención diaria, que hoy nada ataca, y le da a Premium su valor más frecuente.
- **C 40 %:** analogía con Lisa (otra categoría) + intuición; sin datos propios de hábito.
- **E 13:** ver §14.

Por RICE queda **debajo** de lo de noviembre y de la prueba de Gold: es más caro y menos seguro. Lo defiendo igual como la apuesta de retención porque es lo único del backlog que crea un motivo de volver entre semana y porque reutiliza casi todo. El usuario decidió (20/11) desarrollarlo ya, en paralelo a noviembre. Lo que sí queda como compuerta es el **lanzamiento**: se prende después de leer el sábado (si el informe semanal con push no se abre, un diario no lo va a arreglar).

**Cuándo entra (decisión del usuario del 20/11: pisa "en noviembre no agregamos features" solo para esta feature):**

Regla de convivencia con noviembre: el desarrollo no puede ensuciar la lectura de cohortes de las apuestas #1–#5. Por eso:

- Todo detrás del interruptor `daily_brief` en `app_config`, **apagado en producción** hasta el lanzamiento; con el interruptor apagado, nada cambia para nadie (ni push, ni Home, ni `morning_brief`).
- Prioridad de los devs: si hay que elegir, ganan las apuestas de noviembre y la condición de publicar (#0). El brief usa la capacidad que sobra.
- Si el código sale en el release de noviembre, sale apagado. Las pruebas en producción, solo con una lista interna (cuentas del equipo), excluida de las cohortes.

Plan:

- **S3–S4 de noviembre (20/11–27/11):** spec de `porty-architect` (decisiones de §14). Primeros pedazos sin riesgo para la lectura: validador y prompt del brief (assistant), `claim_daily_brief` y macro compartida (backend).
- **27/11:** revisión de diciembre. Se mira `weekly_report_opened` W2–W4 con push; es la compuerta de lanzamiento, no de desarrollo.
- **Diciembre, primera mitad:** pantalla, fila en la Home, push con plantillas, eventos. QA por plan. Prendido solo para la lista interna, para ajustar redacción y cobertura argentina con carteras reales durante 2 semanas.
- **Lanzamiento:** al 100 % en la **primera semana hábil de enero**, y **después de la prueba de Gold** si el usuario la aprueba (no se mezclan dos cambios en la misma lectura de retención y conversión). La segunda quincena de diciembre es mala para medir un hábito diario (feriados, mercado flojo). Si no hay prueba de Gold y la lectura del 27/11 es buena, se puede adelantar a mediados de diciembre; lo decide el usuario.
- **Febrero:** lectura a 4 semanas; decisión de la capa 2 de §16 (feed y "¿cómo me afecta?") y de "Escuchar" con la voz del sistema.

## 13. Riesgos

| Riesgo | Mitigación |
|---|---|
| **Licencias de fuentes** | Seguir el modelo actual: título, medio, fecha y link, parafraseo propio, nunca texto del artículo, solo medios de `news_source_allowlist`. Sumar fuentes oficiales (BCRA, INDEC, CNV, Fed) para la macro: son primarias y sin problema de licencia. Un producto diario tiene más exposición que el semanal; el audio la sube más (otra razón para dejarlo afuera). |
| **Exactitud / grounding** | Números sin IA; el validador del semanal se aplica completo; sin causas afirmadas; las partes que fallan se sacan. Mapeo macro → clase de activo fijo y chico. Evento de "esto está mal" para detectar errores. |
| **Cobertura argentina** | GDELT busca por nombre de empresa; para bonos (AL30, GD30) y CEDEARs puede no encontrar nada por ticker. Por eso la macro va por tema, no por ticker. El arquitecto tiene que medir la cobertura con carteras reales antes de prometer "lo que pega en tus bonos". |
| **Costo** | Generar al abrir; "por qué" desde `headlines` (gratis); macro compartida; sin TTS. Vigilar el p99 en `ai_turn_usage`. |
| **Fatiga de notificaciones** | Un solo push a la mañana, solo con algo que contar, dentro del tope diario. Guardarraíl de bajas. |
| **Trader UX** | Diario no es intradía: un envío, sin "abrió/cerró en vivo", sin colores de alarma, un minuto de lectura. |
| **Brief Free que no alcanza** | Si el Free es solo un número, el usuario no vuelve y tampoco ve lo que pagaría. Por eso el hecho macro y la propuesta de 7 días completos. |
| **Canibalizar el sábado** | El diario no lleva super investors ni "lo que aprendí"; se mira `weekly_report_opened` como guardarraíl. |

## 14. Talla y dueños

**Talla: M–L, ~13 días-persona** (estimación, la cierra el arquitecto).

| Dueño | Qué | Días |
|---|---|---|
| `porty-architect` | Spec: generar al abrir vs. a las 8, reemplazo de `morning_brief`, `claim_daily_brief`, prioridad en el tope diario, mapeo macro | 1–1,5 |
| `porty-backend-dev` | `claim_daily_brief` y gating en el servidor; macro compartida por mercado y día en `news-context`; `daily-jobs` + `notify-dispatch` (push con plantillas); fuentes oficiales en la allowlist; caché del día | 4–5 |
| `porty-assistant-dev` | Prompt del brief sobre la base del semanal; validador con largos propios; reescritura; contexto para "Preguntale a Porty" | 3 |
| `porty-flutter-dev` | Pantalla del brief, fila en la Home, deep link del push, gating visual y teaser sin ticker, eventos | 4 |
| Revisión y QA | `porty-code-reviewer`, `porty-security-reviewer` (gating, planes), `porty-ui-reviewer`, `porty-qa-engineer` (humo por plan) | aparte |

## 15. Preguntas que decide el usuario

1. **Free:** ¿números + 1 hecho de mercado + teaser sin ticker? ¿Y los primeros 7 días hábiles completos para altas nuevas? (Cambia lo que incluye Free.)
2. **Push:** ¿un solo push a la mañana que reemplaza al `morning_brief` actual, solo los días con algo para contar, con la preferencia actual (prendida por defecto)? ¿O preferís que sea opt-in?
3. **Orden en enero frente a la prueba de Gold:** ¿el brief se prende al 100 % después de la prueba (mi recomendación) o antes?
4. **Audio:** ¿te parece validar la demanda con la voz del sistema en v1.1 antes de pagar TTS neural?
5. **Nombre visible:** "Brief diario", "Tu mañana", "Resumen de la mañana" u otro (con `porty-marketing-lead`).
6. **Licencias:** para un producto diario, ¿alcanza el modelo actual (título + link + parafraseo de la allowlist) o querés explorar un acuerdo con algún medio argentino antes de escalar (y antes de cualquier audio)?
7. **Visión (§16):** ¿aprobás el orden de capas (brief → feed + "¿cómo me afecta?" → seguir temas → comparar fuentes) y dejar afuera videos y "tendencias del mercado en general"?

## 16. Visión completa vs. v1

Así describe un cofundador de Lisa su app: seguís a los medios que querés, te arma un podcast según tus intereses, scrolleás noticias o videos, preguntás, buscás tendencias, pedís comparar fuentes, ves las últimas noticias, todo personalizado. El usuario quiere tomarlo como idea. Traducido a Porty, la diferencia de fondo se mantiene: en Lisa lo que seguís es una lista de intereses; en Porty lo que seguís **ya está cargado: es tu cartera**. Eso hace que casi todas las piezas existan a medias y que la personalización no cueste configuración.

**La v1 sigue siendo solo el brief diario.** El resto se suma en capas, y cada capa entra solo si la anterior mueve su métrica.

### Pieza por pieza

| Lisa | En Porty | Qué ya existe | Valor | Esfuerzo | Plan |
|---|---|---|---|---|---|
| Podcast personalizado | **Brief diario** (texto; audio después, §5) | Informe semanal, `headlines`, `news-context`, `morning_brief` | Alto: hábito diario + vidriera de Premium | M–L | Free (números + macro), Premium, Gold (§7) |
| Seguir medios | **Seguir tickers:** cartera + watchlist | Cartera (multi-bróker) y watchlist (Free 3, decisión del 05/11) | Alto, y ya está hecho: es lo que alimenta al brief | — | Todos |
| Seguir medios | **Seguir temas:** BCRA y dólar, inflación/CER, Fed y tasas, cripto | No existe como preferencia; el mapeo macro → clase de activo de la v1 es el primer paso | Medio: suma lo que no tiene ticker y hoy el usuario busca afuera | S–M (lista cerrada de 4–6 temas, sin texto libre) | Todos eligen; la profundidad sigue el gating (macro general en Free) |
| Seguir medios | **Medios preferidos** dentro de `news_source_allowlist` | La allowlist existe; no hay preferencia por usuario | Bajo para el inversor casual (no sabe ni quiere elegir medios) y fragmenta la caché compartida | S | No se hace hasta que alguien lo pida |
| Scrollear noticias | **Feed de lo tuyo:** titulares de cartera y watchlist, ordenados por peso | `headlines` + `widget_news_sheet.dart` (hoja del widget, ya ordena por peso y gatea por plan) | Medio: le da a Premium un lugar fijo para "lo tuyo" fuera del brief | S–M (reusar la hoja como pantalla) | Premium (cartera), Gold (+ watchlist); Free ve el teaser sin ticker |
| Preguntar | **"¿Cómo me afecta?"** desde cada noticia y desde el brief: abre el chat con la noticia y la posición como contexto | El chat de Porty con `get_news` y la cartera | Alto y barato: convierte lectura en conversación, que es el centro del producto | S | Todos; gasta consulta normal (Free tiene 20) |
| Tendencias | **Lo que se mueve en lo tuyo:** movimientos fuertes de cartera y watchlist | `market-watch` (cada 5 min, movimientos fuertes y watchlist, push) | Medio, ya existe | — | Como hoy |
| Tendencias | **Lo que se mueve en el mercado en general** (lo más buscado, lo que más sube) | No existe | Bajo y en contra de `PRODUCT.md`: empuja a mirar lo que no tenés, es trader UX | M | **Afuera** |
| Comparar fuentes | **"Qué dice cada medio sobre X"**: 2–4 medios de la allowlist, en qué coinciden y en qué no, cada afirmación con su fuente | `news-context` (búsqueda web con citas, restringida a la allowlist) | Alto como **diferencial de confianza** (responde a "4 de cada 5 dudan de la exactitud", roadmap) y encaja con "números exactos con fuente" | M (prompt + validador de atribución: cada frase con su medio) | Gold (cuesta varias búsquedas por pedido; entra en el tope de `news-context` del 05/11). Premium, solo de tickers en cartera, si el costo da |
| Últimas noticias | **Lo último de lo tuyo** | `headlines` (caché de 30 min) | Bajo como pieza aparte: es el feed ordenado por fecha | XS (una opción de orden del feed) | Igual que el feed |
| Videos | — | — | Bajo: no tenemos fuente con licencia, es caro y es el formato más "casino" del mercado; el inversor casual no lo pide | L | **Afuera** |

### Orden por capas

1. **Capa 1 (v1, este brief):** brief diario en texto + "Preguntale a Porty" al pie. Cartera y watchlist ya son el "seguir".
2. **Capa 2 (febrero, si el brief retiene):** feed de lo tuyo reusando `widget_news_sheet` + "¿Cómo me afecta?" en cada noticia + "Escuchar" con la voz del sistema. Las tres son S y reusan todo.
3. **Capa 3:** seguir temas (lista cerrada). Entra si el `daily_brief_item_tapped{kind: macro}` muestra que la macro se usa.
4. **Capa 4:** comparar fuentes, para Gold. Es la más interesante para diferenciarse, pero necesita su propio brief (costo por pedido, validador de atribución).
5. **Afuera:** videos, tendencias del mercado en general, medios preferidos (hasta que haya pedido real).

Prioridad por valor/esfuerzo: "¿cómo me afecta?" (alto, S) > brief diario (alto, M–L, pero es la base) > feed de lo tuyo (medio, S–M) > comparar fuentes (alto, M) > seguir temas (medio, S–M) > medios preferidos (bajo) > tendencias generales y videos (afuera). El brief va primero aunque "¿cómo me afecta?" rinda más por día de trabajo, porque es lo que trae al usuario a la noticia; sin brief ni feed, el botón no tiene dónde vivir más que en el chat.
