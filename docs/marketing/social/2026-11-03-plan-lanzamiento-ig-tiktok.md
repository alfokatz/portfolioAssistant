# Plan de lanzamiento orgánico: Instagram y TikTok (5 semanas)

Fecha: 2026-11-03. Estado: borrador para aprobar, v2. Incluye la semana 1 de presentación y TODAS las correcciones de `docs/legal/reviews/2026-11-03-plan-redes.md` (los textos de compliance reemplazan a los anteriores). Las piezas nuevas (PR1 a PR5) usan copy propio armado con las reglas de ese review: pasan por `porty-compliance` antes de producir, igual que cualquier copy nuevo.
Alcance: solo orgánico. Sin ads pagas. Nada se publica sin aprobación del usuario.

Referencias: `PRODUCT.md` (quiet, precise, trustworthy), `DESIGN.md` (colores y tipografía), `docs/business/research/2026-11-02-que-paga-el-inversor-retail.md` (posicionamiento), `docs/legal/reviews/2026-11-03-plan-redes.md` (compliance).

---

## 0. Estado de cada pieza

Criterio: **lista para producir** = se arma con capturas generadas por los tests, el avatar y plantillas de marca, sin que el usuario grabe nada. **Necesita grabación del usuario** = hay que grabar pantalla o filmar (sección 4). **Bloqueada por abogado** = no se produce hasta que un abogado revise el punto indicado.

| Pieza | Estado | Qué falta |
|---|---|---|
| PR1 Video manifiesto "Esto es Porty" | Lista para producir | Compliance sobre el copy nuevo |
| PR2 Carrusel "Qué es Porty en 5 placas" | Lista para producir | Compliance sobre el copy nuevo |
| PR3 Imagen "Conocé a Porty" | Lista para producir | Compliance sobre el copy nuevo |
| PR4 Video "Cómo funciona en 3 pasos" | Necesita grabación del usuario | T11, T2, T3 (y T6 si se muestra el import) |
| PR5 Stories de presentación | Lista para producir | Compliance; el sticker de pregunta se modera a mano |
| P1 Brókers en un solo lugar | Bloqueada por abogado | Términos de marca de SnapTrade/Binance/eToro y promoción de plataforma cripto; después, grabación T1 y T2 |
| P2 Tres cosas que tu cartera no te cuenta | Bloqueada por abogado | Uso de "S&P 500" (placa 4) |
| P3 Preguntale a Porty | Necesita grabación del usuario | T3 y T4; leer entera cada respuesta del chat |
| P4 El informe del sábado | Lista para producir | Leer las dos muestras demo completas |
| P5 De una captura a tu cartera | Necesita grabación del usuario | T6, con pantalla de confirmación real |
| P6 Un número sin fuente es una opinión | Lista para producir | Placa 3 solo con respuesta real; si no sale, se omite |
| P7 Metas de ahorro | Lista para producir | Ninguna extra |
| P8 Qué es el PnL en 20 segundos | Lista para producir | Ninguna extra |
| P9 Diagnóstico de cartera | Bloqueada por abogado (condicional) | Solo si el Diagnóstico demo trae lenguaje de acción; si no, queda lista para producir |
| P10 Abrir la app 14 veces | Necesita grabación del usuario | T12 (escena actuada) |
| P11 Tu cartera vs un índice | Bloqueada por abogado | Uso de la marca y datos del S&P 500 |
| P12 Así se empieza en Porty | Necesita grabación del usuario | T11, T2, T3; medir el recorrido si se quiere decir "menos de un minuto" |
| Stories 6.2 y recurrentes | Necesita grabación del usuario | Capturas de T1, T2, T3; el resto sale de los tests |

---

## 1. Estrategia en una página

### Idea central
Un chat de IA sobre la cartera ya no es diferencial (IOL lanzó un MCP gratis con ChatGPT y Claude). No vendemos "tenemos IA". Estamos **presentando Porty al público**, y vendemos cuatro cosas:

1. **Tu cartera en un solo lugar**: brókers compatibles, un extracto o una captura.
2. **Las cifras salen de tu cartera y de datos de mercado**: Porty te explica tus números.
3. **Un asistente calmo** que te explica tu cartera en tu idioma.
4. **Contexto sobre cómo viene tu cartera**: informe semanal del sábado (Gold), diagnóstico de cartera.

Tono: calmo, preciso, sin hype. Se siente entendido, no apurado. Cero casino, cero "trading", cero urgencia.

### Qué es Porty, para quién, qué problema resuelve (base de las piezas de presentación)
- **Qué es:** una app con dashboard de portfolio (valor total, PnL, posiciones, gráficos) y un asistente de IA que se llama igual: Porty.
- **Para quién:** el inversor retail casual. Invierte en acciones o ETFs de forma personal, no es trader, abre la app en momentos puntuales (mañana, fin de semana, después de una noticia).
- **Qué problema resuelve:** la plata está repartida, los números son crípticos y mirar el total no alcanza para entender cómo viene la cartera.
- **Cómo se usa:** cargás tu cartera, la entendés de un vistazo, le preguntás a Porty.

### Qué es gratis y qué no (para no prometer de más)
- Free: cartera propia, Dashboard, chat (20 consultas por mes), Diagnóstico de cartera.
- Premium: conexión de bróker, comparar con el S&P 500, metas.
- Gold: informe semanal, noticias, varios brókers por SnapTrade.
- Regla: solo "Descargala gratis" (con aviso de planes pagos). Nunca "Probala gratis". Sin precios y sin "sin costo" a secas. No afirmar nada sobre Binance, el import por captura ni pruebas gratis.

### Objetivo medible (5 semanas)
- Primario: **300 instalaciones atribuidas** a contenido orgánico (link/código por red) y **40% de ellas con un import hecho, un bróker conectado o una primera pregunta al chat** en las primeras 48 h. Meta de partida: se ajusta con `porty-data-analyst` después de la semana 1 si la base real es muy distinta.
- Secundario: 1.500 clics al link de la bio; 3% de guardados sobre alcance en carruseles; 35% de retención a 3 s en reels/TikTok.

### Pilares de contenido
| Pilar | Qué hace | Peso |
|---|---|---|
| A. Mostrá el producto | Demos reales de pantalla: conectar, importar, diagnóstico, informe | 40% |
| B. "Preguntale a Porty" | Preguntas al asistente en cuenta demo, con cards | 25% |
| C. Educación simple | Un concepto en 20 s (PnL, diversificación, benchmark) | 20% |
| D. Momento del inversor casual | Humor calmo, identificación, sin burlarse del usuario | 15% |

La semana 1 es de presentación y mezcla los pilares A y B con una pieza de identidad (Conocé a Porty).

### Frecuencia
| Red / formato | Por semana | Notas |
|---|---|---|
| Instagram Reel | 2 | Reutiliza los TikTok sin marca de agua |
| Instagram carrusel | 1 | Pilares C y A, el que más se guarda |
| Instagram imagen única | 1 | Informe del sábado, cita de dato |
| Instagram Stories | 4 a 5 días, 2 a 4 placas | Secuencias de la sección 6 + encuestas |
| TikTok video | 3 | 2 propios + 1 reutilizado de Reel |
| TikTok carrusel de fotos | 0 a 1 | Solo si un carrusel de IG rinde bien |

Total: unas 7 piezas de feed por semana, de las cuales hay 5 de presentación y 12 prioritarias detalladas abajo; el resto son variantes y reutilizaciones.

### Identidad visual para imágenes (DESIGN.md)
- Fondo Warm Canvas `#FBFBFA`; tarjetas `#FFFFFF`; texto `#2F3437`; secundario `#787774`; acento terracota `#D98E5D` (solo detalle chico, nunca fondo grande); positivo `#346538` sobre `#EDF3EC`; negativo `#9F2F2D` sobre `#FDEBEC`.
- Tipografía: Plus Jakarta Sans; números con cifras tabulares (tnum). Títulos 600 a 700, cuerpo 400 a 500.
- Variante nocturna disponible: fondo `#171614`, texto `#E9E6E1`.
- Mucho aire, una idea por placa, sin gradientes, sin glassmorphism, sin números gigantes tipo "hero metric", sin verde neón.

---

## 2. Calendario de 5 semanas

Horarios sugeridos (hora Argentina), a validar con los primeros datos: Reels/TikTok 12:30 o 20:30; carrusel 19:00; Stories 9:00 y 21:00. El informe semanal va el sábado a la mañana.

Orden: la semana 1 es solo de presentación. Las piezas que ya estaban se reordenaron (semanas 2 a 5) y siguen con su numeración P1 a P12.

### Semana 1: "Esto es Porty" (presentación)
| Día | Red | Pieza |
|---|---|---|
| Lun | TikTok + Reel | PR1 Video manifiesto "Esto es Porty" |
| Lun | Stories | PR5 Stories de presentación, día 1 (sticker de pregunta) |
| Mar | IG imagen | PR3 "Conocé a Porty" |
| Mié | IG carrusel | PR2 "Qué es Porty en 5 placas" |
| Jue | Stories | Repost de PR2 + encuesta (ver 6.1, placa 2) |
| Vie | TikTok + Reel | PR4 "Cómo funciona en 3 pasos" |
| Sáb | Stories | Repost de PR4 + recordatorio de la caja de preguntas |
| Dom | Stories | Respuestas a "¿Qué te gustaría que Porty te explique?" + link |

### Semana 2: "Lo que hace Porty" (producto)
| Día | Red | Pieza |
|---|---|---|
| Lun | Stories | Encuesta + repaso de la semana 1 |
| Mar | TikTok + Reel | P1 Brókers en un solo lugar (si el abogado lo libera; si no, P5) |
| Mié | IG carrusel | P2 Tres cosas que tu cartera no te cuenta (si se libera; si no, P6) |
| Vie | TikTok + Reel | P3 Preguntale a Porty |
| Sáb | IG imagen | P4 El informe del sábado |
| Dom | Stories | Recap + link |

### Semana 3: "Cómo funciona" (producto)
| Día | Red | Pieza |
|---|---|---|
| Lun | Stories | Secuencia "cómo funciona" (6.2) |
| Mar | TikTok + Reel | P5 De una captura a tu cartera |
| Mié | IG carrusel | P6 Un número sin fuente es una opinión |
| Vie | TikTok + Reel | P7 Metas de ahorro |
| Sáb | IG imagen | Informe del sábado (nueva muestra demo) |
| Dom | Stories | Respuestas a la caja de preguntas |

### Semana 4: "Entendé tu cartera" (educación)
| Día | Red | Pieza |
|---|---|---|
| Lun | Stories | Encuesta: "¿Cada cuánto mirás tu cartera?" |
| Mar | TikTok + Reel | P8 Qué es el PnL en 20 segundos |
| Mié | IG carrusel | P9 Diagnóstico de cartera: qué mirar |
| Vie | TikTok + Reel | P10 Abrir la app 14 veces vs una por semana (humor calmo, escena actuada) |
| Sáb | IG imagen | P11 Tu cartera vs un índice (si el abogado lo libera; si no, informe del sábado) |
| Dom | Stories | Resultados de la encuesta + link |

### Semana 5: "Empezá a tu ritmo" (conversión sin presión)
| Día | Red | Pieza |
|---|---|---|
| Lun | Stories | "Lo que más preguntaron" + link |
| Mar | TikTok + Reel | P12 Así se empieza en Porty |
| Mié | IG carrusel | Mejor carrusel de las semanas 1 a 4, rehecho con lo aprendido (copy nuevo vuelve a compliance) |
| Vie | TikTok + Reel | Repetir el formato ganador (pilar con mejor retención) |
| Sáb | IG imagen | Informe del sábado |
| Dom | Stories | Cierre del mes con métricas propias de la cuenta (seguidores, respuestas a encuestas; nunca resultados de usuarios) + encuesta de qué quieren ver |

Regla: a partir de la semana 2 se duplica lo que supere la mediana de retención/guardados y se baja lo que no. Si una pieza bloqueada por abogado no se libera a tiempo, se corre la siguiente del mismo pilar; no se publica con el copy sin revisar.

---

## 3. Piezas de presentación (semana 1)

Convenciones generales: "Pantalla" es la captura o toma real (cuenta demo siempre). Hashtags pocos y relevantes. Toda pieza lleva el link con UTM (sección 7). Disclaimers A a E: textos exactos de la sección 3.2. CTA siempre "Descargala gratis" con la línea D.

### PR1. Video manifiesto "Esto es Porty"
- **Red y formato:** TikTok + Reel (video, 20 s). Armado con capturas de los tests y el avatar, sin grabación de pantalla. Voz en off calma, o solo texto y música instrumental de la biblioteca comercial.
- **Objetivo:** que alguien que no nos conoce entienda en 20 s qué es, para quién es y qué problema resuelve.
- **Hook (0 a 2 s):** texto "¿Tu cartera te cuenta lo que pasa?" sobre fondo canvas, avatar de Porty (estado idle) chico.
- **Guion:**
  - 0-2 s: hook.
  - 2-6 s: voz: "Esto es Porty." Avatar en estado idle. Texto: "Tu cartera en un solo lugar."
  - 6-11 s: voz: "Es para quien invierte sin vivir pegado al mercado." Captura del Dashboard, sin zoom a ninguna posición.
  - 11-16 s: voz: "Le preguntás a Porty y te explica tus números en tu idioma." Captura de una card del chat (leída entera antes).
  - 16-20 s: avatar en estado answered. Voz: "Descargala gratis." Texto: "Porty. Tu asistente de inversiones."
- **Pantalla real:** Dashboard consolidado; card de análisis del chat. Avatar: `porty_idle.svg`, `porty_answered.svg`.
- **Texto en pantalla:** "Tu cartera en un solo lugar", "Para el inversor casual", "Hecho con IA".
- **Disclaimer en la imagen:** "Cuenta demo" desde el segundo 0 hasta el final; A + C + D en los últimos 3 s (28 px mínimo sobre 1080, dentro de la zona segura).
- **Caption:** "Porty es una app con un dashboard de tu cartera y un asistente que te explica tus números en tu idioma. Para quien invierte sin vivir pegado al mercado. Es una IA y puede equivocarse: verificá lo importante. Algunas funciones son de planes pagos. Cuenta demo. No es asesoramiento financiero. Descargala gratis, link en la bio."
- **CTA:** "Descargala gratis, link en la bio."
- **Hashtags:** #porty #inversiones #finanzaspersonales #inversorcasual #argentina

---

### PR2. Qué es Porty en 5 placas
- **Red y formato:** IG carrusel (5 placas 1080x1350, imagen de marca + captura).
- **Objetivo:** guardados y visitas al perfil; la pieza que se guarda para explicar Porty.
- **Hook (placa 1):** "Qué es Porty, en cinco placas."
- **Texto por placa:**
  1. **Qué es.** "Porty es una app para ver tu cartera y un asistente que te la explica." Avatar `porty_idle.svg` chico.
  2. **Para quién.** "Para quien invierte sin vivir pegado al mercado." Sin captura. Pie A.
  3. **Qué problema resuelve.** "Mirar solo el total no alcanza para entender cómo viene tu cartera." Captura del Dashboard. Pie A.
  4. **Cómo se usa.** "Cargás tu cartera, la mirás de un vistazo, le preguntás a Porty." Captura del chat con una card. Pie A + C.
  5. **Cómo empezar.** "Descargala gratis. Algunas funciones son de planes pagos." Avatar `porty_answered.svg`. Pie A + C + D.
- **Pantalla real:** Dashboard, chat con card (T2, T3 o captura del test de cards).
- **Caption:** "Qué es Porty, para quién es y cómo se usa, en cinco placas. Es una IA y puede equivocarse: verificá lo importante. Algunas funciones son de planes pagos. Cuenta demo. No es asesoramiento financiero."
- **CTA:** "Guardalo y descargala gratis (link en la bio)."
- **Hashtags:** #porty #inversiones #educacionfinanciera #finanzaspersonales #portfolio

---

### PR3. Conocé a Porty
- **Red y formato:** IG imagen única (1080x1350) + versión Stories (1080x1920). Imagen de marca, sin captura de pantalla.
- **Objetivo:** identidad; que la gente asocie la cara de Porty con el asistente.
- **Hook / texto:** "Conocé a Porty." Debajo, una línea: "Tu asistente de inversiones. Te explica tu cartera con calma."
- **Visual:** fondo canvas `#FBFBFA`, el avatar centrado y grande, en estado idle (`assets/porty-avatar/states/porty_idle.svg`, variante clara; usar `porty_idle_mono_dark.svg` en la versión nocturna `#171614`). Acento terracota solo en un detalle chico. Sin gradientes. Opcional para el carrusel o las stories: los otros estados (`porty_thinking.svg`, `porty_answered.svg`) como serie "Porty mientras piensa / cuando responde".
- **Pie:** "Porty usa IA y puede equivocarse. Verificá la información importante." (C). No hay números ni funciones pagas: no lleva B ni D.
- **Caption:** "Conocé a Porty, el asistente de la app. Te explica tu cartera en tu idioma, con calma. Porty usa IA y puede equivocarse: verificá la información importante. No es asesoramiento financiero. Descargala gratis, link en la bio. Algunas funciones son de planes pagos."
- **CTA:** "Descargala gratis, link en la bio."
- **Hashtags:** #porty #inversiones #asistenteIA #finanzaspersonales

---

### PR4. Cómo funciona en 3 pasos
- **Red y formato:** TikTok + Reel (video, 30 s). Grabación de pantalla (T11, T2, T3).
- **Objetivo:** que se entienda el uso concreto; descarga.
- **Hook (0 a 2 s):** texto "Así se usa Porty, en tres pasos." Sin numeración decorativa: ícono más frase por paso. Cuenta demo visible desde 0 s.
- **Guion:**
  - 0-2 s: hook.
  - 2-10 s: **Cargás tu cartera.** Pantalla de elegir cómo cargar (importar con captura; conectar un bróker es de planes pagos). Voz: "Primero, cargás tu cartera."
  - 10-19 s: **La entendés de un vistazo.** Dashboard con scroll lento, sin zoom a ninguna posición, ordenado por tamaño. Voz: "Después la ves toda junta, de un vistazo."
  - 19-27 s: **Le preguntás a Porty.** Chat con una pregunta genérica ("¿Cómo me fue este mes?") y su card. Voz: "Y le preguntás lo que quieras entender."
  - 27-30 s: avatar + "Descargala gratis."
- **Pantalla real:** Onboarding/carga, Dashboard, Chat. No usar T5 (simulación).
- **Texto en pantalla:** "Cargá tu cartera", "Entendela de un vistazo", "Preguntale a Porty", "Hecho con IA". No decir "en 60 segundos" ni otro tiempo.
- **Disclaimer en la imagen:** "Cuenta demo" desde 0 s; A + C + D durante los últimos 3 s (B si se muestra rendimiento en la card).
- **Caption:** "Así se usa Porty: cargás tu cartera, la entendés de un vistazo y le preguntás a Porty. Podés cargarla con un import; conectar brókers es de los planes pagos. Es una IA y puede equivocarse: verificá lo importante. Cuenta demo. No es asesoramiento financiero."
- **CTA:** "Descargala gratis, link en la bio."
- **Hashtags:** #porty #tutorial #inversiones #finanzaspersonales #argentina

---

## 3.1 Las 12 piezas prioritarias (con correcciones de compliance aplicadas)

---

### P1. Brókers en un solo lugar
- **Red y formato:** TikTok + Reel (video, 25 s). Grabación de pantalla. **Bloqueada por abogado** (marcas de proveedores, cripto).
- **Objetivo:** descarga y conexión de bróker (función de planes pagos).
- **Hook (0 a 2 s):** texto "¿Tu plata está repartida en varias apps?" con íconos genéricos de apps (nunca logos reales) y un swipe.
- **Guion:**
  - 0-2 s: hook, voz: "Si tu plata está repartida en varias apps, mirá esto."
  - 2-8 s: pantalla *Conectar bróker* (lista vista tal cual, sin zoom ni foco en ningún proveedor, grabada solo hasta la pantalla previa a autenticar). Nunca "Conectá tu Binance".
  - 8-16 s: Dashboard con el total consolidado y posiciones de varias fuentes.
  - 16-22 s: voz: "Podés verla junta: cada posición con su bróker." (usar solo si el Dashboard muestra el bróker de cada posición; si no, "Podés verla toda junta.")
  - 22-25 s: avatar de Porty (estado idle) + CTA.
- **Pantalla real:** Conectar bróker; Dashboard consolidado.
- **Texto en pantalla:** "Una sola vista", "Brókers compatibles".
- **Disclaimer en la imagen:** "Cuenta demo" desde 0 s; A + D + E en los últimos 3 s.
- **Caption:** "Una sola vista para tu cartera, aunque esté repartida en varios brókers compatibles. Conectar brókers es parte de los planes pagos. La disponibilidad depende del país y del bróker. Cuenta demo. No es asesoramiento financiero."
- **CTA:** "Descargala gratis, link en la bio."
- **Hashtags:** #inversiones #finanzaspersonales #argentina #inversorcasual (sin #portfolio, compite con cripto)

---

### P2. Tres cosas que tu cartera no te cuenta
- **Red y formato:** IG carrusel (6 placas, imagen de marca + captura). **Bloqueada por abogado** (nombre S&P 500 en placa 4). Si el abogado lo aprueba solo con atribución, se sigue; si no, se reemplaza la placa 4 por "un índice de referencia" sin nombre.
- **Objetivo:** guardados y visitas al perfil, luego descarga.
- **Hook (placa 1):** "Tu cartera tiene tres cosas que el total no te muestra."
- **Texto por placa (pie A en todas las placas con captura):**
  1. Hook. Fondo canvas, título grande, avatar de Porty chico.
  2. "1. Cuánto pesa cada activo." Captura *Asignación*.
  3. "2. Cuánto depende de un solo lugar." Misma captura, recorte del mayor peso.
  4. "3. Cómo te fue contra un benchmark." Captura del gráfico comparativo (línea gris del S&P 500). Pie B (comparación de rendimiento). Esta comparación es una función Premium.
  5. "Son tus propios datos, calculados y explicados por Porty." Captura *Diagnóstico de cartera*. Pie A + C.
  6. CTA: "Porty te lo explica en tu idioma. Descargala gratis. Link en la bio." Pie A + D + E (S&P 500).
- **Pantalla real:** Asignación, comparativo con benchmark, Diagnóstico de cartera.
- **Caption:** "Mirar solo el total es como mirar solo la nota final. Acá van tres cosas más para mirar. La comparación con el S&P 500 es de los planes pagos. Cuenta demo. Rendimientos pasados no garantizan resultados futuros. No es asesoramiento financiero."
- **CTA:** "Guardalo y descargala gratis (link en la bio)."
- **Hashtags:** #educacionfinanciera #inversiones #diversificacion #portfolio #finanzas

---

### P3. Preguntale a Porty
- **Red y formato:** TikTok + Reel (video, 30 s). Grabación de pantalla del chat.
- **Objetivo:** uso del asistente y descarga.
- **Hook:** texto "Esto le preguntaría a mi cartera de ejemplo: ¿cómo me fue este mes?" (cuenta demo visible desde 0 s). Alternativa: "Preguntale a tu cartera en lenguaje normal."
- **Guion:**
  - 0-3 s: pregunta tipeada: "¿Cómo me fue este mes?"
  - 3-12 s: respuesta de Porty con card de análisis.
  - 12-20 s: segunda pregunta: "¿Cómo me fue contra el S&P 500?" Card de comparar (función Premium).
  - 20-27 s: voz: "Porty no te dice qué hacer: te muestra tus números y te los explica."
  - 27-30 s: CTA.
- **Pantalla real:** Chat con cards de análisis y comparar. Leer cada respuesta completa; descartarla si dice "te conviene", "comprá", "sumá X" o propone tickers.
- **Texto en pantalla:** "Respuestas basadas en tus datos", "Hecho con IA".
- **Disclaimer en la imagen:** "Cuenta demo" desde 0 s; B + C durante todo el video o, como mínimo, los últimos 3 s.
- **Caption:** "Preguntale a tu cartera en lenguaje normal. Las respuestas parten de tus datos y las genera una IA que puede equivocarse: verificá lo importante. Comparar con un índice es de los planes pagos. Cuenta demo. Rendimientos pasados no garantizan resultados futuros. No es asesoramiento financiero."
- **CTA:** "Descargala gratis, link en la bio."
- **Hashtags:** #asistenteIA #inversiones #finanzaspersonales #porty #argentina

---

### P4. El informe del sábado
- **Red y formato:** IG imagen única (1080x1350) + versión en Stories.
- **Objetivo:** mostrar el hábito y generar interés en descargar.
- **Hook:** "Los sábados, cinco minutos y listo."
- **Texto:** captura del *Informe semanal* centrada sobre canvas, con tres líneas debajo que describan solo las secciones del informe capturado, por ejemplo: "Qué pasó esta semana. Qué se movió más. Lo que hay en agenda." (sacar "agenda" si el informe no tiene esa sección; nunca "qué mirar la próxima"). Aviso en la imagen: "Informe semanal: plan Gold" (D).
- **Pantalla real:** Informe semanal (`weekly_report_samples.json`). Leer las dos muestras demo completas; si una trae lenguaje de "qué hacer", no se usa.
- **Caption:** "Una vez por semana, un resumen de tu cartera, sin ruido. El informe semanal completo es del plan Gold. Cuenta demo. No es asesoramiento financiero."
- **CTA:** "Descargala gratis. Link en la bio."
- **Hashtags:** #inversiones #finanzaspersonales #rutina #portfolio

---

### P5. De una captura a tu cartera
- **Red y formato:** TikTok + Reel (video, 25 s). Grabación de pantalla. Publicar solo si T6 muestra una pantalla de confirmación real antes de guardar.
- **Objetivo:** descarga y primer import.
- **Hook:** texto "¿Tu bróker no se conecta? Sacale una captura." mientras se ve una captura de posiciones (de demo).
- **Guion:**
  - 0-3 s: hook.
  - 3-10 s: pantalla *Importar con captura*: se elige la imagen.
  - 10-18 s: Porty lee y muestra las posiciones para confirmar.
  - 18-23 s: cartera cargada en Dashboard.
  - 23-25 s: CTA.
- **Pantalla real:** Importar con captura; pantalla de confirmación; Dashboard.
- **Texto en pantalla:** "Revisás antes de guardar" (solo si se verifica), "También sin conectar un bróker".
- **Disclaimer en la imagen:** A + C. No decir "seguro" ni "privado".
- **Caption:** "Si tu bróker no se conecta, podés cargar tu cartera con una captura o un extracto. Porty lee la imagen con IA y puede equivocarse: vos revisás y confirmás cada dato antes de guardar. Tapá tu nombre y tu número de cuenta antes de subirla. Cuenta demo."
- **CTA:** "Descargala gratis, link en la bio."
- **Hashtags:** #inversiones #tutorial #finanzaspersonales #portfolio #truco

---

### P6. Un número sin fuente es una opinión
- **Red y formato:** IG carrusel (5 placas).
- **Objetivo:** confianza y guardados.
- **Hook:** "Un número sin fuente es una opinión." (es una frase, no promete nada de Porty).
- **Texto por placa (pie A + C en todas):**
  1. Hook.
  2. "Cuando Porty busca en la web o trae noticias, te muestra el medio, la fecha y el link." Captura de la lista FUENTES del pie del mensaje o de una card de noticias (noticias: plan Gold, con D en el pie).
  3. "Si no encuentra un dato, lo aclara." Solo con captura real (caso de noticias vacías o respuesta de límite real, nunca maquetada a mano). Si no sale, se omite la placa.
  4. "Tu cartera, tus números." Captura del Dashboard.
  5. CTA "Descargala gratis" + A + C + D.
- **Pantalla real:** Chat con FUENTES o noticias, Dashboard.
- **Caption:** "Porty está pensado para aclarar cuándo no tiene un dato en lugar de inventarlo. Es una IA y puede equivocarse: verificá lo importante. Noticias: plan Gold. Cuenta demo. No es asesoramiento financiero."
- **CTA:** "Descargala gratis, link en la bio."
- **Hashtags:** #transparencia #inversiones #finanzas #asistenteIA

---

### P7. Metas de ahorro
- **Red y formato:** Reel + TikTok (video, 20 s). Animación de capturas con ffmpeg (sin grabación).
- **Objetivo:** descarga, atraer al usuario que ahorra más que lo que invierte.
- **Hook:** texto "¿Cuánto te falta para eso que querés?"
- **Guion:**
  - 0-2 s: hook sobre fondo canvas.
  - 2-10 s: captura *Metas* (meta demo, ej. "Viaje", "Entrada"), con zoom suave al progreso.
  - 10-16 s: captura de una meta con avance y fecha estimada. Mostrar el supuesto de la proyección si la card lo muestra.
  - 16-20 s: CTA.
- **Pantalla real:** Metas de ahorro (función Premium).
- **Texto en pantalla:** "Poné la meta", "Mirá el avance", y al mostrar la fecha: "Estimación, no garantía". Aviso: "Metas: planes pagos".
- **Disclaimer en la imagen:** A + D.
- **Caption:** "Una meta, un avance, una fecha estimada. La fecha se calcula con supuestos y es una estimación, no una garantía. Metas es de los planes pagos. Cuenta demo."
- **CTA:** "Descargala gratis y probá Metas con tu plan." (corta: "Armá tu meta en la app. Función de planes pagos.")
- **Hashtags:** #metas #ahorro #finanzaspersonales #inversiones

---

### P8. Qué es el PnL en 20 segundos
- **Red y formato:** TikTok + Reel (video, 20 s). Animación de capturas + voz.
- **Objetivo:** alcance y seguidores; puerta de entrada educativa.
- **Hook:** texto "PnL: la palabra que todos usan y pocos explican."
- **Guion:**
  - 0-3 s: hook.
  - 3-10 s: voz: "PnL es lo que ganaste o perdiste respecto de lo que pagaste." Captura de una posición con PnL en verde `#346538`, sin nombrar el activo.
  - 10-16 s: voz: "Un PnL negativo es una foto de hoy: por sí solo no dice si una decisión fue buena o mala." Misma posición en rojo `#9F2F2D` (ejemplo demo).
  - 16-20 s: voz: "En Porty lo ves por posición y total." CTA.
- **Pantalla real:** Dashboard / detalle de posición con PnlBadge.
- **Texto en pantalla:** "PnL no realizado = valor actual − lo que pagaste".
- **Disclaimer en la imagen:** A.
- **Caption:** "PnL en criollo. Ejemplo con datos de cuenta demo. No es asesoramiento financiero."
- **CTA:** "Más conceptos simples en el perfil."
- **Hashtags:** #educacionfinanciera #pnl #inversiones #aprendeconmigo

---

### P9. Diagnóstico de cartera: qué mirar
- **Red y formato:** IG carrusel (7 placas). Función Free (no lleva D). **Bloqueada por abogado solo si** el Diagnóstico demo contiene lenguaje de acción ("considerá", "reducí", "diversificá con X").
- **Objetivo:** descarga; mostrar la función más diferencial.
- **Hook:** "Si tuvieras que revisar tu cartera en 1 minuto, mirá esto."
- **Texto por placa (pie A):**
  1. Hook.
  2. "Concentración: cuánto pesa lo más grande." Captura *Diagnóstico*, sección concentración.
  3. "Diversificación: cuántas cosas distintas tenés de verdad."
  4. Solo secciones que existen en la captura real, por ejemplo "Moneda: en qué está expresada tu cartera". Sacar "Costos" si el Diagnóstico no los muestra.
  5. "Cómo lo explica Porty (IA, puede equivocarse)." Captura de la explicación en lenguaje simple. Pie C.
  6. "Esto es información, no una recomendación." Disclaimer visible + C.
  7. CTA "Descargala gratis".
- **Pantalla real:** Diagnóstico de cartera (`portfolio_diagnosis_screenshots_test.dart`). Leer entero el texto demo antes de producir.
- **Caption:** "Un chequeo de una página para entender qué tenés. Describe tu cartera: no te dice qué comprar. Cuenta demo. No es asesoramiento financiero."
- **CTA:** "Pedí tu diagnóstico en la app."
- **Hashtags:** #diagnostico #portfolio #inversiones #educacionfinanciera

---

### P10. Abrir la app 14 veces vs una por semana
- **Red y formato:** TikTok + Reel (video, 15 s). Humor calmo, grabación de pantalla + una toma de mano. Rotulada como escena actuada.
- **Objetivo:** alcance, identificación, seguidores.
- **Hook:** texto "Mirar la cartera cada 10 minutos" sobre un teléfono en mano (voz impersonal, sin "yo").
- **Guion:**
  - 0-4 s: toma de mano abriendo y cerrando apps, contador "14" subiendo. Texto "Escena actuada".
  - 4-9 s: corte: texto "Alternativa: un informe el sábado (plan Gold)."
  - 9-13 s: captura del Informe semanal.
  - 13-15 s: avatar de Porty + CTA.
- **Pantalla real:** Informe semanal.
- **Texto en pantalla:** "Mirar más no siempre es entender más." Pie A en los últimos 3 s.
- **Caption:** "No hace falta mirar la cartera cada 10 minutos para entenderla. El informe semanal es del plan Gold. Cuenta demo. No es asesoramiento financiero."
- **CTA:** "Descargala gratis, link en la bio."
- **Hashtags:** #humor #inversores #finanzaspersonales #relatable

---

### P11. Tu cartera vs un índice
- **Red y formato:** IG imagen única (1080x1350) + Stories. **Bloqueada por abogado** (marca y datos del S&P 500).
- **Objetivo:** guardados, mostrar contexto de rendimiento.
- **Hook:** "¿Mejor o peor que un índice de referencia? Se mira así."
- **Texto:** captura del gráfico comparativo (línea charcoal de la cartera vs línea gris `#B0ABA8` del benchmark), con el período indicado ("Últimos 12 meses, datos demo") y la línea: "Un benchmark es una referencia, no una meta ni una recomendación. Tu cartera puede tener otros objetivos, otra moneda y otro riesgo." Curva demo sin diferencia grande ni a favor ni en contra; evitar el mensaje "ganale al mercado". Verificar con assistant-dev/backend-dev qué benchmark se usa: si es un ETF que replica el índice, decirlo así.
- **Pie:** B + D + E. Sin logo de S&P.
- **Pantalla real:** gráfico comparativo / card "comparar" del chat (función Premium).
- **Caption:** "Un número suelto no dice mucho. Contra un benchmark, tiene contexto. Cuenta demo. Rendimientos pasados no garantizan resultados futuros. La comparación con el S&P 500 es de los planes pagos. No es asesoramiento financiero."
- **CTA:** "Descargala gratis. Link en la bio."
- **Hashtags:** #sp500 #benchmark #inversiones #educacionfinanciera

---

### P12. Así se empieza en Porty
- **Red y formato:** TikTok + Reel (video, 40 s). Grabación de pantalla.
- **Objetivo:** descarga y activación.
- **Hook:** texto "Así se empieza en Porty." Sin cronómetro. Solo se usa "Tu cartera en menos de un minuto" si el equipo mide el recorrido completo 3 veces y todas dan menos de 60 s (guardar la medición en este plan).
- **Guion:**
  - 0-3 s: hook.
  - 3-12 s: *Onboarding* (pantallas de bienvenida con avatar de Porty).
  - 12-25 s: elegir cómo cargar: importar (o conectar bróker, de planes pagos).
  - 25-35 s: Dashboard con cartera demo + una pregunta al chat (leer entera la respuesta antes de usarla).
  - 35-40 s: CTA.
- **Pantalla real:** Onboarding, Conectar bróker/Importar, Dashboard, Chat. Mail de T11 de una casilla demo sin nombre real.
- **Texto en pantalla:** "Paso 1", "Paso 2", "Listo".
- **Disclaimer en la imagen:** A + D (+ C si se ve el chat).
- **Caption:** "Así se empieza. Podés cargar tu cartera con un import; conectar brókers es de los planes pagos. Cuenta demo. No es asesoramiento financiero."
- **CTA:** "Descargala gratis, link en la bio."
- **Hashtags:** #porty #tutorial #inversiones #finanzaspersonales #argentina

---

## 3.2 Disclaimers aprobados (compliance, sección 2 del review)

- **A:** `Cuenta demo. No es asesoramiento financiero.`
- **B (rendimiento o comparación):** `Cuenta demo. Rendimientos pasados no garantizan resultados futuros. No es asesoramiento financiero.`
- **C (IA):** `Porty usa IA y puede equivocarse. Verificá la información importante.`
- **D (planes):** `Algunas funciones son de planes pagos.`
- **E (marcas):** `S&P 500® es marca registrada de S&P Dow Jones Indices LLC. Binance, eToro y SnapTrade son marcas de sus titulares, usadas solo para indicar compatibilidad.` (revisión humana)

Dónde: videos, texto fijo en la imagen (mínimo 28 px sobre 1080, contraste 4.5:1, dentro de la zona segura, fuera de los 340 px de abajo y de los botones laterales), "Cuenta demo" desde el segundo 0 y A o B durante los últimos 3 s como mínimo; además, siempre, en el caption. Carruseles e imagen única: en el pie de cada placa con comparación, rendimiento o PnL y en la última. Stories: en cada placa con números o una función, y en la última. C en toda pieza donde se vea una respuesta del chat. D en toda pieza que muestre Premium o Gold. E donde se vea un logo o nombre de tercero.

Funciones pagas: se nombran siempre como tales (conexión de bróker: Premium/Gold; comparar con el S&P 500: Premium; metas: Premium; informe semanal: Gold; noticias: Gold).

---

## 4. Tomas para grabar la pantalla del teléfono

**Preparación (una vez):**
- Cuenta demo de Porty, **nunca una cuenta real**. Modo claro para todo (tanda extra en modo oscuro para las Stories nocturnas).
- Teléfono en vertical 9:16, modo no molestar, batería llena, barra de estado limpia (hora 9:41, sin notificaciones), brillo alto, grabadora nativa.
- Revisar cada archivo antes de editar: barra de estado, portapapeles, ajustes, mail, ID de cuenta, notificaciones.
- Datos demo ficticios y redondeados: 8 a 10 posiciones mezcladas (ETFs amplios, algunas acciones grandes, un bono, una cripto), repartidas en 2 o 3 "brókers" demo, con mezcla de verde y rojo. PnL moderado: como máximo +/-15% en cualquier posición o total. Posiciones ordenadas por tamaño, no por rendimiento. Ningún ticker se nombra por voz ni en texto en pantalla, y no se hace zoom a una posición concreta.
- Metas demo: "Viaje" (avance 45%) y "Entrada de un depto" (avance 20%).
- Una captura de posiciones armada con datos inventados para la toma de importar.

**Tomas (grabar cada una dos veces, con pausas de 1 s entre toques):**

| Toma | Orden y qué tocar | Dura | Piezas |
|---|---|---|---|
| T1 Conectar bróker | Ajustes > Conectar bróker > abrir la lista > volver. Grabar solo hasta la lista y la pantalla previa a autenticar (o con cuenta sandbox del proveedor si existe); nunca iniciar sesión real | 15 s | P1, P12, stories |
| T2 Dashboard consolidado | Abrir app > mostrar total > scroll lento por posiciones > detalle y PnL | 15 s | PR1, PR4, P1, P8, P12 |
| T3 Chat: "¿Cómo me fue este mes?" | Abrir chat > escribir la pregunta > esperar la card > scroll lento. Leer la respuesta entera: descartar si hay lenguaje de recomendación | 15 s | PR1, PR4, P3 |
| T4 Chat: comparar | Escribir "¿Cómo me fue contra el S&P 500?" > card de comparar | 12 s | P3, P11 |
| T5 Chat: simulación | **No usar en el feed** (puede mostrar tickers candidatos). En stories solo si la card no muestra candidatos con nombre. Para proyección usar T9 | 12 s | stories (condicional) |
| T6 Importar con captura | Importar > elegir captura > esperar lectura > pantalla de confirmación > guardar | 20 s | PR4 (opcional), P5, P12 |
| T7 Diagnóstico de cartera | Abrir Diagnóstico > scroll lento por secciones > explicación | 20 s | P9, stories |
| T8 Informe semanal | Abrir el informe > scroll lento | 12 s | P4, P10 |
| T9 Metas | Metas > abrir "Viaje" > avance y fecha estimada | 10 s | P7 |
| T10 Watchlist | Watchlist > agregar un activo genérico, sin destacarlo > ver la lista | 10 s | stories |
| T11 Onboarding | Cuenta nueva con una casilla demo sin nombre real: recorrer onboarding completo | 25 s | PR4, P12, stories |
| T12 Mano y teléfono | Mano abriendo y cerrando apps (sin datos reales), teléfono sobre una mesa | 10 s | P10 |

Reglas de grabación: gestos lentos, sin zoom con los dedos, sin notificaciones ni datos personales. Pasar los archivos sin editar; la edición (subtítulos, voz, audio) se hace en CapCut.

---

## 5. Capturas a generar desde test/screenshots (coordinador)

Con datos demo, modo claro y oscuro, resolución alta (por lo menos 1170x2532), recortes sin marco de dispositivo para las plantillas HTML.

| Captura | Test de origen | Para |
|---|---|---|
| Dashboard consolidado | test de Dashboard existente | PR1, PR2, PR5 |
| Cards del chat: análisis, comparar | `genui_catalog_screenshots_test.dart` | PR1, PR2, PR5, P2, P3, P6, P11 |
| Diagnóstico de cartera (completo y por sección) | `portfolio_diagnosis_screenshots_test.dart` | P2, P9, Stories |
| Informe semanal (2 muestras distintas) | `weekly_report_screenshots_test.dart` + `weekly_report_samples.json` | P4, P10, Stories |
| Metas de ahorro (lista y detalle) | `goals_screenshots_test.dart` | P7 |
| Asignación | `allocation_screenshots_test.dart` | P2 |
| Conectar bróker (lista) | `connect_broker_screenshots_test.dart`, `snaptrade_screenshots_test.dart`, `binance_screenshots_test.dart`, `etoro_screenshots_test.dart` | P1, P12, Stories (sin foco en un proveedor) |
| Importar extracto/captura | `statement_import_screenshots_test.dart` | PR4, P5 |
| Watchlist | `watchlist_screenshots_test.dart` | Stories |
| Onboarding (todas las pantallas) | `onboarding_screenshots_test.dart` | PR4, P12, Stories |
| Avatar de Porty (estados: idle, thinking, answering, answered, concerned, error; variantes claras, oscuras y mono) | `assets/porty-avatar/states` (+ `porty_splash_assets_test.dart`) | PR1, PR2, PR3, PR5 y placas de cierre |
| Auth (opcional) | `auth_screenshots_test.dart` | Stories |

Notas: no usar `paywall_screenshots_test.dart` en ninguna pieza hasta que `porty-monetization` confirme planes y precios. Una respuesta del chat que reconozca "no tengo ese dato" (P6, placa 3) solo si sale real con datos demo, nunca maquetada a mano.

Plantillas HTML de marca: 1080x1350 (feed), 1080x1920 (stories y portada de reel), y el set de carruseles. Fondo `#FBFBFA`, Plus Jakarta Sans, un solo mensaje por placa, avatar de Porty en la placa final y disclaimer en el pie.

---

## 6. Stories

Formato 1080x1920. Zona segura: 250 px arriba y 340 px abajo. Una idea por placa. Disclaimer A (o B si hay números) en las placas con números o función, y en la última; C en las placas del chat.

### 6.1 PR5. Stories de presentación (5 placas, día 1 de la semana 1)
1. **Hola, soy Porty.** Avatar (`porty_idle.svg`) + "Hola, soy Porty. Te ayudo a entender tu cartera." Sticker "Seguime" (sin cuenta regresiva, que crea urgencia).
2. **Para quién y qué problema.** "Si invertís sin vivir pegado al mercado y tu plata está repartida en varias apps, esto es para vos." Sticker de **encuesta**: "¿En cuántos lugares tenés tu plata? 1 / 2 o más".
3. **Qué hace.** Captura Dashboard consolidado + "Tu cartera en un solo lugar." Pie A.
4. **Cómo se usa.** Captura del chat con una card + "Cargás tu cartera, la entendés de un vistazo, le preguntás a Porty." Sticker de **pregunta**: "¿Qué te gustaría que Porty te explique? No me cuentes montos ni datos de tu cuenta." Pie A + C. Las respuestas salen el domingo, sin handle ni foto de quien preguntó, salvo permiso.
5. **Cierre.** Avatar (`porty_answered.svg`) + "Descargala gratis. Link abajo." Sticker de **link** con el UTM de Stories. Pie A + D.

### 6.2 Secuencia "Cómo funciona" (6 placas, semana 3)
1. **Hook.** "Cómo funciona Porty." Ícono y frase, sin numeración decorativa.
2. **Cargá tu cartera.** Captura Conectar bróker; texto "Conectá un bróker (planes pagos) o importá con una captura." Sticker de **encuesta**: "¿Qué usás hoy? Bróker conectado / Captura o planilla".
3. **Mirá el panorama.** Captura Dashboard.
4. **Preguntale a Porty.** Captura del chat. Sticker de **pregunta**: "¿Qué le preguntarías a tu cartera?". Pie C.
5. **Recibí el informe.** Captura Informe semanal. Texto "Los sábados, un resumen (plan Gold)."
6. **Empezá.** "Descargala gratis. Link abajo." Sticker de **link** (UTM Stories) + A + D. Guardar la secuencia en Destacados como "Cómo funciona" (la de presentación PR5 va en Destacados como "Qué es Porty").

### Stories recurrentes y caja de preguntas
Resultados de encuestas (agregados, nunca capturas con handles), repost del reel del día, respuestas a la caja de preguntas. Las preguntas y mensajes son datos personales: se usan solo para responder, sin repostear con nombre o foto sin permiso.

Plantilla de respuesta a "¿conviene comprar X?": "No te puedo decir si conviene comprar X: Porty no da recomendaciones. Lo que sí te explico es cómo mirar [concepto: peso en la cartera, diversificación, etc.] para decidir con tu propio criterio. No es asesoramiento financiero." Sin nombrar ni valorar el activo.

---

## 7. Cómo medir

### Atribución de descargas
- **Link con UTM** (landing o link de instalación inteligente) por red y formato:
  - `?utm_source=instagram&utm_medium=organic&utm_campaign=lanzamiento_nov26&utm_content=bio`
  - `...utm_source=tiktok&utm_medium=organic&utm_campaign=lanzamiento_nov26&utm_content=bio`
  - `utm_content` cambia por pieza: `reel_pr1`, `carrusel_pr2`, `imagen_pr3`, `reel_pr4`, `story_presentacion`, `reel_p1`, etc.
- **Un solo link en la bio** por red, y un link por secuencia de Stories (sticker de link) para aislar su efecto.
- **Código de referencia por red** (`IG` y `TT`) cargable en el onboarding; `porty-data-analyst` tiene que confirmar si hay campo disponible (hoy no verificado).
- **Pregunta de origen** en el onboarding ("¿Cómo nos conociste?"): Instagram / TikTok / amigo / tienda / otro. Es un dato nuevo: compliance lo refleja en `data-inventory.md`, la Política de Privacidad y las etiquetas de las tiendas. La landing con analytics necesita aviso de cookies/medición.
- Instalaciones sin atribuir: comparar el pico de "nombre de marca" en las tiendas con el día de publicación de cada pieza (`porty-aso-specialist`).
- Pedir a `porty-data-analyst` que confirme los eventos: instalación, bróker conectado/importado, primera pregunta al chat. Si alguno no existe, queda pendiente de implementar.

### Métricas por pieza
| Formato | Métricas | Referencia de alerta |
|---|---|---|
| Reel / TikTok | Retención a 3 s, % que lo ve completo, compartidos, guardados, clics al perfil, seguidores nuevos | Retención 3 s < 30%: cambiar hook |
| Carrusel | Guardados, compartidos, % que llega a la última placa, visitas al perfil | Guardados < 2% del alcance: revisar el tema |
| Imagen única | Guardados, compartidos, clics en el link | Sin guardados: no repetir formato |
| Stories | Salidas por placa, respuestas a stickers, clics al link, avance por placa | Salidas altas en la placa 2: acortar |
| Cuenta | Seguidores, visitas al perfil, clics al link de la bio | Revisar semanalmente |
| Negocio | Instalaciones atribuidas, % con import/bróker/primera pregunta en 48 h, preguntas al chat por usuario nuevo | Meta de la sección 1 |

Para la semana 1, además: qué pregunta de la caja "¿Qué te gustaría que Porty te explique?" se repite más (alimenta el pilar C) y qué placa de PR2 se guarda más.

### Revisión
- Cada lunes (15 minutos): top 3 y bottom 3 de la semana, qué hook funcionó, qué pilar subir.
- Fin de la semana 5: tabla por pilar con costo en horas, instalaciones atribuidas y calidad de activación, para decidir si se sigue, se ajusta o se pasa a pagas (decisión aparte; si pasa a pagas, todo se revisa de nuevo en compliance).

---

## 8. Compliance, riesgos y pendientes

**Estado:** correcciones del review de compliance aplicadas (2026-11-03). Pendiente: revisión de `porty-compliance` sobre el copy nuevo de PR1 a PR5 y sobre todo copy rehecho (semana 5). No publicar nada antes.

Reglas aplicadas:
- Sin recomendaciones de compra, sin promesas de ganancia, sin urgencia (ni cuenta regresiva, ni "últimos días").
- Sin claims absolutos: nada de "cada número con su fuente", "sin inventar", "siempre", "nunca", "toda tu cartera", "rendimiento real". Se dice "las cifras salen de tu cartera y de datos de mercado", "Porty te explica tus números", "tu cartera en un solo lugar".
- CTA: "Descargala gratis" con la línea D. Nunca "Probala gratis", sin precios, sin "sin costo" a secas.
- Disclaimers A a E de la sección 3.2; en videos van en la imagen y en el caption.
- Sin testimonios inventados ni primera persona sobre una cuenta demo: voz impersonal o condicional. Humor actuado rotulado "Escena actuada".
- Sin tickers como consejo ni zoom a posiciones; PnL demo moderado; T5 fuera del feed.
- Logos de terceros: no se usan (íconos genéricos); la lista de brókers se muestra sin foco; nunca "Conectá tu Binance". Disponibilidad: "brókers compatibles" y "la disponibilidad depende del país y del bróker".
- Todo dato es de cuenta demo y se aclara. Nunca datos de usuarios reales.
- Las proyecciones de Metas y las simulaciones se presentan como estimaciones.
- Toda respuesta del chat grabada se lee entera antes de usarla; se descarta si hay lenguaje de recomendación. Hallazgo para `porty-assistant-dev` y product-owner: el prompt tiene una línea que permite sugerir cualquier ticker (`assistant_prompt_rules.dart:99`).
- IA generativa (Sunra): hoy sin créditos ni plan; si se activa, solo para planos de contexto, nunca para simular pantallas de la app, y se declara con la etiqueta de la red.
- Audio de tendencia: solo de la biblioteca comercial de cada red y si encaja con la marca.
- TikTok: revisar el ajuste de divulgación comercial ("tu marca") antes de publicar.
- Terceros que publiquen sobre Porty con algún beneficio: pasan por compliance y divulgan la relación con las herramientas de contenido de marca.
- Competencia: no nombrar ni comparar con IOL ni con otros brókers.

Requiere abogado (bloquea las piezas indicadas en la sección 0):
1. Diagnóstico e informe semanal: información vs asesoramiento regulado (CNV y mercado de cada país). Afecta P9 (condicional), P4 y P10.
2. Uso del nombre "S&P 500" y de datos del índice. Afecta P2, P11 y la comparación en P3.
3. Marcas de SnapTrade, Binance y eToro en marketing. Afecta P1 y las capturas de la lista de brókers.
4. Promoción de plataforma cripto en orgánico (y, si se paga, autorización previa de Meta y TikTok). Afecta P1.

Pendientes de validar con el equipo: que el Dashboard muestre el bróker de cada posición (P1), pantalla de confirmación real en el import (P5, PR4), qué benchmark se usa en "comparar" (P11), y si las muestras del informe y el Diagnóstico demo traen lenguaje de acción.
