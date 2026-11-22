# Revisión de compliance: Noticias, fotos de las notas, fuentes de respaldo y copy nuevo

**Fecha:** 2026-11-22 · **Autor:** porty-compliance (no es asesoramiento legal)
**Rama:** `claude/hopeful-babbage-mqjnr6` · **Revisión previa:** `docs/legal/reviews/2026-11-21-brief-diario-medios-y-youtube.md`
**Alcance:** `supabase/functions/_shared/news_fallback.ts`, `_shared/gdelt.ts`, `daily-brief/contract.ts` y `handler.ts`; `lib/presentation/shared/widgets/news_image.dart`, `lib/features/news_feed/view/`, `lib/features/daily_brief/view/`; claves `news_*`, `daily_brief_*`, `home_*`, `brief_*` de `assets/translations/es-ES.json` y `en-US.json`; páginas publicadas `porty-web/src/pages/app/terminos.astro` y `privacidad.astro`.

## Veredicto

| # | Punto | Veredicto | ¿Bloquea el lanzamiento? |
|---|---|---|---|
| 1 | Fotos de las notas por hotlink | **Ok con cambios** | Sí, el general, hasta cerrar 1.1, 1.2 y 1.3. La lista interna no. |
| 2a | Finnhub `company-news` | **No** | **Sí, el deploy.** Hoy no hay licencia para esto. |
| 2b | Yahoo `v1/finance/search` | **No** | **Sí, el deploy.** |
| 3 | Copy con voz de Porty | **Ok con cambios** | Solo 3.1 (rótulo de IA, ya bloqueaba en la revisión anterior). El resto no. |
| 4 | Cláusulas publicadas en porty-web | **No cubren las fotos** | Se suman dos líneas (sección 4). |

**Requiere abogado: sí.** Fotos de prensa en una app comercial (1), licencia de datos a pedir por escrito a un proveedor (2) y alcance del art. 50 del AI Act (3.1).

## Qué pude y qué no pude verificar

- No pude abrir `finnhub.io`, `legal.yahoo.com` ni `gdeltproject.org`: el entorno no resuelve esos hosts. Los términos de Finnhub y de Yahoo **no los leí en la fuente**. Me apoyo en fragmentos de búsqueda, en el repo y en mi revisión del 05/11 (`.claude/agent-memory/porty-compliance/project_widget_news_licensing.md`), donde sí tuve el resumen de los términos de Finnhub.
- Confianza: **media** en Finnhub (el repo y dos fuentes coinciden), **media** en Yahoo (fuentes secundarias más una decisión previa del proyecto), **baja** en fotos (criterio conservador; no hay norma que lea con certeza).
- Sin git en esta sesión: no pude distinguir qué claves son nuevas. Revisé todas las de `news_*`, `daily_brief_*`, `brief_*`, `today_card_*`, `market_today_*` y `home_*` relacionadas con el brief.

---

## 1. Fotos de las notas (`image_url`)

**Lo que hace el código.** Guarda solo la URL (https, hasta 500 caracteres, sin credenciales; `safeImageUrl`) en la caché compartida y en el payload del brief (14 días). La app la carga con `NetworkImage` desde el servidor del medio o del proveedor, sin descargarla ni reencodarla en nuestros servidores. Si falla, se retira sola. La nota principal lleva el chip "Foto: {medio}".

**Lo que está bien.** No hay copia ni proxy propio (es lo que más baja el riesgo). Solo https. Sin imagen no hay hueco. Las capturas de prueba (`news_screenshots_test.dart`) usan imágenes sintéticas, no fotos reales.

**El riesgo de fondo.** Titular, medio, fecha y link son datos. Una foto es una obra protegida, y su titular suele ser una agencia o un fotógrafo, no el medio. Mostrar la imagen social (`og:image`) dentro de una app que cobra suscripciones no está cubierto por "enlazar y citar". Hay un argumento a favor: el medio publica esa imagen justamente para que se vea al compartir la nota (licencia implícita para vista previa). Es un argumento, no una autorización, y para prensa europea se suma el derecho de los editores (Directiva 2019/790, art. 15, que incluye fotografías de publicaciones de prensa). El hotlink ayuda: no copiamos. Pero que un tribunal lo trate como "no es copia" depende de la jurisdicción, y no lo puedo confirmar acá. **Abogado: sí.**

[CORREGIR, bloquea el lanzamiento general] 1.1 `news_photo_credit` "Foto: {source}" atribuye una autoría que no sabemos
Por qué: el chip dice que la foto es del medio. Si es de una agencia (Getty, AP) o la sirve Yahoo, el pie afirma algo falso y además sugiere un acuerdo con el medio que no existe. La Directiva 2019/790 y los términos de los medios piden no sugerir respaldo; el art. 4 de la Ley 24.240 pide información cierta.
Texto propuesto (clave `news_photo_credit`):
- es: "Imagen de la nota de {source}"
- en: "Image from the {source} article"
Revisión humana: no.

[CORREGIR, bloquea el lanzamiento general] 1.2 No hay forma de apagar las imágenes por medio ni en conjunto
Por qué: si un medio o una agencia reclama, hoy hay que desplegar. El pedido de retiro que ya prometen los Términos ("10 días hábiles") necesita una acción rápida. La app ya oculta la foto cuando `image_url` no viene, así que alcanza con el servidor.
Cambio: en una migración nueva (no se edita la existente), un flag global en `app_config` (`news_images`: `on`/`off`) y una columna `show_images boolean` en `news_source_allowlist`. Para agencias y medios con foto de agencia (por ejemplo Reuters, AP, Bloomberg), arrancar en `false` hasta que una persona lea los términos del medio (condición C de la revisión anterior, con un punto más: "imágenes"). El servidor deja `image_url` vacío si el flag está apagado, y también para las notas viejas de la caché. Dueño: `porty-backend-dev`.
Revisión humana: no (la lista de medios con imagen sí la aprueba el usuario).

[CORREGIR, bloquea el lanzamiento general] 1.3 Términos y Privacidad no mencionan las imágenes
Por qué: ver sección 4. La frase "Porty no reproduce las notas" (Términos) deja de ser completa si se muestra la foto, y el pedido a un tercero de la IP al cargar la imagen no figura en Privacidad.
Texto propuesto: sección 4.
Revisión humana: sí.

[SUGERENCIA] 1.4 El host de la imagen puede ser cualquiera
Por qué: `safeImageUrl` solo exige https; el servidor de la imagen no tiene que ser el del medio. Puede ser un CDN, un servicio de miniaturas o, en el peor caso, un host de seguimiento. Cada host ve la IP y el dispositivo del usuario.
Cambio: un script de medición (como `scripts/news_coverage.ts`) que liste los hosts de imagen más frecuentes; revisarlos una vez y descartar los que sean de publicidad o seguimiento. Dueño: `porty-backend-dev`.
Revisión humana: no.

[SUGERENCIA] 1.5 Las fotos no salen de las pantallas de noticias
Regla: ninguna foto de una nota en push, widget de pantalla de inicio, ficha de las tiendas, anuncios, ni publicaciones de redes. Las capturas de marketing y de la ficha usan imágenes sintéticas **y medios ficticios**: hoy los fixtures atribuyen titulares inventados a "Reuters" (`test/fixtures/daily_brief/*.json`). En una captura pública eso es atribuir un titular falso a un medio real. Aviso a `porty-aso-specialist` y `porty-social-media`.
Revisión humana: no.

---

## 2. Fuentes de respaldo nuevas

**Qué hace el código.** Cuando GDELT falla o no trae nada de las últimas 48 h para un ticker (`headlinesByTicker`, `gdelt.ts:429-466`), llama a Finnhub `company-news` (solo tickers de EE. UU.) y, si no alcanza, a Yahoo `v1/finance/search`. Filtra por `news_source_allowlist` (activos). Guarda título, medio, fecha, link e `image_url` en la caché compartida y en el payload del brief que ven todos los usuarios.

### 2a. Finnhub: **No** (bloquea el deploy)

- **Plan.** El proyecto está en el **plan gratuito** (`docs/ops/gastos.md:19`: "US$0 hoy (plan gratis)"); no hay contrato ni plan pago en el repo. `FINNHUB_API_KEY` es un secreto de Supabase, así que el plan real solo lo confirma el usuario en su cuenta de Finnhub.
- **Licencia.** La página de precios de Finnhub (según el resultado de búsqueda) marca **Free y All-In-One como "Personal Use. Terms apply"**: https://finnhub.io/pricing. Otras fuentes dicen que el uso comercial o mostrar los datos a clientes exige un contrato Enterprise por consulta: https://massive.com/compare/massive-vs-finnhub (es un competidor; peso bajo) y https://apicostcalc.com/finnhub.html. En mi revisión del 05/11 anoté de los términos (https://finnhub.io/terms-of-service) que **no permiten redistribuir datos ni resultados derivados**.
- **Coherencia con el proyecto.** `docs/runbooks/news-sources-v2.md:3` dice que se reemplazó "Finnhub free ... que no permiten uso comercial" y la memoria del architect registra "Finnhub prohibido por licencia". Este cambio **vuelve a meterlo** en el camino de noticias, ahora con imagen, y el resultado se guarda en `data_cache` y en `daily_briefs.payload` (14 días) para todos los usuarios: eso es redistribuir.
- **El filtro por nombre es más débil que el de dominio.** Cuando el link es un redirect de `finnhub.io`, la nota se acepta si el campo `source` coincide con el nombre de un medio permitido. Eso lo dice el proveedor, no lo verificamos: la nota puede terminar en otro dominio que no habilitamos. La allowlist es nuestro control legal principal, y acá se salta.
- **Atribución.** El pie del widget dice "Titulares vía GDELT Project" (`home_widget_sheet_legend`): con el respaldo sería inexacto.

Cambio concreto: sacar la llamada a `finnhubNews` de `headlinesByTicker` (o dejarla detrás de un flag que arranque apagado, sin camino a producción) hasta tener una licencia **por escrito** que permita mostrar titular, imagen y link a usuarios de una app de pago. Esa licencia la pide el usuario a Finnhub (Enterprise) o a otro proveedor con licencia comercial. En el plan del informe semanal (`docs/runbooks/weekly-report.md:210`) ya figuraba Marketaux como alternativa; **no leí sus términos**, hay que revisarlos antes de proponerlo. Revisión humana: sí. Dueño: `porty-backend-dev`.

### 2b. Yahoo `v1/finance/search`: **No** (bloquea el deploy)

- No hay API oficial de noticias de Yahoo Finance; el endpoint es el de la web. Para llamarlo, `yahoo_session.ts` obtiene cookie y `crumb` de `fc.yahoo.com` y manda un **User-Agent de Chrome en macOS**, es decir, se hace pasar por un navegador.
- Los términos de la API de Yahoo (https://legal.yahoo.com/us/en/yahoo/terms/product-atos/apiforydn/index.html; **no la pude abrir**) son, según fuentes secundarias, restrictivos con ingresos sin permiso escrito y con la recolección automatizada fuera de sus APIs. `docs/runbooks/news-sources-v2.md:3` ya había descartado "el uso de Yahoo para noticias" por no permitir uso comercial. Esa decisión no cambió.
- La miniatura de Yahoo está alojada por Yahoo (copia redimensionada propia), no por el medio. Eso agrega a la nota un tercero con derechos sobre la imagen.
- Ya hay otros usos de Yahoo (precios, gráficos) marcados como "sin uso comercial" en el runbook. Es un tema aparte, que sigue abierto; no lo agrava esta revisión, pero tampoco lo cierra.

Cambio concreto: igual que 2a, sacar `yahooNews` del respaldo. Sin Finnhub ni Yahoo el respaldo se reduce a: lo que ya trae GDELT, y los titulares que citan la búsqueda web de OpenAI (las citas visibles y clicables que OpenAI exige; ver `news-sources-v2.md`, sección de monitoreo). Si hay cobertura insuficiente por ticker, es una decisión de producto: se resuelve con una fuente licenciada, no con una de estas dos. **Aviso a `porty-product-owner`**: este cambio recorta el alcance de la cobertura por ticker (los casos NFLX y AMZN que motivaron el respaldo vuelven a salir vacíos hasta tener fuente licenciada). Revisión humana: sí.

---

## 3. Copy nuevo con voz de Porty

**Bien:** buscando imperativos de compra o venta, "te recomiendo", garantías, urgencia y conectores causales ("por qué", "debido a", "gracias a") en `news_*`, `daily_brief_*`, `brief_*`, `today_card_*`, `market_today_*` y `home_*`, **no hay ninguno** en es ni en en. Lo que ya está bien y hay que mantener: `news_porty_mine` ("Ordené primero lo que toca tu cartera": dice lo que hizo Porty, no que sea importante), `daily_brief_earnings_estimated` ("presentaría", con "estimada"), `home_widget_sheet_legend` ("no los escribo ni los recomiendo"), `news_topic_media_highlights` ("Titula: ..."), `daily_brief_teaser_premium` (ya corregido, H6b) y las frases de `home_widget_phrase_*` (aporte aritmético, no causa).

[CORREGIR, bloquea el lanzamiento general] 3.1 `news_ai_notice` y `news_ai_notice_short`: dicen "automático", no "IA"
Por qué: en la revisión anterior (H6) propuse "hecho con IA". "Automático" no dice que lo escribió un modelo de lenguaje, y ese es el dato que el usuario necesita y que apunta a pedir el art. 50 del AI Act (https://eur-lex.europa.eu/eli/reg/2024/1689/oj; alcance y fecha sin confirmar). El pie está bien ubicado: en cada capítulo del brief, en Mercado hoy, en el feed y en el tema.
Texto propuesto:
- `news_ai_notice` es: "Resumen hecho con IA a partir de las fuentes citadas; puede tener errores. Información, no una recomendación."
- `news_ai_notice` en: "AI-generated summary based on the cited sources; it may contain errors. Information, not a recommendation."
- `news_ai_notice_short` es: "Resumen hecho con IA" · en: "AI-generated summary"
Revisión humana: sí (alcance del art. 50).

[CORREGIR] 3.2 `news_videos_empty` promete un aviso que no existe
Por qué: "Todavía no hay videos nuevos. Te aviso cuando haya." No encontré ninguna notificación de videos (`notify-dispatch` y `daily-jobs` no los tratan). Es una promesa que el producto no cumple (art. 4 de la Ley 24.240).
Texto propuesto: es "Todavía no hay videos nuevos." · en "No new videos yet."
Revisión humana: no.

[CORREGIR] 3.3 "¿Cómo me afecta?" (`news_feed_how_affects`, `daily_brief_how_affects`) y su pregunta al asistente (`news_ask_affects`, `daily_brief_ask_affects`)
Por qué: el botón promete un análisis del efecto de la nota sobre la cartera y la pregunta lo manda tal cual al asistente. La respuesta natural es una predicción o una causa, que es lo que el brief evita por diseño. Conviene pedir lo que sí se puede responder con datos: qué tiene que ver la nota con lo que el usuario tiene.
Texto propuesto:
- Botón es: "¿Qué tiene que ver con lo mío?" · en: "What does this have to do with my portfolio?"
- Pregunta es: "¿Qué tiene que ver esta noticia con mi cartera: {title}?" · en: "What does this news have to do with my portfolio: {title}?"
- Agregar un caso de evals (`test/evals/`): la respuesta no afirma causa ni predice precio, ni recomienda.
Revisión humana: no. Dueño: `porty-flutter-dev` y `porty-assistant-dev` (el cambio de eval va en un PR aparte, según las reglas del repo).

[CORREGIR] 3.4 `home_benchmark_ahead` / `_behind` / `_tie`: "Le ganaste al S&P 500 por {points} puntos."
Por qué: "ganaste" y "quedaste debajo" convierten una comparación en un resultado de habilidad. "Puntos" es ambiguo (¿porcentuales o del índice?) y no dice el período. Si hay aportes y retiros durante el período, la comparación con un índice puede ser engañosa. S&P 500 es marca de S&P Dow Jones Indices (usarla para identificar el índice es normal; no sugerir respaldo).
Texto propuesto:
- ahead es: "Tu cartera rindió {points} puntos porcentuales más que el S&P 500 en este período." · en: "Your portfolio returned {points} percentage points more than the S&P 500 over this period."
- behind es: "... {points} puntos porcentuales menos que el S&P 500 en este período." · en: "... {points} percentage points less than the S&P 500 over this period."
- tie es: "Tu cartera rindió casi lo mismo que el S&P 500 en este período." · en: "Your portfolio returned about the same as the S&P 500 over this period."
- Debajo del bloque, la línea ya existente de "El rendimiento pasado no garantiza resultados futuros", o un toque para ver cómo se calculó.
Revisión humana: no (sí si el cálculo no ajusta por aportes; avisar a `porty-flutter-dev`).

[SUGERENCIA] 3.5 `news_topic_porty` y `news_topic_porty_following`: "te aviso en tu brief cuando pase algo acá"
Por qué: "cuando pase algo" promete vigilancia completa de un tema. El brief solo lo incluye si hay notas de fuentes permitidas, y no sale los días sin mercado abierto.
Texto propuesto: es "Seguilo y lo incluyo en tu brief." / "Está incluido en tu brief." · en "Follow it and I'll include it in your brief." / "It's included in your brief."

[SUGERENCIA] 3.6 `home_porty_entry_subtitle`: "cualquier acción"
Por qué: la cobertura depende de los proveedores y de los tickers que resuelven. "Cualquier" es un claim absoluto.
Texto propuesto: es "Sobre tu cartera, una acción o tus metas, con tus datos reales." · en "About your portfolio, a stock or your goals, with your real data."

[SUGERENCIA] 3.7 `daily_brief_section_signals` / `brief_chapter_heads` ("Para tener en cuenta")
Se acepta mientras las señales sean descriptivas (por ejemplo `daily_brief_signal_concentration`: "{ticker} pesa {pct} de tu cartera."). Regla: si una señal pasa a decir "demasiado concentrado" o "conviene", vuelve a compliance.

---

## 4. ¿Cubren las fotos las cláusulas publicadas en porty-web?

**No.** Leí `terminos.astro` y `privacidad.astro` (los de `/app/terminos` y `/app/privacidad`).

- **Términos, sección "Noticias, resúmenes y videos de terceros".** Dice que se muestran "títulos, nombres de medios, fechas y enlaces", que "Porty no reproduce las notas" y que los contenidos pertenecen a sus titulares, con casilla de retiro y 10 días hábiles. No nombra imágenes. La frase "no reproduce las notas" deja de ser exacta si se muestra una foto de la nota. El resto (marcas, sin vínculo con los medios, retiro) **sí sirve** y se reutiliza.
- **Privacidad.** Cubre OpenAI, YouTube (miniaturas y reproductor) y "Finnhub y Yahoo Finance" como proveedores de mercado que reciben tickers. No dice que los servidores de los medios o sus CDN reciben la IP del usuario al cargar la imagen. Con 2a y 2b resueltos, la mención de Finnhub y Yahoo se mantiene solo para precios y logos.

Líneas propuestas (borrador; no se editó porty-web). **Revisión humana: sí.**

**Términos**: en el primer párrafo de la sección, cambiar "Porty no reproduce las notas" por "Porty no reproduce el texto de las notas", y agregar un párrafo:

> Algunas notas se muestran con la imagen que el propio medio publica para esa nota. Porty no guarda copias de esas imágenes en sus servidores: se cargan directamente desde los servidores del medio o de su proveedor de contenidos. Las imágenes pertenecen a sus titulares (el medio, una agencia o un fotógrafo) y Porty no las licencia. Si sos titular y querés que no mostremos una imagen, escribinos a {takedown} y te respondemos dentro de los 10 días hábiles.

> *(en)* Some articles are shown with the image the outlet itself publishes for that article. Porty does not keep copies of those images on its servers: they load directly from the outlet's servers or its content provider's. The images belong to their owners (the outlet, an agency or a photographer) and Porty does not license them. If you own an image and don't want us to show it, write to {takedown} and we will reply within 10 business days.

**Privacidad**: al final de "Brief diario, noticias y resúmenes con IA":

> Algunas notas muestran una imagen. Tu dispositivo la descarga directamente de los servidores del medio o de su proveedor de contenidos, que pueden ver tu dirección IP y el tipo de dispositivo. Porty no recibe esos datos ni los envía, y no guarda la imagen: solo guardamos su dirección web por hasta 14 días junto con el brief.

> *(en)* Some articles show an image. Your device downloads it directly from the outlet's servers or its content provider's, which may see your IP address and device type. Porty does not receive or send that data and does not store the image: we only keep its web address for up to 14 days along with the brief.

Nota de redacción: el listado "Con quién los compartimos" empieza con "Solo con proveedores que los procesan por cuenta nuestra". Los servidores de los medios no son proveedores nuestros, así que la frase va en el párrafo y no en la lista.

Privacy labels de Apple y Data safety de Google: sumar a lo ya pendiente por YouTube (H8 de la revisión anterior) que servidores de terceros reciben la IP al mostrar imágenes de notas. Revisión humana: sí.

---

## 5. Qué decide el usuario

1. **Finnhub y Yahoo.** Confirmar que salen del respaldo (2a y 2b) y si se pide una licencia por escrito a Finnhub (Enterprise) o a otro proveedor. La pide el usuario; yo no contacto a nadie.
2. **Plan de Finnhub.** Confirmar en su cuenta cuál es el plan real de `FINNHUB_API_KEY`.
3. **Fotos.** Aprobar el interruptor global y por medio (1.2) y qué medios arrancan con imagen apagada.
4. **Abogado.** Sumar a la consulta ya pendiente (R1, R2, R3): fotos de prensa por hotlink, y el alcance del art. 50 para el rótulo de IA.
5. **Textos.** Aprobar 1.1, 3.1 a 3.4 y las líneas de la sección 4.

## Orden sugerido

1. Antes de cualquier deploy: sacar Finnhub y Yahoo del respaldo (2a, 2b).
2. Antes del lanzamiento general: 1.1, 1.2, 1.3, 3.1 (y 3.2 a 3.4, que son de copy y cuestan poco).
3. Después: 1.4, 1.5, 3.5 a 3.7.
