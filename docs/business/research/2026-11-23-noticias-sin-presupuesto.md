# Noticias por ticker sin proveedor pago, con licencia de uso comercial

**Fecha:** 2026-11-23 · **Autor:** porty-market-researcher (no es asesoramiento legal)
**Decisión que informa:** ¿de dónde sacamos titulares por ticker (EE. UU., CEDEAR/.BA, cripto) mientras no hay presupuesto para un proveedor pago, sin violar licencias, y cuánto cuesta?
**Leí primero:** `docs/legal/reviews/2026-11-22-noticias-fotos-y-fuentes.md` y `docs/runbooks/news-sources-v2.md`.

## Aviso sobre las fuentes (importante)

**No pude abrir ninguna página de términos en la fuente.** En esta sesión, `WebFetch` no resuelve ningún host externo (marketaux.com, alphavantage.co, sec.gov, gdeltproject.org, openai.com, developers.openai.com, globenewswire.com, prnewswire.com: todos `ENOTFOUND`; hay que habilitarlos en la red de la sesión). Todo lo de abajo viene de **resultados de búsqueda web (fragmentos)** del 23/11/2026. Cada dato lleva el link de donde salió el fragmento, pero **ningún término fue leído completo**. Donde digo "no leído" es literal. Antes de apoyar una decisión legal en algo de acá, alguien tiene que leer el texto original (lista en la sección 7).

Marca: [H] = hecho que dice un fragmento de la fuente; [I] = inferencia mía; [M] = fuente de marketing o secundaria (peso bajo).

---

## 1. Resumen ejecutivo

La combinación recomendada, en capas y a costo casi cero:

| Capa | Fuente | Para qué | Costo/mes | Riesgo de licencia |
|---|---|---|---|---|
| 0 | SEC EDGAR (8-K / 6-K) | Comunicados oficiales de empresas de EE. UU. y emisores extranjeros (resultados, hechos relevantes) | US$0 | Bajo [I] |
| 1 | GDELT bien usado (consulta por nombre de empresa, no solo por ticker) | Cobertura general de medios de la allowlist | US$0 | Bajo-medio |
| 2 | OpenAI `web_search` con caché compartida por ticker/día, solo si capas 0-1 vienen vacías | Cobertura de CEDEAR/.BA, cripto y cola larga | US$30-600 según tickers (tabla 4) | Medio |
| 3 (opcional, a validar) | BYMA hechos relevantes (emisores argentinos) | Acciones .BA locales (no CEDEAR) | US$0 si el plan gratis es real | Desconocido (términos no leídos) |

Lo que **descarto** por licencia: Alpha Vantage, Tiingo free, EODHD free, Brave/Google/Bing como fuente de datos, Common Crawl. **Marketaux** y **NewsData.io** quedan como candidatos solo si el usuario lee sus términos y confirma por escrito (sección 3).

Idea de mayor palanca [I]: para los **CEDEAR (.BA) buscar noticias del subyacente de EE. UU.** (AAPL.BA -> AAPL). El CEDEAR no tiene noticias propias; las que importan son las de la empresa. Eso resuelve gran parte de la "mala cobertura fuera de EE. UU." sin pagar nada.

---

## 2. Fuentes oficiales y gratuitas

### 2.1 SEC EDGAR
- [H] Límite: no más de 10 pedidos por segundo por usuario, sin importar cuántas máquinas; hay que declarar `User-Agent` con nombre y mail de contacto; la SEC se reserva el derecho de bloquear IP: https://www.sec.gov/os/accessing-edgar-data y https://www.sec.gov/developer (fragmentos de búsqueda, 23/11/2026; páginas **no leídas**).
- [H] Ya lo usamos (`sec`, `docs/runbooks/news-sources-v2.md`).
- Uso comercial: la política de reuso del sitio de la SEC **no la leí** (el fragmento de búsqueda no la cubrió). [I] Es información pública del gobierno de EE. UU. y lo que mostramos es el nombre del formulario + fecha + link a sec.gov, no el texto. Los anexos (Ex. 99.1, el comunicado de la empresa) los escribe la empresa; no los reproducimos.
- Qué cubre: 8-K (ítem 2.02 resultados, 1.01 acuerdos, 5.02 cambios de directivos, etc.), 6-K de emisores extranjeros (ADR), 10-Q/10-K. **No cubre**: .BA, cripto, notas periodísticas.
- Imagen: ninguna.
- Calidad para el usuario casual: alta en confiabilidad, baja en legibilidad ("8-K") salvo que Porty ponga un rótulo propio ("Presentó resultados", derivado del ítem 2.02) más resumen parafraseado con IA. [I]

### 2.2 Newswires (PR Newswire, Business Wire, GlobeNewswire)
- [H] Business Wire: sus términos restringen el sitio a presentar comunicados, recuperar RSS y leerlos, y prohíben usarlo para "almacenar, agregar, reproducir o distribuir"; ofrece **feeds licenciados** aparte (texto completo, o solo titulares con link): https://www.businesswire.com/terms-of-use y https://businesswire.com/help/feed-options (fragmentos; **no leídos**).
- [H] PR Newswire: su RSS es para sitios web y ofrece "opciones para publicadores"; los términos que devolvió la búsqueda no hablan del RSS: https://prnewswire.com/rss/ y https://prnewswire.com/terms-of-use/ (**no leídos**).
- [H] GlobeNewswire: material centrado en feeds licenciados para "media partners" (https://globenewswiresupportcenter.gcs-web.com/node/5916); **sus términos sobre RSS no los encontré**.
- Conclusión: la premisa "su contenido se publica para ser redistribuido" **no está confirmada por ninguna fuente que pude ver**, y el único término visible (Business Wire) apunta a lo contrario para agregación. [I] **No lo usaría como capa hasta que alguien lea los términos de los tres.** Alternativa más limpia: link a la página de prensa (IR) de la propia empresa, que la empresa publica para ser leída.
- Cobertura: mayormente EE. UU./Europa y por empresa, no por ticker; poco útil para .BA o cripto.

### 2.3 Argentina: CNV y BYMA
- [H] CNV: publica hechos relevantes en su plataforma (Autopista de Información Financiera) con consulta por empresa y fechas; no encontré una API pública documentada: https://www.argentina.gob.ar/preguntas-frecuentes-cnv (**no leído**). Un tercero (financialreports.eu) dice que ingiere esos filings; eso no prueba acceso oficial: https://financialreports.eu/filings/countries/argentina/ [M].
- [H] BYMA: tiene API de market data con sección de hechos relevantes; fragmentos mencionan un plan de hechos relevantes sin costo, 1.000 solicitudes/mes y otro plan de US$200/mes: https://byma.com.ar/productos/productos-de-datos/market-data/apis y https://www.byma.com.ar/newsroom/hechos-relevantes-avisos. **No encontré ni leí los términos de reuso o redistribución.** Los precios son de fragmentos, sin confirmar.
- [I] Sirve para **emisores argentinos** (GGAL, YPFD, PAMP...), no para los CEDEAR (cuyo emisor es extranjero). Es la fuente más "oficial" para el .BA local, pero depende de que los términos permitan mostrar título + link en una app paga: **a confirmar por escrito con BYMA**. Yo no contacto a nadie.

### 2.4 Otros reguladores
No investigué en profundidad. [I] Equivalentes de EDGAR en otros mercados (Companies House en UK, CVM en Brasil, etc.) existen pero no hay evidencia acá de que Porty los necesite todavía.

---

## 3. APIs de noticias con plan gratis

| Proveedor | Plan gratis (hechos) | Uso comercial | Veredicto |
|---|---|---|---|
| **Marketaux** | 100 pedidos/día, 3 notas por pedido: https://marketaux.com/pricing. "100% free to use on our free plan": https://www.marketaux.com/faq | **No pude leer los términos** (https://marketaux.com/tos). Ninguna fuente confirma ni niega uso comercial ni mostrar a usuarios finales. | **Pendiente de leer.** Aun si se permite, 100 pedidos x 3 notas/día no alcanza para cientos de tickers; sirve a lo sumo de refuerzo para los tickers más seguidos. |
| **Alpha Vantage** NEWS_SENTIMENT | 25 pedidos/día en gratis: https://www.alphavantage.co/premium | [H] Los términos conceden uso personal no comercial salvo acuerdo escrito; "For commercial use, please contact sales": https://alphavantage.co/terms_of_service | **Descartado** en gratis. |
| **Tiingo** News | Gratis = "internal use only", 3 meses de historia, 1 GB/mes; redistribuir exige licencia de negocio: https://api.tiingo.com/products/news-api y https://www.tiingo.com/documentation/appendix/developers | No para una app que muestra a usuarios | **Descartado** en gratis. |
| **EODHD** | 20 llamadas/día; cada pedido de noticias cuesta 5 (4 pedidos/día): https://eodhd.com/financial-apis/financial-news-api | [H] Los paquetes son para uso personal; el comercial pide licencia aparte: https://eodhd.com/financial-apis/commercial-vs-personal-license-use | **Descartado.** |
| **NewsData.io** | 200 créditos/día, noticias con 12 h de demora, sin texto completo (fuentes secundarias): https://newsdata.io/blog/?p=6514 | Un blog propio dice que se puede usar comercialmente; una guía de terceros advierte que algunos gratis lo prohíben. **Términos formales no encontrados.** | **Pendiente de leer.** Es una API de noticias generales, no por ticker: poco útil para esto [I]. |
| **StockData.org** | 100 pedidos/día, sin tarjeta: https://www.StockData.org (vía espejo) | Términos en https://www.stockdata.org/terms, **no leídos** | **Pendiente de leer.** |
| **Polygon / Massive** | Plan Basic ~5 llamadas/min (secundarias): https://apis.io/plans/polygon/polygon-plans-pricing/ [M] | Una fuente advierte que si la app es comercial o redistribuye, el precio individual puede no aplicar: https://apicostcalc.com/blog/polygon-massive-rebrand-api-pricing.html [M]. Sin términos leídos. | **Pendiente**; no hay evidencia de que el gratis incluya noticias con uso comercial. |

Patrón [I]: casi todos los planes gratis son "uso personal / interno". Los que no lo dicen explícitamente (Marketaux, StockData, NewsData.io) son una **apuesta hasta leer el texto**. Una API gratis que no declara la licencia no es "con licencia".

Imágenes: ninguna de estas fuentes confirmó que entregue una imagen con derecho de uso. La imagen sigue siendo el `og:image` de la nota (ver revisión de compliance 22/11, secciones 1.1-1.3).

---

## 4. OpenAI `web_search` con caché compartida por ticker

### Precio
- [H] Herramienta `web_search` estándar: US$10 por 1.000 llamadas, más los tokens del contenido de búsqueda a la tarifa del modelo: https://developers.openai.com/api/docs/pricing (fragmento; página **no leída**).
- [H] `gpt-5-mini`: US$0,25 por 1M tokens de entrada, US$0,025 cacheada, US$2 de salida: https://developers.openai.com/api/docs/models/gpt-5-mini.
- [H] Hay reportes en el foro de OpenAI de facturas más altas que lo listado (hasta ~US$100 por 1.000 búsquedas en un caso), sin resolución oficial: https://community.openai.com/t/heads-up-web-search-tool-billing-can-be-higher-than-you-expect-here-s-why/1236954 [M, voz de usuarios].
- [H, propio] Medido por el equipo en local el 11/10/2026: 1-5 búsquedas por consulta, US$0,013-0,058, típico US$0,025 (`docs/runbooks/news-sources-v2.md`). Uso **US$0,025 como caso conservador** y **US$0,015 como caso optimista** (1 búsqueda y pocos tokens) [I].

### Qué permiten los términos sobre mostrar resultados citados
- [H] La guía de la herramienta exige que, al mostrar resultados web o información de ellos a usuarios finales, las **citas en línea sean claramente visibles y clicables**: https://developers.openai.com/api/docs/guides/tools-web-search (fragmento). Porty ya lo cumple con `AnswerSources`.
- **No leí** los Términos de Uso/Servicio de OpenAI. [I, de memoria, a confirmar] Entre las partes, el *output* es del cliente, pero eso **no transfiere derechos de terceros** sobre el contenido de las notas. Lo que mostramos (titular, medio, fecha, link, resumen propio parafraseado) cae en el mismo régimen que GDELT: hechos + enlace.
- Riesgo propio de este canal: el modelo puede devolver URLs fuera de la allowlist o títulos reescritos. Mitigación: aceptar solo citas (`url_citation`) con dominio en `news_source_allowlist` y tomar el título del `url_citation`, no del texto del modelo.

### Costo mensual (supuestos explícitos)
Supuestos: 1 búsqueda por ticker por día, 30 días (cripto y .BA; con solo días hábiles, restar ~27%); `f` = fracción de tickers para los que GDELT/EDGAR vienen vacíos. Costo por ticker-día: US$0,015 (optimista) a US$0,025 (medido, típico). **No incluye** el resumen con IA aparte (ya existe).

| Tickers distintos | f = 100% (peor caso) | f = 40% (esperable) | f = 20% |
|---|---|---|---|
| 100 | US$45-75 | US$18-30 | US$9-15 |
| 500 | US$225-375 | US$90-150 | US$45-75 |
| 2.000 | US$900-1.500 | US$360-600 | US$180-300 |

`f` = 40% es **mi supuesto**, no un dato: hay que medirlo con `scripts/news_coverage.ts` (existe según la revisión de compliance) sobre la cartera real antes de decidir.

Palancas para bajar el costo [I]:
1. Solo tickers con al menos N tenedores activos y que abrieron la app en los últimos 7 días.
2. TTL de 24 h en días hábiles; tickers "quietos" cada 48-72 h.
3. Un tope mensual (circuit breaker) en `app_config`: al superarlo, el feed cae a GDELT/EDGAR y no a ninguna fuente prohibida.
4. Limitar a 1 búsqueda por consulta (la API de Responses tiene un tope de llamadas a herramientas; **no verifiqué el nombre del parámetro ni que aplique a `web_search`**).
5. Mapear CEDEAR -> subyacente: una sola búsqueda sirve a ambos tickers.

---

## 5. Otras vueltas baratas

- **GDELT bien usado.** [H] La página "About" dice que los datasets son de "uso ilimitado y sin restricciones para cualquier uso académico, comercial o gubernamental" y que cada uso lleve una cita y un link a GDELT (según un blog que lo cita): https://gdeltproject.org/about y https://blog.gdeltproject.org/?p=3976 (**no leído en la fuente**). [H] El DOC 2.0 responde 429 "una cada 5 segundos": https://blog.gdeltproject.org/gdelt-doc-2-0-api-debuts/ y fuentes de terceros que reportan tasas altas de rechazo en la práctica. Cuidado: **GDELT Cloud es otro producto comercial con otros términos** (gratis = evaluación, sin mostrar a terceros): https://gdeltcloud.com/terms. Para no mezclar, la atribución y el endpoint deben ser los del proyecto abierto.
  - [I] Cuentas: a 1 pedido cada 5,5 s caben ~15.700 pedidos/día; 2.000 tickers en una pasada diaria ocupan ~3 h. El límite no es el problema con caché compartida; sí lo son el 429 intermitente y la cobertura. Mejoras: buscar por **nombre de empresa + variantes** (no solo el ticker), con filtro de idioma (`sourcelang:spanish`) y país para .BA; consultas con `OR` para varios nombres; reintento con espera y *backoff*; una sola IP de salida programada (cola) en vez de pedidos desde cada usuario.
- **Brave Search API.** [H] Los términos (actualizados 1/9/2026, según un resumen) prohíben guardar resultados salvo almacenamiento transitorio sin un plan con derechos de almacenamiento; hay un plan con almacenamiento desde ~US$26/mes en un listado; la tarifa estándar ronda US$4-5 por 1.000 consultas: https://www.activepieces.com/blog/brave-search-api-pricing-plans-limits-cost-2026 y https://www.trustradius.com/compare-products/brave-search-api [M]. Hay demandas de editores (News Corp, NYT) contra Brave según esas fuentes. **Descartado** como fuente: caché compartida es justo lo que prohíben.
- **Google Custom Search JSON API / Bing.** [H] Bing Search API retirada el 11/8/2025: https://learn.microsoft.com/en-us/lifecycle/announcements/bing-search-api-retirement. Google Custom Search cerrada a clientes nuevos y con fin el 1/1/2027: https://brave.com/learn/google-api-shutdown/ [M, de un competidor]. **No son opción.**
- **Common Crawl / CC-NEWS.** [H] Hay una carta de la News/Media Alliance (29/4/2026) pidiendo prohibir usos de IA: https://www.newsmediaalliance.org/nma-letter-to-common-crawl/. Es un lote offline, sin frescura. **Descartado.**
- **Feeds RSS de medios de la allowlist.** **No leí los términos de ninguno.** [I, de conocimiento general, a confirmar] Muchos medios licencian sus RSS solo para lectura personal/no comercial; los feeds por ticker son poco comunes. Para usarlos hay que leer **medio por medio** y quedarse solo con los que lo permitan por escrito (patrón que ya pide la condición C de la revisión previa). Es trabajo manual, con retorno bajo hasta que se conozca la lista concreta.

---

## 6. Qué cobertura gana cada mercado

| Mercado | Hoy | Con la combinación |
|---|---|---|
| EE. UU. acciones/ETF | GDELT | + EDGAR (comunicados oficiales) + OpenAI si GDELT vacío |
| CEDEAR (.BA) | GDELT flojo | Mapeo al subyacente -> capas 0, 1 y 2 sobre el ticker de EE. UU. [I] |
| Acciones .BA locales | GDELT flojo | GDELT por nombre + filtro es/AR; OpenAI con allowlist argentina; BYMA hechos relevantes si los términos lo permiten |
| Cripto | GDELT flojo | GDELT por nombre de la moneda + OpenAI. No encontré una fuente gratis con licencia comercial confirmada |
| Europa/otros | GDELT | GDELT + OpenAI; EDGAR solo para ADR |

---

## 7. Riesgos de licencia y qué decide el usuario

**Riesgos** (de mayor a menor):
1. Ningún término fue leído completo (ver aviso). Es el riesgo principal de este informe.
2. OpenAI `web_search`: el contenido de las notas es de terceros; el control legal es la allowlist + citas visibles + mostrar solo titular/medio/fecha/link.
3. GDELT: atribución exigida y estabilidad; los derechos de las notas no son de GDELT.
4. Imágenes: sin cambio respecto de la revisión del 22/11 (hotlink de `og:image`, abogado, interruptores).
5. Newswires y RSS de medios: sin base confirmada; no usar hasta leer.

**Decide el usuario:**
1. **Habilitar los hosts** en la red de la sesión (o leer vos) para que se revisen: https://marketaux.com/tos, https://www.stockdata.org/terms, términos de OpenAI, política de reuso de sec.gov, términos de BYMA y de GDELT. Sin eso, queda "no leído".
2. **Tope mensual de OpenAI para noticias** (propongo empezar en US$50-100 con circuit breaker) y el N mínimo de tenedores por ticker.
3. Si se **escribe a BYMA** (y eventualmente a Marketaux) para confirmar por escrito el uso comercial. Yo no contacto a nadie.
4. Mantener la decisión de que Finnhub y Yahoo no vuelven (revisión 22/11).
5. Cuándo pasar a un proveedor pago: señal sugerida, `f` sostenido > 50% o costo de búsqueda > un % acordado del ingreso por suscripción (dato de ingresos: no lo tengo).

---

## Implicancias para Porty
- Armar capas en este orden: caché compartida -> EDGAR -> GDELT por nombre -> OpenAI con tope. Ninguna usa una fuente descartada por licencia.
- Mapear CEDEAR al subyacente de EE. UU. antes de buscar noticias; es la mejora de cobertura más barata.
- Medir `f` (porcentaje de tickers que quedan sin titulares) en la cartera real antes de fijar el presupuesto de OpenAI; hoy el rango es de US$18 a US$1.500/mes según escala y supuestos.
- Aceptar de OpenAI solo citas con dominio en la allowlist y tomar el titular de la cita, no del texto del modelo.
- No sumar Marketaux, NewsData.io, StockData ni newswires hasta que alguien lea sus términos.

## Confianza
**Baja-media.** Hechos de precios y límites con fragmentos consistentes (media); licencias de uso comercial **sin leer en la fuente** (baja); costos de OpenAI dependen de supuestos propios y de reportes de facturación mayor a lo listado (media-baja).
