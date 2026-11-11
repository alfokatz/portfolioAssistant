# Anuncios de Porty con Sunra: instrucciones y prompts para Claude Code

Objetivo: generar con Sunra los anuncios de Porty (Instagram, TikTok, Facebook Ads) y compararlos con los armados a mano en diseño. Primero una prueba chica; no gastes créditos en todo de una.

## 0. Antes de empezar

- Leé `PRODUCT.md` y `DESIGN.md` del repo (marca, tokens y anti-referencias). Respetalos siempre.
- Si algo de este documento choca con el código o con esos docs, mandan el código y los docs: avisame la diferencia.
- NUNCA escribas la API key de Sunra en el código, en archivos versionados ni en logs. Si hace falta, usá la variable de entorno `SUNRA_KEY` y agregá `.env`, `out/` y `ads-out/` al `.gitignore`. El repo es público.

## 1. Referencias del avatar (obligatorio)

Sin imagen de referencia, los modelos deforman a Porty (cambian la forma y la cara). Prepará referencias desde los SVG oficiales:

- `assets/porty-avatar/states/porty_idle.svg` (reposo, sonrisa leve)
- `assets/porty-avatar/states/porty_concerned.svg` (preocupado, boca plana)
- `assets/porty-avatar/states/porty_thinking.svg` (con destello de 4 puntas)
- `assets/porty-avatar/states/porty_answered.svg` (sonrisa amplia)

Renderizalos a PNG de 1024x1024 sobre fondo marfil `#FBFBFA` (por ejemplo con `cairosvg`; `pip install cairosvg --break-system-packages` si falta) y subilos para usarlos como `image_urls`. El PNG de `assets/porty-avatar/splash/porty_splash.png` mide solo 256 px: usalo solo si no podés renderizar los SVG.

Orden de referencias en cada pedido: (1) idle, (2) concerned, (3) thinking, (4) answered. En cada prompt se indica cuál usar.

## 2. Cómo conectar Sunra

Opción A (preferida): MCP o CLI de Sunra con inicio de sesión en el navegador, sin API key.

- Instalar: `npm i -g @sunra/cli@0.3.2` y después `sunra login`.
- Verificar: `sunra balance` y `sunra tools`. Usá `--help` para ver los parámetros reales; no asumas flags.
- Si Sunra está conectado como MCP, los IDs de modelo del catálogo son: `nano-banana-2.1`, `ideogram-v4.5`, `gpt-image-2.5-flare`, `nano-banana-pro`, `seedream-5-pro`, `flux-3-image`.

Opción B (API): `npm i @sunra/client`, key en `SUNRA_KEY`. Los IDs de la API NO coinciden con los del catálogo. El único ID de API que verifiqué es `black-forest-labs/flux-kontext-pro/text-to-image`. Buscá el resto en https://docs.sunra.ai y no inventes IDs.

## 3. Modelos y costos aproximados (créditos por imagen, vía MCP)

| Modelo | Costo | Cuándo |
|---|---|---|
| `gpt-image-2.5-flare` (calidad media) | 1 (2 con referencia) | Iterar rápido composiciones |
| `nano-banana-2.1` (1K o 2K) | 4 a 5 | Primera opción: buen texto, hasta 14 referencias |
| `ideogram-v4.5` (calidad media) | 6 | Si el texto en español sale mal con los otros |

El saldo de la cuenta es bajo. Antes de generar:
1. Mirá el saldo (`sunra balance`) y estimá el costo total.
2. Mostrame el costo y esperá mi OK.
3. Primera tanda: SOLO los anuncios 1, 2 y 7 en feed (4:5), con `nano-banana-2.1`. Si alcanza, seguí con el resto.

Los modelos generan a ~2K en 4:5 y 9:16. Hay que reescalar a 1080x1350 (feed) y 1080x1920 (story, reel, TikTok) al exportar.

## 4. Bloque de estilo común (pegarlo al inicio de cada prompt)

```
Calm editorial advertising piece for a mobile investing app, in the spirit of Notion or Linear: lots of air, clear hierarchy, maximum 3 main elements. Flat warm ivory background #FBFBFA. Text color charcoal #2F3437, secondary text warm gray #787774. A single accent color: terracotta #D98E5D. Profit green #346538 and loss red #9F2F2D only on numbers. Typography: Plus Jakarta Sans style geometric sans-serif, bold headlines with slightly negative letter-spacing (no inflated letters, no comic or script fonts). White #FFFFFF cards with a very thin 8% gray border and ~16px radius, no heavy shadows, no gradients, no glossy 3D. Small hand-drawn details (underline, sparkle) in terracotta, used sparingly. Mascot "Porty": use the attached reference images EXACTLY as the mascot: a slightly irregular soft terracotta pebble with no body, no arms and no hands, two dark charcoal oval eyes and a thick rounded gentle curved smile. Do NOT redraw, restyle, symmetrize or deform it; only scale or crop it. All text in Rioplatense Spanish with correct spelling and every accent. Render ONLY the quoted text, no extra words, no logos. Forbidden: coins, dollar-sign symbols, rockets, charts that only go up, gold bars, bulls, cash, neon, gradients, stock photos.
```

## 5. Reglas de formato

- Feed: relación 4:5 (1080x1350).
- Story, reel, TikTok: relación 9:16 (1080x1920). Dejá libre de elementos clave los 250 px de arriba y los 340 px de abajo (la interfaz de Instagram y TikTok los tapa).
- Agregá siempre al final del prompt: `Format: <Instagram feed 4:5 | vertical story 9:16 with the top 13% and bottom 18% free of key content>.`

## 6. Prompts por anuncio

Cada prompt va después del bloque de estilo común (sección 4). Los textos entre comillas son EXACTOS.

### Anuncio 1: Por qué bajó

Referencias: 1 (idle), 2 (concerned).

```
Brand lockup at the top: small Porty avatar (reference 1) next to the word "Porty" in bold. Centered headline, two lines: "Tu cartera bajó." / "¿Por qué?" with a thin hand-drawn terracotta underline under "¿Por qué?". Below it a small gray line: "Porty te lo explica en criollo." Below, a modern smartphone mockup with thin frame and realistic tall proportions (about 1:2.1), cropped by the bottom edge of the image. On its ivory screen, a chat: a light gray user bubble aligned right with "¿Por qué bajé hoy?"; below it a reply in a white card with hairline border: "Bajaste 1,2% sobre todo por NVDA, que cayó tras su reporte. El resto está estable." where "NVDA" is inside a small rounded pill and "1,2%" is in deep red #9F2F2D. A small Porty avatar (reference 2, concerned mood) sits next to the reply. Under the reply, two small white suggestion chips: "¿Y el resto de mi cartera?" and "¿Qué pasó con NVDA?". Tiny gray caption: "Ejemplo ilustrativo".
```

### Anuncio 2: Calma

Referencias: 1 (idle).

```
Brand lockup at the top: small Porty avatar (reference 1) and "Porty". Centered headline: "Abrí. Mirá cómo vas. Cerrá." with a thin hand-drawn terracotta underline under "cómo vas." Below, gray line: "Tu cartera de un vistazo, sin ruido." Then a tall modern smartphone mockup (about 1:2.1), thin frame, cropped by the bottom edge. On its screen: gray label "Tu cartera"; big bold number "US$ 12.480"; below it "−0,4% hoy" in red and "+1,3% este mes" in green; a thin charcoal line sparkline that goes up and down (not only up) ending in a small terracotta dot; a row with a small Porty avatar (reference 1) and a white card saying "Día tranquilo. Nada raro en tu cartera."; a gray section label "Posiciones" followed by two editorial rows with hairline separators: "NVDA" (subtitle "Nvidia") with "−1,2%" in red, and "VOO" (subtitle "ETF · S&P 500") with "+0,4%" in green. Tiny gray caption: "Ejemplo ilustrativo".
```

### Anuncio 3: Sin jerga

Referencias: 1 (idle), 3 (thinking).

```
Brand lockup at the top: small Porty avatar and "Porty". Centered bold headline in two lines: "Preguntale lo que" / "no te animás a preguntar." with a thin hand-drawn terracotta underline under "no te animás". Below, three white pill-shaped question chips stacked and left-aligned, the first with a terracotta outline: "¿Qué es un ETF?", "¿Qué es un dividendo?", "¿Por qué cae el mercado?". Below them, a small Porty avatar (reference 1) next to a white card with the answer: "Un ETF es una canasta de acciones que comprás de una sola vez. Por ejemplo, el SPY sigue a las 500 empresas más grandes de EE. UU." At the bottom, a large Porty (reference 3, with the four-point sparkle) partly cropped by the bottom edge, with its full face visible. No phone mockup in this piece.
```

### Anuncio 4: Confianza

Referencias: 1 (idle).

```
Brand lockup at the top: small Porty avatar and "Porty". Very large bold centered headline in two lines: "No te dice" / "qué comprar." with a thick hand-drawn terracotta underline under "qué comprar." Below, gray line: "Te ayuda a entender lo que ya tenés." In the middle, a tilted pill-shaped sticker with gray text "¡Comprá ya!" crossed out by a terracotta strike line (the text must remain readable). At the bottom, a large smiling Porty (reference 1), centered and partly cropped by the bottom edge, face fully visible.
```

### Anuncio 5: Metas

Referencias: 1 (idle).

```
Brand lockup at the top: small Porty avatar and "Porty". Centered headline in two lines: "¿Vas en camino" / "a tu meta?" with a thin hand-drawn terracotta underline under "en camino". Gray line: "Contale qué querés lograr. Porty arma el plan." Then a tall modern smartphone mockup (about 1:2.1) cropped by the bottom edge. On its screen: a small Porty avatar (reference 1) beside a white card "Japón va en camino. El fondo de emergencia viene un poco atrasado."; then two goal rows with hairline separators: "Viaje a Japón" with "60 %" on the right, small gray line "US$ 2.400 de US$ 4.000 · abril 2027" and a thin charcoal progress bar filled 60%; "Fondo de emergencia" with "35 %", gray line "US$ 1.050 de US$ 3.000 · atrasada" and a progress bar filled 35%; then a small line "Entre todas: US$ 3.450 de US$ 7.000". Tiny gray caption: "Ejemplo ilustrativo".
```

### Anuncio 6: Conectá tu cuenta

Referencias: 1 (idle).

```
Brand lockup at the top: small Porty avatar and "Porty". Centered headline in two lines: "Tu cartera de eToro," / "sin cargar nada." with a thin hand-drawn terracotta underline under "sin cargar nada." Gray line: "Conectá tu cuenta. Solo lectura." Then a tall modern smartphone mockup (about 1:2.1) cropped by the bottom edge. On its screen: bold title "Conectá tu cuenta de eToro"; gray paragraph "Porty trae tus posiciones y las mantiene al día, así no tenés que cargarlas a mano."; a full-width charcoal button with ivory text "Conectar eToro"; small gray text "Solo lectura"; below, a white card with a terracotta circle containing a white check mark, bold "12 posiciones importadas" and gray "Se actualizan solas." Do NOT draw any eToro logo, only the word in text. Tiny gray caption: "Ejemplo ilustrativo".
```

### Anuncio 7: Concentración

Referencias: 1 (idle), 2 (concerned).

```
Brand lockup at the top: small Porty avatar and "Porty". Centered headline in two lines: "¿Estás muy" / "concentrado?" with a thin hand-drawn terracotta underline under "concentrado?" Gray line: "Porty te avisa cuando un sector pesa demasiado." Then a tall modern smartphone mockup (about 1:2.1) cropped by the bottom edge. On its screen: gray label "Tu cartera por sector"; four horizontal bar rows with the name on the left and the percentage on the right: "Tecnología" "62 %" with a terracotta bar, "Finanzas" "18 %", "Salud" "12 %", "Consumo" "8 %" with light gray bars (bars proportional to the numbers); below, a small Porty avatar (reference 2, concerned) beside a white card with bold "Tecnología pesa 62 % de tu cartera." followed by regular "Porty te lo marca cuando un sector supera el 40 %." Tiny gray caption: "Ejemplo ilustrativo".
```

### Anuncio 8: Ideas según tu perfil

Referencias: 1 (idle).

```
Brand lockup at the top: small Porty avatar and "Porty". Centered headline in two lines: "Diversificá según" / "tu perfil." with a thin hand-drawn terracotta underline under "tu perfil." Gray line: "Porty te muestra ideas que le faltan a tu cartera." Then a tall modern smartphone mockup (about 1:2.1) cropped by the bottom edge. On its screen: gray label "Tu perfil de inversor" and three small white pills in one row: "Moderado", "Largo plazo", "Crecimiento"; a small Porty avatar (reference 1) beside a white card "Tus 6 posiciones son 100 % de EE. UU. Mirá qué le falta."; two white idea cards: first bold "ETF de acciones internacionales", gray "Suma empresas de otros países.", and a small pill with a terracotta dot "Buen encaje"; second bold "ETF de bonos", gray "Suma estabilidad a tu cartera.", pill "Encaje medio". Tiny gray caption: "Ejemplo ilustrativo. Información educativa, no es asesoramiento financiero." Do not write any specific ticker symbols.
```

### Anuncio 9: Registrá tus compras hablando

Referencias: 1 (idle), 4 (answered).

```
Brand lockup at the top: small Porty avatar and "Porty". Centered headline in two lines: "Registrá tus compras" / "hablando." with a thin hand-drawn terracotta underline under "hablando." Gray line: "Contale a Porty. Vos confirmás." Then a tall modern smartphone mockup (about 1:2.1) cropped by the bottom edge. On its screen: a light gray user bubble aligned right "Compré 5 VOO hoy"; a small Porty avatar (reference 4, answered) beside a white card "Listo, lo preparé. ¿Lo confirmás?"; below, a white card with three rows (label gray on the left, value bold on the right): "Operación" "Compra", "Activo" "VOO", "Cantidad" "5"; then a full-width charcoal button "Confirmar" and a gray text button "Cancelar". Tiny gray caption: "Ejemplo ilustrativo".
```

### Anuncio 10: Avisos

Referencias: 1 (idle).

```
Brand lockup at the top: small Porty avatar and "Porty". Centered headline in two lines: "Porty te avisa" / "solo cuando importa." with a thin hand-drawn terracotta underline under "solo cuando importa." Gray line: "Nunca más de 3 avisos automáticos por día." Then three stacked white push-notification cards with hairline borders and large radius, each with a small rounded app icon holding the Porty avatar (reference 1), a tiny gray header and a bold title and a gray body: "Porty · ahora" / "NVDA bajó de US$ 150" / "Tu alerta de precio se activó."; "Porty · 9:00" / "AAPL presenta resultados mañana" / "Después del cierre."; "Porty · sábado" / "Tu semana está lista" / "Mirá cómo te fue y qué viene." Tiny gray caption: "Ejemplo ilustrativo". At the bottom, a large smiling Porty (reference 1) partly cropped by the bottom edge, face fully visible.
```

## 7. Proceso a seguir

1. Preparar las referencias (sección 1) y conectar Sunra (sección 2).
2. Estimar costos y pedirme OK (sección 3). Primera tanda: anuncios 1, 2 y 7 en feed.
3. Generar. Si el modelo permite varias imágenes por pedido, pedí 2 variantes por anuncio para elegir.
4. Descargar cada resultado y revisarlo mirando la imagen (no asumas que salió bien). Si no podés abrir las imágenes, dame las URLs.
5. Revisar con esta lista y marcar OK o problema por pieza:
   - Avatar fiel: forma de guijarro irregular (no círculo perfecto), ojos ovalados, sonrisa curva, sin cuerpo ni manos.
   - Texto exacto: sin palabras inventadas, con todos los acentos y signos (¿ ?).
   - Paleta: marfil, carbón, un solo acento terracota; verde y rojo solo en números.
   - Nada de lo prohibido (monedas, cohetes, gráficos que solo suben, neón, degradados).
   - Cartel "Ejemplo ilustrativo" presente donde haya cifras.
   - Story: nada clave en los 250 px de arriba ni en los 340 px de abajo.
6. Si una pieza falla por el texto, hacé UN reintento con el mismo prompt cambiando de modelo (por ejemplo `ideogram-v4.5`) y, si sigue fallando, pedí la imagen sin texto y agregalo después en diseño. No entres en bucles de reintentos que gasten créditos.
7. Guardar todo en `ads-out/` con nombres como `ad01_por_que_bajo_feed_nano-banana-2.1.png` y un `log.md` con modelo, parámetros, costo y observaciones (sin ninguna key).
8. Entregarme una tabla comparativa: anuncio, modelo, costo, avatar OK, texto OK, comentarios. Si están los diseños manuales (sección 9), sumá una columna de comparación contra cada uno.

## 8. Notas legales y de producto

- Porty no recomienda comprar ni vender. Los anuncios hablan de "ideas" y "contexto educativo", nunca de "te recomienda comprar X". No cambies ese encuadre.
- Los números de los anuncios son de ejemplo: mantené el cartel "Ejemplo ilustrativo".
- Antes de pautar, conviene revisar con compliance o un abogado la publicidad de "sugerencias de inversión según tu perfil". No está verificado.
- Algunas funciones (noticias, resultados, informe semanal) dependen del plan Gold y de reemplazar fuentes de datos sin licencia comercial: en la landing deben figurar como "próximamente" hasta que estén listas.

## 9. Diseños manuales para comparar (NO usar como referencia)

Hay diseños hechos a mano de estos mismos anuncios, ya cargados en el repo. Sirven SOLO para comparar el resultado al final. Reglas:

- NO los pases a Sunra como `image_urls` ni los describas en el prompt de generación: el modelo los copiaría y la comparación no serviría. Las únicas referencias para generar son las del avatar (sección 1).
- Buscalos en el repo con un glob (`**/porty_*_feed.png` y `**/porty_*_story.png`). Los nombres siguen este patrón: `porty_<NN>_<nombre>_<feed|story>.png`.
- Si no los encontrás, preguntame la ruta. No sigas sin ellos: la comparación es opcional, la generación no depende de eso.

| # | Anuncio | Archivos |
|---|---|---|
| 1 | Por qué bajó | `porty_01_por_que_bajo_feed.png` / `_story.png` |
| 2 | Calma | `porty_02_calma_feed.png` / `_story.png` |
| 3 | Sin jerga | `porty_03_sin_jerga_feed.png` / `_story.png` |
| 4 | Confianza | `porty_04_confianza_feed.png` / `_story.png` |
| 5 | Metas | `porty_05_metas_feed.png` / `_story.png` |
| 6 | eToro | `porty_06_etoro_feed.png` / `_story.png` |
| 7 | Concentración | `porty_07_concentracion_feed.png` / `_story.png` |
| 8 | Perfil e ideas | `porty_08_perfil_ideas_feed.png` / `_story.png` |
| 9 | Registrar hablando | `porty_09_registrar_hablando_feed.png` / `_story.png` |
| 10 | Avisos | `porty_10_avisos_feed.png` / `_story.png` |

Al final, comparalos lado a lado (Sunra vs. manual) en estos puntos: fidelidad del avatar, exactitud del texto en español, respeto de la paleta, jerarquía y aire, y proporción del celular. Decime en cuáles gana cada enfoque y en cuáles conviene mezclar (por ejemplo, fondo generado con Sunra y texto agregado en diseño).