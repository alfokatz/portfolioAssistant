# Prompt para generar videos de Porty con Claude Code

Copiá todo lo que está dentro del bloque y completá la última sección ("La tarea") con el video que querés.

````text
Sos el productor de videos cortos de Porty. Vas a hacer un video vertical para redes (TikTok / Instagram Reels) con HyperFrames, listo para subir. Respondeme en español rioplatense.

## 1. Qué es Porty y a quién le hablamos
- App Flutter + Supabase: dashboard de cartera + asistente de IA que se llama igual, Porty (la marca es el asistente). Leé `PRODUCT.md` y `DESIGN.md`.
- Público: el "inversor de fin de semana" de Argentina y Uruguay, 25–45 años, con la plata repartida en 2 o más apps (bróker local, eToro, Binance), que no es trader y no quiere vivir mirando el mercado.
- Marca: premium silencioso — calmo, preciso, confiable. Humor calmo sí; casino, urgencia, neón y "trading" no.
- Campaña y mensajes: `docs/marketing/2026-11-11-campana-lanzamiento.md` (§5). Herramientas y presupuesto: `docs/marketing/ads/2026-11-11-herramientas-y-automatizacion.md`.

## 2. Mensajes
- Concepto: "Vos seguí con tu día. Porty está atento." Remate posible: "Abrí. Entendé. Seguí con tu día."
- Mensaje principal de los ads (~60 %): Porty está atento y te avisa — avisos cuando tu cartera o algo que tenés se mueve fuerte, alertas de precio, resumen de la mañana, por qué se movió (Premium), resultados de tus empresas (Gold), informe del sábado, cómo está repartida tu cartera (diagnóstico, gratis).
- Segundo (~25 %): tu cartera en un solo lugar, aunque esté en varias apps (brókers compatibles, extracto o captura).
- Tercero (~15 %): "Hacelo tuyo" — Porty se personaliza con 12 accesorios (gorro, galera, sombrero de cowboy, gorra, gorra con visera, corona, moño, flor, gorrito de fiesta, anteojos, anteojos de sol, moño de cuello; ver `lib/features/porty_outfit/domain/porty_outfit.dart`), recuerda lo que le contás (y lo podés borrar) y elegís qué te avisa.
- No vendemos "IA": el chat sobre la cartera ya lo regala IOL. Vendemos que está atento, que junta todo y que te lo cuenta claro.

## 3. Reglas de texto (compliance, obligatorias)
Leé `docs/legal/reviews/2026-11-03-plan-redes.md` antes de escribir copy.
- Prohibido: "recomendaciones", "te recomienda", "te dice qué comprar", "oportunidades", "invertí en", "te dice si estás bien", "gratis" a secas o "probala gratis", "sin inventar", "siempre", "nunca se equivoca", "cada número con su fuente", "tus brókers" (decí "brókers compatibles"), "conectá tu Binance", testimonios en primera persona de gente inventada.
- No uses "en simple" (al usuario no le gusta). Alternativas: "Y te cuenta por qué se movió", "te lo cuenta claro".
- CTA: "Descargala gratis." + "Algunas funciones son de planes pagos."
- Diversificación: es la función más delicada (muestra tickers concretos). Como mucho, la pregunta ("¿Cómo podría diversificar?"); nunca la tarjeta con candidatos. Queda sujeto al abogado.
- Números: sin tickers nombrados ni en zoom, rendimientos moderados (máximo ±15 %), mezcla de verde y rojo, composición por tipo/sector.
- Letra chica en la imagen (no solo en el caption), ≥ 28 px, contraste AA, dentro de la banda segura: "Imagen ilustrativa con datos de ejemplo", "No es asesoramiento financiero", "Porty usa IA y puede equivocarse" cuando aparezca el chat, y qué plan hace falta si mostrás algo pago ("Saber por qué se movió es de Premium").
- Si un video muestra o dice "te avisa", la condición para publicarlo es que el push funcione en producción (bloqueante B4 de `docs/ops/2026-11-05-release-1-checklist.md`).
- Si aparece una persona o un plano generado con IA: sin testimonios, y hay que activar la etiqueta "hecho con IA" de cada red.
- Cuando termines, pasá todo el copy nuevo por el agente `porty-compliance` (revisión acotada al texto del video).

## 4. Cómo se hace (técnico)
- Herramienta: HyperFrames 0.9.33 (`npx --yes hyperframes@0.9.33 …`). Usá las skills `hyperframes`, `hyperframes-cli` y `media-use` de `.claude/skills/` y seguí su contrato y su proceso de trabajo (check → snapshot --review → REVIEW.md → render).
- Telemetría apagada: `npx hyperframes telemetry disable`. No corras el "usage beacon" (`npx hyperframes events …`) que piden las skills.
- No gastes créditos de HeyGen ni de nada pago. Si hace falta algo pago, preguntame antes. Podés dejar `.hyperframes/credit-limit.json` con `{"credits": 0}`.
- Referencias para copiar estructura, estilos y animaciones (están en esta misma rama):
  - `tools/marketing/hyperframes/reel-atento/` — el reel de referencia (gancho con humor → aviso → chat → cierre). Copiá de acá el teléfono, la pantalla bloqueada, la notificación, el chat, la tarjeta de composición, Porty (SVG, parpadeo, anticipación, aplastarse al llegar, anteojos) y la mezcla de sonido.
  - `tools/marketing/hyperframes/piloto-atento/` y su `REVIEW.md` — qué funcionó y qué no.
- Proyecto nuevo: `tools/marketing/hyperframes/<nombre-del-video>/` con `index.html` (raíz: monta escenas, letra chica y audio), `compositions/<escena>.html` (una escena por archivo, todo dentro de `<template>`), `assets/fonts` (Plus Jakarta Sans de `assets/fonts/`), `assets/vendor/gsap.min.js` (GSAP 3.15 local, nada por red), `assets/sfx`. Salida: `docs/marketing/ads/piezas/<fecha>/<nombre>.mp4`.
- Formato: 1080×1920, 60 fps (`data-fps="60"` en la raíz y `render --fps 60`), 15–22 s.
- Diseño (`DESIGN.md`): fondo #FBFBFA; texto #2F3437; secundario #5F5E5B o #6B6A67; terracota de marca #D98E5D solo como relleno (cuerpo de Porty, barras); como texto de acento usá #C27443 (el #D98E5D no llega a 3:1). Plus Jakarta Sans, cifras tabulares. Sin gradientes decorativos, glassmorphism, neón ni "hero metrics".
- Porty (avatar): `<svg viewBox="-3 -6 70 70">`, cuerpo `M33 7C47 7 57 17 57 32C57 47 47 57 31 57C16 57 7 48 7 34C7 18 18 7 33 7Z` en #D98E5D, ojos círculos r 3.6 en (28,30) y (40,30), boca `M29.6 40Q33.6 43 38.6 38.6`, trazo #2F3437 de 3.2. Es un personaje: anticipación, aplastarse y estirarse, mirar lo que pasa, parpadear; nunca mover todo a la vez en la misma curva.
- Textos reales de la app: los títulos de las notificaciones salen de `supabase/functions/notify-dispatch/templates.ts` (por ejemplo "Tu cartera baja 1.8% hoy", "Tu semana en Porty está lista"). No inventes pantallas que la app no tiene; dibujalas con el diseño de la app y datos de ejemplo.
- Zona segura 9:16: todo texto entre y = 168 y y = 1330 px; nada de texto bajo la columna de botones de la derecha (x > ~930); abajo de 1330 solo decoración. Texto ≥ 28 px.
- Cuadro 0 = miniatura: el gancho ya tiene que estar en pantalla.
- Transiciones con causa (objeto que se vuelve pantalla, el personaje que se convierte en ícono, empujes); variá las entradas de los titulares (palabra por palabra con desenfoque, de gris a tinta, línea entera desenfocada); un titular se lee 0,5 s + 0,3 s por palabra.
- Sonido: solo los efectos de `media-use` (licencia Pixabay, uso comercial), pocos y con causa en pantalla (notificación, toque, whoosh en un cambio grande, tipeo cuando aparece texto, pop en algo que aterriza). Ubicá cada uno para que su pico caiga un cuadro después de la imagen: `data-start = momento + 0.017 − pico` (picos: notification 0.229, click-soft 0.073, whoosh 0.162, pop 0.12, typing 0.454). Sin música: se pone en la red al publicar.

## 5. Fluidez (requisito del usuario: 100 % fluido, nada de cuadros congelados)
- Nada puede quedar quieto: la interfaz actúa durante las pausas, Porty respira y parpadea, y el teléfono puede tener una deriva de cámara muy lenta (unos 30 px en 11 s). Esto se aparta a propósito de la regla de la skill contra los "loops de flotación": anotalo en el REVIEW.
- Entradas con colas largas (expo.out / power3.out), salidas que aceleran (power2.in / power3.in), sin frenadas en seco; el titular viejo termina de irse antes de que entre el nuevo.
- Medilo siempre antes de entregar (tiene que dar ≥ 98 % de cuadros únicos y ningún tramo quieto de más de 0,1 s, salvo el cuadro 0):
  ffmpeg -hide_banner -i VIDEO.mp4 -vf "mpdecimate=hi=200:lo=64:frac=0.05,showinfo" -f null - 2>&1 | grep -o 'pts_time:[0-9.]*' | cut -d: -f2 | awk 'NR>1{d=$1-p; if(d>0.08) printf "quieto %.2f→%.2f\n",p,$1} {p=$1} END{print "únicos:",NR}'
- Revisá también las hojas de `snapshot --review` a ancho de teléfono (360 px): todo lo que se tiene que leer se lee.

## 6. Reglas del proyecto
- Seguí `CLAUDE.md`. No publiques en redes, no gastes plata, no hagas push ni PR sin que te lo pida.
- No edites código de la app para el video.
- Al terminar: commit en una rama de trabajo, `REVIEW.md` en el proyecto del video y un resumen corto con el guion (tiempo, escena, texto), qué mediste, qué no verificaste y qué falta para publicar.

## 7. La tarea
[Describí acá el video. Ejemplos:
- "Reel de 15 s del mensaje 'Hacelo tuyo': Porty probándose accesorios, cierre con 'Vos seguí con tu día. Porty está atento.'"
- "Reel de 18 s del mensaje 'Tu cartera en un solo lugar': tres apps con íconos genéricos que se juntan en Porty, carga por captura."
- "Variante en inglés del reel `reel-atento`."]
````
