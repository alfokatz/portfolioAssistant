# Revisión de compliance: plan de lanzamiento orgánico IG + TikTok

**Fecha:** 2026-11-03 · **Autor:** porty-compliance (no es asesoramiento legal)
**Documento revisado:** `docs/marketing/social/2026-11-03-plan-lanzamiento-ig-tiktok.md` (12 piezas + 2 secuencias de stories). El plan no se editó: los textos corregidos de abajo reemplazan a los del plan al producir.
**Veredicto:** ok con cambios. No producir P1, P3 y P6 con el texto actual (claims no verificados en el código). Ningún cambio altera el alcance de una feature, así que no hace falta pasar por product-owner. Quedan cuatro puntos que necesitan abogado (ver el final).

## Cómo se revisó y qué NO se verificó

- Leí el plan y, en el código, solo lo de las 3 dudas: `lib/domain/subscription/plan_matrix.dart`, `lib/features/assistant/catalog/` (kit y widgets), `lib/features/assistant/prompts/assistant_prompt_rules.dart`, y un grep puntual de gating del Diagnóstico y del informe semanal.
- **No abrí las políticas de Meta ni de TikTok ni las normas argentinas en esta sesión** (presupuesto de tokens). Los links son las raíces oficiales y las reglas las cito de memoria: hay que confirmarlas antes de apoyarse en ellas.
  - Instagram, normas de la comunidad: https://help.instagram.com/477434105621119
  - Meta, estándares de la comunidad (fraude, estafas y prácticas engañosas): https://transparency.meta.com/policies/community-standards/fraud-scams/
  - Meta, política de contenido de marca: https://transparency.meta.com/policies/other-policies/branded-content-policies/
  - TikTok, normas de la comunidad (integridad y autenticidad, divulgación comercial, contenido generado por IA): https://www.tiktok.com/community-guidelines/en
  - Ley 24.240 de Defensa del Consumidor, art. 4 (información cierta y clara): https://servicios.infoleg.gob.ar/infolegInternet/anexos/0-4999/638/texact.htm
  - CNV (régimen de asesores de inversión): https://www.argentina.gob.ar/cnv
- Las reglas estrictas de "productos y servicios financieros" de Meta y de TikTok son sobre todo reglas de **anuncios**. El contenido orgánico queda bajo las normas de la comunidad (fraude, engaño, promesas de ganancia, divulgación comercial). Si el plan pasa a pagas, todas las piezas se revisan de nuevo (más estricto, y cripto puede pedir autorización previa).
- `docs/legal/disclaimers.md` y `docs/legal/data-inventory.md` **no existen todavía**. Los disclaimers de la sección 2 de este archivo quedan como propuesta para pasarlos a `disclaimers.md` cuando el usuario los apruebe.

---

## 1. Dudas abiertas del plan, resueltas con el código

### (1) ¿Se puede decir "gratis"?

**Sí, con condiciones.** Existe el plan Free (`PlanMatrix.plans[SubscriptionTier.free]`): solo `ownPortfolio`, 20 consultas al mes, 10 posiciones, 1 alerta de precio, watchlist 0.

Qué incluye cada plan según la matriz (lo que importa para las piezas):

| Plan | Lo que muestran las piezas |
|---|---|
| Free | Cartera propia, Dashboard, chat (20 consultas/mes). El Diagnóstico de cartera "funciona igual en Free" (comentario en `portfolio_diagnosis_screen.dart`); solo la sincronización de brókers queda bloqueada. |
| Premium | Comparación contra el S&P 500 (`benchmark`), precios de lo que no tenés (`marketData`), simulaciones, metas, plan de cartera, conexión de bróker (eToro y uno de SnapTrade), posiciones ilimitadas |
| Gold | Varios brókers por SnapTrade, noticias, earnings, fundamentals, análisis de empresa, informe semanal (lo habilita el servidor `claim_weekly_report`; quien no tiene Gold recibe una muestra de cortesía) |

Por pieza: P1 (conexión de brókers) = Premium/Gold; P2 (placa de benchmark) y P3 (comparar con S&P 500) = Premium; P4 y P10 (informe semanal) = Gold; P7 (metas) = Premium; P11 = Premium; P6 (noticias) = Gold; P8, P9 = Free; P12 = onboarding Free, la conexión es paga. No verifiqué si Binance y el import por captura están en Free (no figuran en la matriz) ni si hay prueba gratis en RevenueCat: no afirmar ninguna de las dos cosas.

Reglas para el uso de "gratis":
- Permitido: "Descargala gratis" y "Empezá con el plan Free".
- No permitido: "Probala gratis" (sugiere prueba gratuita de todo; no se verificó ningún trial) ni "gratis" pegado a una demo de función paga sin aclararlo.
- Toda pieza que muestre una función de Premium o Gold lleva la línea D de la sección 2.
- No mencionar precios ni "sin costo" a secas.

### (2) ¿Las cards del chat muestran fuente y fecha de los números?

**No de forma general.** Lo que encontré en `catalog/`:
- `as_of` **no se dibuja**. Es un dato del contexto de las tools que usa el modelo para resolver fechas relativas ("ayer") y decidir si un precio está viejo (`assistant_prompt_rules.dart`, líneas 72-73 y 434-435). Ninguna card lo muestra como "actualizado al...".
- Lo que sí tiene fuente y fecha visibles: las **noticias** (medio + fecha relativa vía `QaTime.ago`, `company_widgets.dart:515`; son Gold), la lista **FUENTES** al pie del mensaje con links (citas de búsqueda web y presentaciones a la SEC, `source_widgets.dart`), y la etiqueta "Fecha estimada" en earnings.
- Las cards de análisis, comparar y simulación no tienen una línea de fuente ni de fecha de los números. No encontré ningún rótulo "Fuente:" ni "Actualizado" en esas cards (grep sobre `catalog/`; no leí cada widget línea por línea, así que lo confirma el coordinador al capturar T3 y T4).

Consecuencia: "Cada número con su fuente" (P1), "con la fuente de cada número" (P1, stories 6.1 placa 3), "Con la fuente" (P3), "de dónde sale" (P3 guion) y P6 placa 2 **no se pueden decir tal cual**. Abajo van los reemplazos. Si product-owner quiere ese diferencial como promesa de marca, es una feature (mostrar fuente y `as_of` en las cards) y recién ahí se puede decir.

### (3) ¿El chat responde "no tengo ese dato"?

**Es el comportamiento pedido, pero no hay una frase fija ni un test que la capture.**
- El prompt (`assistant_prompt_rules.dart`, "GROUNDING", líneas 92-112) manda: números solo del brief o de tools, "campo ausente → decilo con claridad", "decí lo que no podés verificar". Para noticias vacías hay una frase literal: "No tengo noticias recientes sobre X" (línea 436). Para el resto la redacción la genera el modelo y varía.
- La única coincidencia literal en `lib/`, `test/` y `assets/` es esa línea del prompt. No hay screenshot-test que genere una respuesta de límite.
- Es una IA: el prompt reduce el riesgo pero no lo elimina. Se puede decir "está pensado para aclarar lo que no sabe", no "siempre te dice" ni "nunca inventa".
- P6 placa 3: generar la captura como caso extra con datos demo (como pide el plan), pero **solo con una respuesta real**. El caso más estable es noticias vacías de un activo sin notas (frase literal del prompt, aunque noticias es Gold). Si no sale, se omite la placa.

### Hallazgo extra del prompt, fuera del plan

`assistant_prompt_rules.dart:99`: "You MAY talk about and suggest ANY company, fund or ticker you know". Esa línea choca con "nada de recomendaciones". No revisé el contexto completo. Por eso **toda respuesta del chat grabada (T3, T4, T5 y stories) se lee entera antes de usarla**, y se descarta si dice "te conviene", "comprá", "sumá X" o propone tickers. Se lo paso a quien me consultó para que lo derive a `porty-assistant-dev` y a product-owner.

---

## 2. Disclaimers: dónde y cómo

Textos aprobados para estas piezas (todos en español rioplatense):

- **A (base):** `Cuenta demo. No es asesoramiento financiero.`
- **B (con rendimiento o comparación):** `Cuenta demo. Rendimientos pasados no garantizan resultados futuros. No es asesoramiento financiero.`
- **C (IA):** `Porty usa IA y puede equivocarse. Verificá la información importante.`
- **D (planes):** `Algunas funciones son de planes pagos.`
- **E (marcas):** `S&P 500® es marca registrada de S&P Dow Jones Indices LLC. Binance, eToro y SnapTrade son marcas de sus titulares, usadas solo para indicar compatibilidad.` (Revisión humana: sí. No afirmo "sin afiliación": SnapTrade es proveedor de Porty y no conozco el vínculo con los demás.)

Cómo:
- **Videos (Reel/TikTok):** el texto fijo va **en la imagen**, no solo en el caption. Los captions se cortan ("ver más") y los Reels reutilizados pierden el caption. Poner "Cuenta demo" desde el segundo 0 hasta el final, y A o B en pantalla durante los últimos 3 s como mínimo (o todo el video si hay comparación o rendimiento).
- **Tamaño y ubicación:** por lo menos 28 px sobre 1080 de ancho, contraste mínimo 4.5:1, dentro de la zona segura (no en los 340 px de abajo ni sobre los botones laterales, que tapan los controles de la red). Eso es criterio de este review, no una cifra de las redes.
- **Caption:** el disclaimer va igual, al final, porque el caption es lo que ven los buscadores de la red y los lectores de pantalla.
- **Carruseles e imagen única:** en el pie de **cada placa** que tenga comparación, rendimiento o PnL, y en la última placa (A o B). No alcanza con poner uno en la última placa si el comparativo está en la 4.
- **Stories:** en cada placa que muestre números o una función, y en la última (sticker de link). Tamaño mínimo igual que arriba.
- **C (IA)** va en P3, P6 y en cualquier pieza donde se vea una respuesta del chat. **D** va en toda pieza que muestre una función de Premium/Gold. **E** en P1, P2, P3, P11 y P12 cuando se vea un logo o nombre de tercero.
- **Contenido generado por IA (Sunra):** si alguna vez se usa para planos de contexto, se declara con la etiqueta de la red (TikTok y Meta tienen etiqueta para contenido realista generado por IA). Nunca para simular pantallas de la app (ya está en el plan).
- **TikTok, divulgación comercial:** al promocionar el propio producto desde la cuenta, revisar el ajuste de divulgación de contenido (la opción "tu marca") antes de publicar. Lo recuerdo de memoria: confirmarlo en la app.

---

## 3. Hallazgos transversales

```
[BLOQUEA] Plan completo (idea central, pilares, P1, P3, 6.1) — "números reales con su fuente", "cada número con su fuente", "sin inventar números" son claims absolutos no verificables
Por qué: las cards de análisis/comparar no muestran fuente ni as_of (ver 1.2) y el chat es un LLM (ver 1.3). Ley 24.240 art. 4 (información cierta) y normas de Meta/TikTok sobre contenido engañoso.
Texto propuesto: "Las cifras salen de tu cartera y de datos de mercado." / "Porty te explica tus números." Nada de "sin inventar", "siempre", "nunca" ni "cada número con su fuente".
Revisión humana: no
```

```
[BLOQUEA] P1 (CTA), P4, P7, P11 y todo CTA con "Probala gratis" / "Activalo" / "Armá la tuya" — "gratis" y CTA sin aclarar que la función mostrada es paga
Por qué: ver 1.1. Mostrar una función paga con "gratis" es publicidad engañosa por omisión (Ley 24.240 art. 4) y las redes lo tratan como engaño.
Texto propuesto: "Descargala gratis. Algunas funciones son de planes pagos." (línea D en la imagen y en el caption)
Revisión humana: no
```

```
[CORREGIR] Plan sección 4 (tomas), T5 — la pregunta de simulación ("¿Qué pasaría si aporto una cantidad fija por mes?") activa la simulación educativa (get_invest_candidates), que puede mostrar tickers candidatos
Por qué: tickers visibles con una simulación de aporte se leen como "dónde poner la plata". Código: PlanFeature.investSimulation en plan_matrix.dart.
Texto propuesto: No usar T5 en el feed. En stories, solo si la card no muestra candidatos con nombre. Para mostrar proyección usar T9 (Metas) con la línea "Estimación, no garantía."
Revisión humana: no
```

```
[CORREGIR] Plan sección 4 (cuenta demo, T1, T10, T11) — datos personales y marcas en pantalla
Por qué: T1 "tocar un bróker" puede abrir el login real de SnapTrade/Binance/eToro y mostrar una cuenta real; T11 usa un mail para registrarse; T10 agrega un activo con nombre. Ley 25.326 (minimización).
Texto propuesto: grabar T1 solo hasta la lista y la pantalla previa a autenticar, o con una cuenta de prueba/sandbox del proveedor si existe (no lo verifiqué). Mail de T11 con una casilla de demo sin nombre real. En T10, un activo genérico sin destacar. Revisar cada archivo antes de editar: barra de estado, portapapeles, ajustes y notificaciones, sin mail ni ID de cuenta.
Revisión humana: no
```

```
[CORREGIR] Plan sección 4 (datos demo) — tickers y rendimientos
Por qué: la regla "ETFs amplios y acciones grandes, sin destacarlas" es buena, pero tickers reales visibles pueden leerse como sugerencia si hay zoom, voz, texto o si el mejor queda primero. Un PnL demo muy alto invita a perseguir rendimiento.
Texto propuesto: ningún ticker se nombra por voz ni en texto en pantalla ni se hace zoom a una posición concreta; ordenar posiciones por tamaño, no por rendimiento; PnL demo moderado (como máximo un +/-15 % en cualquier posición o total) y mezcla de verde y rojo.
Revisión humana: no
```

```
[CORREGIR] P1, P3, P10 y stories — testimonios en primera persona inventados ("Tenía mi plata repartida en tres apps", "Le pregunté a mi asistente cómo me fue este mes", "Mi yo de ahora")
Por qué: el propio plan (sección 8) prohíbe testimonios inventados. Un relato en primera persona sobre una cuenta demo se lee como experiencia real. Normas de Meta/TikTok sobre autenticidad.
Texto propuesto: voz impersonal o condicional ("Si tu plata está repartida en varias apps...") y "Cuenta demo" visible desde el segundo 0. Si es humor actuado (P10), marcarlo como "escena actuada".
Revisión humana: no
```

```
[CORREGIR] P1 (hook, íconos), 6.1 y 6.2 — marcas de brókers
Por qué: usar logos de terceros puede sugerir alianza o aval. Mencionar "SnapTrade, Binance, eToro" como compatibilidad es uso descriptivo, pero Binance es cripto y Meta y TikTok restringen la promoción de plataformas cripto (confirmar la regla vigente). Los términos de SnapTrade/eToro/Binance sobre uso de sus marcas en marketing no los leí.
Texto propuesto: no armar la toma de "tres íconos de apps" con logos reales: usar íconos genéricos. La lista de la app (T1) puede verse tal cual, sin zoom ni foco en Binance, con la línea E en el pie. Nunca "Conectá tu Binance".
Revisión humana: sí (términos de marca de cada proveedor)
```

```
[CORREGIR] Todo el plan — sin disponibilidad por país
Por qué: los hashtags son #argentina y la app tiene es-ES. La conexión de cada bróker y las funciones pueden variar por país (el plan lo anota para backend-dev). Decir "conectá tu bróker" sin límite de países es un claim que hay que poder cumplir.
Texto propuesto: "Brókers compatibles" en vez de "tus brókers", y agregar al caption de P1: "La disponibilidad depende del país y del bróker."
Revisión humana: no
```

```
[SUGERENCIA] Idea central y copy — "rendimiento real" (punto 4 de la estrategia) y "toda tu cartera"
Por qué: "rendimiento real" es ambiguo (¿ajustado por inflación?) y suena a promesa; "toda tu cartera" es absoluto: Free carga hasta 10 posiciones y solo funcionan los brókers compatibles.
Texto propuesto: "Tu cartera en un solo lugar" y "contexto sobre cómo viene tu cartera".
Revisión humana: no
```

```
[SUGERENCIA] Plan sección 8 — pagas, influencers y audio
Por qué: si más adelante alguien más (amigos, creadores) publica sobre Porty con algún beneficio, tiene que divulgarlo con las herramientas de contenido de marca de cada red. El audio de tendencia en cuentas de empresa suele estar limitado a la biblioteca comercial.
Texto propuesto: sumar al plan "si hay terceros que publican, pasa por compliance y divulgan la relación"; audio solo de la biblioteca comercial de cada red.
Revisión humana: no
```

---

## 4. Hallazgos por pieza

Formato: **Texto propuesto** reemplaza al del plan. Lo que no figura queda como está en el plan.

### P1. Tus brókers en un solo lugar

```
[BLOQUEA] P1 hook, guion y texto en pantalla — relato en primera persona inventado, "con la fuente de cada número", "Un solo lugar / Varios brókers"
Por qué: ver hallazgos transversales (testimonio inventado, fuente no verificada, brókers compatibles, plan). Conectar brókers es de Premium/Gold.
Texto propuesto:
- Hook en pantalla: "¿Tu plata está repartida en varias apps?"
- Voz 0-2 s: "Si tu plata está repartida en varias apps, mirá esto."
- Voz 16-22 s: "Podés verla junta: cada posición con su bróker." (usar solo si el Dashboard realmente muestra el bróker de cada posición; si no, decir "Podés verla toda junta.")
- Texto en pantalla: "Una sola vista", "Brókers compatibles". Sacar "Cada número con su fuente".
- Disclaimer en pantalla: A, D y E.
Revisión humana: no
```

```
[CORREGIR] P1 caption y CTA — "gratis" y alcance
Por qué: ver 1.1.
Texto propuesto:
- Caption: "Una sola vista para tu cartera, aunque esté repartida en varios brókers compatibles. Conectar brókers es parte de los planes pagos. La disponibilidad depende del país y del bróker. Cuenta demo. No es asesoramiento financiero."
- CTA: "Descargala gratis, link en la bio."
- Hashtags: sacar #portfolio si compite con cripto; dejar #inversiones #finanzaspersonales #argentina #inversorcasual.
Revisión humana: no
```

### P2. Tres cosas que tu cartera no te cuenta

```
[CORREGIR] P2 placa 5 y caption — "Esto no es una opinión: es lo que dicen tus números" y "conviene mirar"; falta B y D
Por qué: el Diagnóstico incluye una explicación que genera IA; decir que no es una opinión es un claim absoluto. "Conviene" roza consejo. La placa 4 compara con el S&P 500 (Premium) y es una comparación de rendimiento.
Texto propuesto:
- Placa 5: "Son tus propios datos, calculados y explicados por Porty."
- Placa 4: agregar el pie B. En todas las placas con captura, el pie A.
- Caption: "Mirar solo el total es como mirar solo la nota final. Acá van tres cosas más para mirar. La comparación con el S&P 500 es de los planes pagos. Cuenta demo. Rendimientos pasados no garantizan resultados futuros. No es asesoramiento financiero."
- Última placa: A + D + E (S&P 500).
Revisión humana: no
```

### P3. Le pregunté a Porty

```
[BLOQUEA] P3 hook, guion, texto en pantalla y caption — primera persona, "Sin inventar números", "Con la fuente", "no de la imaginación", "de dónde salen"
Por qué: ver 1.2 y 1.3 (el chat es un LLM; las cards no muestran fuente). Meta y TikTok sacan contenido que promete exactitud absoluta de una IA financiera. "Comparar con el S&P 500" es Premium.
Texto propuesto:
- Hook: "Esto le preguntaría a mi cartera de ejemplo: ¿cómo me fue este mes?" (cuenta demo visible desde 0 s). Alternativa más simple: "Preguntale a tu cartera en lenguaje normal."
- Voz 20-27 s: "Porty no te dice qué hacer: te muestra tus números y te los explica."
- Texto en pantalla: "Respuestas basadas en tus datos", "Hecho con IA". Sacar "Sin inventar números" y "Con la fuente".
- Caption: "Preguntale a tu cartera en lenguaje normal. Las respuestas parten de tus datos y las genera una IA que puede equivocarse: verificá lo importante. Comparar con un índice es de los planes pagos. Cuenta demo. Rendimientos pasados no garantizan resultados futuros. No es asesoramiento financiero."
- Pie en pantalla: B + C.
- Antes de usar la captura: leer la respuesta completa; descartar si hay lenguaje de recomendación (ver hallazgo extra en 1).
Revisión humana: no
```

### P4. El informe del sábado

```
[CORREGIR] P4 texto de la imagen, caption y CTA — el informe semanal es Gold; "Qué mirar la próxima" puede leerse como indicación
Por qué: ver 1.1 (el informe lo habilita el servidor; los demás planes reciben una muestra de cortesía). Además no leí `weekly_report_samples.json`: si una muestra trae lenguaje de "qué hacer", no se puede usar.
Texto propuesto:
- Tres líneas: describir solo las secciones que tiene el informe capturado, por ejemplo "Qué pasó esta semana. Qué se movió más. Lo que hay en agenda." Sacar "Qué mirar la próxima" si el informe no tiene una sección de agenda.
- Caption: "Una vez por semana, un resumen de tu cartera, sin ruido. El informe semanal completo es del plan Gold. Cuenta demo. No es asesoramiento financiero."
- CTA: "Descargala gratis. Link en la bio."
- Leer las dos muestras demo completas antes de producir.
Revisión humana: no
```

### P5. De una captura a tu cartera

```
[CORREGIR] P5 hook, texto en pantalla y caption — "Funciona aunque tu bróker no conecte" y "Vos confirmás cada dato" sin verificar; falta aviso de que la lectura puede fallar y de dónde van los datos
Por qué: el plan pide validar con flutter-dev que haya confirmación antes de guardar. El import usa IA para leer la imagen (tercero a revelar en privacidad). Una captura real del usuario suele incluir nombre y número de cuenta.
Texto propuesto:
- Publicar solo si T6 muestra una pantalla de confirmación real antes de guardar.
- Texto en pantalla: "Revisás antes de guardar" (solo si se verifica), "También sin conectar un bróker".
- Caption: "Si tu bróker no se conecta, podés cargar tu cartera con una captura o un extracto. Porty lee la imagen con IA y puede equivocarse: vos revisás y confirmás cada dato antes de guardar. Tapá tu nombre y tu número de cuenta antes de subirla. Cuenta demo."
- Pie en pantalla: A + C. No decir "seguro" ni "privado".
Revisión humana: no
```

### P6. De dónde sale cada número

```
[BLOQUEA] P6 hook, placas 2 y 3, caption — las cards no muestran fuente (1.2) y "no tengo ese dato" no es un comportamiento garantizado (1.3)
Por qué: promesa verificable de transparencia que el producto no cumple en todas las cards. Ley 24.240 art. 4.
Texto propuesto:
- Hook: queda "Un número sin fuente es una opinión." (es una frase, no promete nada de Porty)
- Placa 2: "Cuando Porty busca en la web o trae noticias, te muestra el medio, la fecha y el link." Captura: lista FUENTES del pie del mensaje o card de noticias (las noticias son Gold: poner D en el pie).
- Placa 3: "Si no encuentra un dato, lo aclara." Solo con captura real (ver 1.3). Si no sale una respuesta de límite real, omitir la placa.
- Placa 4: "Tu cartera, tus números." (queda)
- Caption: "Porty está pensado para aclarar cuándo no tiene un dato en lugar de inventarlo. Es una IA y puede equivocarse: verificá lo importante. Noticias: plan Gold. Cuenta demo. No es asesoramiento financiero."
- Pie en todas las placas: A + C.
Revisión humana: no
```

### P7. Metas de ahorro

```
[CORREGIR] P7 caption y CTA — Metas es Premium; las proyecciones dependen de supuestos de rendimiento
Por qué: ver 1.1. Una "fecha estimada" calculada con un rendimiento supuesto puede leerse como promesa si no se dice el supuesto (el código usa `risk_default` en `GoalProjectionBuilder`).
Texto propuesto:
- Caption: "Una meta, un avance, una fecha estimada. La fecha se calcula con supuestos y es una estimación, no una garantía. Metas es de los planes pagos. Cuenta demo."
- Texto en pantalla (al mostrar la fecha): "Estimación, no garantía".
- CTA: "Descargala gratis y probá Metas con tu plan."  (alternativa corta: "Armá tu meta en la app. Función de planes pagos.")
- Mostrar en la captura el supuesto de la proyección si la card lo muestra.
Revisión humana: no
```

### P8. Qué es el PnL en 20 segundos

```
[CORREGIR] P8 guion y texto en pantalla — definición imprecisa y frase que reconforta sobre una pérdida
Por qué: "valor actual - lo que pagaste" es el PnL no realizado; el realizado es otra cosa. "No significa que te equivocaste" puede leerse como "aguantá la posición" (consejo implícito).
Texto propuesto:
- Texto en pantalla: "PnL no realizado = valor actual − lo que pagaste".
- Voz 10-16 s: "Un PnL negativo es una foto de hoy: por sí solo no dice si una decisión fue buena o mala."
- Voz 16-20 s: "En Porty lo ves por posición y total." (queda)
- Pie: A. CTA queda.
Revisión humana: no
```

### P9. Diagnóstico de cartera: qué mirar

```
[CORREGIR] P9 placa 4 y caption — "Costos y moneda" sin verificar; el Diagnóstico incluye texto de IA
Por qué: si el Diagnóstico no muestra costos, la placa promete algo que no está. La placa 5 muestra la explicación: hay que leerla entera. Es Free, así que no hace falta D.
Texto propuesto:
- Placa 4: usar solo secciones que tiene la captura real (por ejemplo "Moneda: en qué está expresada tu cartera"). Si no hay costos, sacar "Costos".
- Placa 5: "Cómo lo explica Porty (IA, puede equivocarse)."
- Placa 6: "Esto es información, no una recomendación." (queda) + C.
- Caption: "Un chequeo de una página para entender qué tenés. Describe tu cartera: no te dice qué comprar. Cuenta demo. No es asesoramiento financiero." (queda)
- Antes de producir: leer el texto del Diagnóstico demo completo; si contiene "considerá", "reducí", "diversificá con X", no usarlo.
Revisión humana: sí, si el Diagnóstico contiene lenguaje de acción (porque ahí el producto, no solo el texto del post, se acerca a una recomendación personalizada; ver el punto de abogado)
```

### P10. Abrir la app 14 veces vs una por semana

```
[CORREGIR] P10 caption, texto en pantalla y disclaimer — falta A en el video; "tu cartera no necesita tu atención" es una pauta de conducta; el informe es Gold
Por qué: el plan solo pone "Cuenta demo" en el caption; en videos va en pantalla. Decirle al usuario cómo debe operar su cartera es borde de consejo.
Texto propuesto:
- Texto en pantalla: "Mirar más no siempre es entender más." (con "siempre", no es absoluto)
- Caption: "No hace falta mirar la cartera cada 10 minutos para entenderla. El informe semanal es del plan Gold. Cuenta demo. No es asesoramiento financiero."
- En pantalla: "Escena actuada" en la toma de la mano y A en los últimos 3 s.
Revisión humana: no
```

### P11. Tu cartera vs el S&P 500

```
[CORREGIR] P11 hook, texto, caption — "el mercado" no es el S&P 500; comparación que puede sugerir una decisión; marca de tercero; Premium
Por qué: el S&P 500 es solo acciones grandes de EE. UU. Un gráfico donde la cartera pierde contra el índice puede leerse como "pasate al índice". S&P 500® es marca registrada: el uso nominativo para identificar el índice suele admitirse, sin logo y con atribución (revisión humana).
Texto propuesto:
- Hook: "¿Mejor o peor que un índice de referencia? Se mira así."
- Texto de la imagen: "Un benchmark es una referencia, no una meta ni una recomendación. Tu cartera puede tener otros objetivos, otra moneda y otro riesgo."
- Indicar el período del gráfico en la placa (por ejemplo "Últimos 12 meses, datos demo").
- Caption: "Un número suelto no dice mucho. Contra un benchmark, tiene contexto. Cuenta demo. Rendimientos pasados no garantizan resultados futuros. La comparación con el S&P 500 es de los planes pagos. No es asesoramiento financiero."
- Pie: B + D + E. Sin logo de S&P.
- Curva demo: que la cartera no le gane por mucho al índice (ni se quede muy atrás); evitar el mensaje "ganale al mercado".
- Verificar con assistant-dev/backend-dev qué se usa como benchmark: si es un ETF que replica el índice, decir "un ETF que replica el S&P 500" y no "el S&P 500".
Revisión humana: sí (uso de la marca S&P 500 y de datos del índice)
```

### P12. Armá tu cuenta en 60 segundos

```
[CORREGIR] P12 hook y CTA — "60 segundos" es un claim de tiempo; "Descargala" sin plan; la conexión de bróker es paga
Por qué: el video dura 40 s pero la conexión real de un bróker puede llevar más; un cronómetro en pantalla es una promesa medible.
Texto propuesto:
- Hook: "Así se empieza en Porty." Si el equipo mide el recorrido completo 3 veces y todas son menores a 60 s, se puede usar "Tu cartera en menos de un minuto" (dato de la medición guardado en el plan).
- Sacar el cronómetro si no hay medición.
- Caption: "Así se empieza. Podés cargar tu cartera con un import; conectar brókers es de los planes pagos. Cuenta demo. No es asesoramiento financiero."
- CTA: "Descargala gratis, link en la bio."
- Pie: A + D (+ C si se ve el chat). La pregunta al chat de 25-35 s se lee entera antes de usarla.
Revisión humana: no
```

### Stories 6.1 (secuencia de lanzamiento)

```
[CORREGIR] 6.1 placas 1, 3, 4 y 5 — sticker de cuenta regresiva, "con la fuente de cada número", caja de preguntas, "Probala"
Por qué: la cuenta regresiva crea urgencia (el plan la prohíbe) salvo que sea una fecha real de lanzamiento. "Con la fuente" no está verificado (1.2). La caja de preguntas recibe datos personales y consultas de inversión. "Probala" sugiere prueba gratis.
Texto propuesto:
- Placa 1: sin cuenta regresiva; usar "Seguime".
- Placa 3: "Todo en un lugar." (sacar "con la fuente de cada número")
- Placa 4: sticker "Preguntame sobre Porty. No me cuentes montos ni datos de tu cuenta." Las respuestas se publican sin handle ni foto de quien preguntó, salvo permiso.
- Placa 5: "Descargala gratis. Link abajo." + pie A + D.
- Pie A (o B si la placa tiene números) en las placas 3 y 4; C en la 4.
Revisión humana: no
```

### Stories 6.2 y recurrentes

```
[CORREGIR] 6.2 placas 2 y 5 y "Stories recurrentes" — alcance de planes, respuestas de la caja de preguntas
Por qué: ver 1.1. El plan dice que las respuestas sobre inversiones concretas serán "educativas", pero no define cómo.
Texto propuesto:
- Placa 2: "Conectá un bróker (planes pagos) o importá con una captura."
- Placa 5: "Los sábados, un resumen (plan Gold)."
- Placa 6: "Descargala gratis. Link abajo." + A + D.
- Plantilla de respuesta a "¿conviene comprar X?": "No te puedo decir si conviene comprar X: Porty no da recomendaciones. Lo que sí te explico es cómo mirar [concepto: peso en la cartera, diversificación, etc.] para decidir con tu propio criterio. No es asesoramiento financiero." Sin nombrar ni valorar el activo.
- Encuestas y resultados: se pueden publicar agregados; no capturas con handles.
Revisión humana: no
```

### Resto del calendario

```
[SUGERENCIA] Semanas 2 a 4 — "Balance del mes", "Lo que más preguntaron", "formato ganador"
Por qué: "Balance del mes" puede derivar en cifras de usuarios o resultados que no se pueden verificar; los formatos rehechos con "lo aprendido" traen textos nuevos que no pasaron por esta revisión.
Texto propuesto: el balance del mes solo con métricas propias de la cuenta (seguidores, respuestas a encuestas), no resultados de usuarios ni de Porty. Toda pieza con copy nuevo vuelve a compliance; una variante sin cambios de texto no.
Revisión humana: no
```

---

## 5. Datos personales

- Solo cuentas demo: correcto en el plan. Agrego tres controles: (a) revisar cada archivo antes de editar (barra de estado, portapapeles, ajustes, mail, ID de cuenta, notificaciones); (b) T1 y T11 como se indica arriba; (c) las respuestas a la caja de preguntas, los comentarios y los mensajes de seguidores son datos personales: se usan solo para responder, sin repostear con nombre o foto sin permiso (Ley 25.326, finalidad).
- Medición: la landing con UTM, el código de referencia (`IG`/`TT`) y la pregunta "¿Cómo nos conociste?" agregan un dato nuevo en el onboarding. Hay que reflejarlo en `data-inventory.md` (que todavía no existe), en la Política de Privacidad y, si se guarda del lado de la cuenta, en las etiquetas de Apple y Google. Lo hago cuando se defina el campo con `porty-data-analyst`. La landing necesita aviso de cookies/medición si usa analytics.

---

## 6. Segunda pasada: piezas de presentación PR1 a PR5 (plan v2)

Alcance: solo el copy nuevo de PR1 a PR5 (secciones 3 y 6.1 del plan v2), contra los hallazgos de arriba. Lo aplicado bien del review anterior (sin "sin inventar", sin "fuente de cada número", "Descargala gratis" + D, voz impersonal, sin cuenta regresiva, sin T5, sin tiempos) no se repite. El resto del plan no se volvió a revisar. Disclaimers A a E: los de la sección 2.

```
[CORREGIR] PR1 (texto en pantalla y cierre), PR3 (línea bajo el título y caption), PR1 hook/caption: "Tu asistente de inversiones"
Por qué: "asistente de inversiones" se puede leer como que Porty asiste o aconseja invertir, justo lo que el producto no hace. Es el claim más cercano al borde de asesoramiento de las 5 piezas. Ley 24.240 art. 4 y el límite regulatorio (ver "Requiere abogado", punto 1).
Texto propuesto: "Porty. Tu asistente para entender tu cartera." (PR1 cierre) y "Tu asistente para entender tu cartera. Te la explica con calma." (PR3 imagen, caption y versión Stories).
Revisión humana: no
```

```
[CORREGIR] PR1 (6-11 s), PR2 (placa 3), PR5 (placa 3) y PR4 (10-19 s): captura del Dashboard sin B, D ni E
Por qué: el Dashboard muestra PnL y variación, y según `plan_matrix.dart` la comparación con el S&P 500 vive en el home y es Premium. Si la captura trae PnL, evolución o el comparativo, es pieza con rendimiento: lleva B (no solo A), D y, si se ve el índice, E. El plan solo pone B "si se muestra rendimiento en la card" (PR4) y A en las demás.
Texto propuesto: recortar la captura para que no se vea el comparativo con el índice, o dejarlo y agregar el pie "Cuenta demo. Rendimientos pasados no garantizan resultados futuros. No es asesoramiento financiero. Algunas funciones son de planes pagos." (B + D) y E. Con PnL visible, B es obligatorio en PR1 (últimos 3 s), PR2 placa 3, PR4 y PR5 placa 3.
Revisión humana: no (la parte del uso de "S&P 500" ya figura en el punto 2 de abogado)
```

```
[CORREGIR] PR4 (pregunta de 19-27 s, texto en pantalla, caption): B y "lo que quieras"
Por qué: "¿Cómo me fue este mes?" devuelve una card con variación: es rendimiento, así que B no es opcional. "Le preguntás lo que quieras entender" invita a preguntas sobre qué comprar, y el prompt permite sugerir tickers (hallazgo extra de la sección 1).
Texto propuesto: voz "Y le preguntás lo que quieras entender de tu cartera." Pie en los últimos 3 s: A + B + C + D. Leer la respuesta grabada entera y descartarla si tiene lenguaje de recomendación.
Revisión humana: no
```

```
[CORREGIR] PR4 caption: "Podés cargarla con un import" junto a "Descargala gratis"
Por qué: el import no figura en `plan_matrix.dart` y no está verificado si es Free; Free llega a 10 posiciones. Afirmarlo con "gratis" es un claim sin respaldo (ver 1.1).
Texto propuesto: publicar la versión del plan solo si flutter-dev confirma que el import está en Free. Si no se confirma: "Podés cargar tu cartera desde la app (según tu plan); conectar brókers es de los planes pagos."
Revisión humana: no
```

```
[CORREGIR] PR1, PR2 placa 4, PR4: texto "Hecho con IA" en pantalla
Por qué: ambiguo. Puede leerse como que el video fue generado con IA (la etiqueta de contenido sintético de TikTok/Meta tiene otro sentido) y no que el asistente usa IA. Además el pie C ya lo dice.
Texto propuesto: "Porty usa IA" (o "Respuestas con IA") en lugar de "Hecho con IA". Si la voz en off es sintética, declararlo con la etiqueta de la red.
Revisión humana: no
```

```
[CORREGIR] PR5 placa 2: "tu plata está repartida en varias apps, esto es para vos"
Por qué: promete juntar varias apps, y eso se logra con conexión de bróker (Premium/Gold) o import (Free sin verificar). Con "Descargala gratis" en la placa 5 queda como promesa de la versión gratuita.
Texto propuesto: "Si tu plata está repartida en varias apps, Porty te ayuda a verla junta (conectando brókers en planes pagos, o con un import)."  Pie A + D en la placa.
Revisión humana: no
```

```
[SUGERENCIA] PR5 placas 1 y 4, PR2 placa 2
Por qué: (a) "Hola, soy Porty" no dice que es una IA: decirlo al presentarse suma transparencia; (b) la caja de preguntas va a recibir "¿conviene comprar X?"; (c) la placa 2 de PR2 no tiene captura, así que "Cuenta demo" en el pie sobra.
Texto propuesto: (a) "Hola, soy Porty, un asistente con IA. Te ayudo a entender tu cartera." (b) usar la plantilla de respuesta del review (sección 4, Stories 6.2); antes de publicar cada respuesta, sin handle ni foto. (c) pie solo "No es asesoramiento financiero".
Revisión humana: no
```

Lo demás de PR1 a PR5 está en regla: disclaimers en la imagen, "Cuenta demo" desde 0 s, avatar sin contenido financiero, pie C en PR3 (sin números), hashtags, CTA con D, audio de la biblioteca comercial, sin comparaciones con terceros y sin tickers. PR3 además lleva el texto "No es asesoramiento financiero" en la imagen (no solo en el caption), porque la imagen se reposta en Stories sin caption.

| Pieza | Veredicto |
|---|---|
| PR1 | ok con cambios (asistente, Dashboard con B/D/E, "Hecho con IA") |
| PR2 | ok con cambios (Dashboard con B/D/E, "Hecho con IA") |
| PR3 | ok con cambios (asistente, agregar "No es asesoramiento financiero" en la imagen) |
| PR4 | ok con cambios (B obligatorio, import en Free sin verificar, "lo que quieras") |
| PR5 | ok con cambios (placa 2, Dashboard con B, presentarse como IA) |

---

## Reporte

**Veredicto:** ok con cambios. No producir P1, P3 y P6 con el texto del plan.
**Requiere abogado:** sí, por cuatro cosas:
1. Si el Diagnóstico y el informe semanal, que hablan de la cartera de cada usuario, quedan del lado de la información o pasan a ser asesoramiento regulado (CNV en Argentina y el mercado de cada país donde se lance).
2. Uso del nombre "S&P 500" y de datos del índice.
3. Uso de las marcas de SnapTrade, Binance y eToro en marketing (sus términos).
4. Promoción de una plataforma cripto en orgánico y, si se paga, la autorización previa de Meta y TikTok.
