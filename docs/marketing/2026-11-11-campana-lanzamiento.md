# Campaña de lanzamiento de Porty

Fecha: 2026-11-11 · Estado: propuesta para aprobar · Alcance: estrategia completa de lanzamiento (orgánico, comunidad, PR, creadores, ASO, email y pago).
Complementa, no reemplaza: `docs/marketing/social/2026-11-03-plan-lanzamiento-ig-tiktok.md` (piezas y calendario de redes), `docs/marketing/aso/ficha-google-play.md` (ficha), `docs/legal/reviews/2026-11-03-plan-redes.md` (reglas de copy).
Herramientas de ads, gestión y automatización: `docs/marketing/ads/2026-11-11-herramientas-y-automatizacion.md`.

> Nada de esto se publica, se manda ni se paga sin tu OK. Todo copy nuevo pasa por `porty-compliance` antes de salir. Los copies de este doc usan solo fórmulas que compliance ya aprobó o están marcados **[a revisar]**.

---

## 1. Resumen en 6 líneas

1. **El concepto:** *"Vos seguí con tu día. Porty está atento."* Porty es la app para el que invierte sin vivir pegado al mercado: junta su cartera en un solo lugar, la mira por él, **le avisa cuando algo se mueve** y se lo explica en palabras simples. El remate de cada pieza: *"Abrí. Entendé. Seguí con tu día."*
2. **No vendemos "IA".** El chat sobre la cartera ya lo regala IOL (MCP con ChatGPT/Claude). Vendemos lo que un chat genérico no da: **un asistente que está atento y te avisa**, varias cuentas en un solo lugar, cómo está compuesta tu cartera, el informe del sábado y un Porty que podés hacer tuyo (accesorios y memoria), con un tono calmo.
3. **Lanzamiento en dos tiempos:** *soft launch* con iOS + beta cerrada de Android (que de paso cumple la prueba de 14 días que exige Google), y **lanzamiento grande cuando Android esté público**, porque la mayoría del público objetivo en Argentina y Uruguay usa Android.
4. **Orgánico primero, pago después.** 2–4 semanas de orgánico, comunidad y PR para aprender qué mensaje funciona; la pauta es de **US$100 por mes**: se usa para empujar los videos que ya funcionaron gratis y para Apple Ads, no para comprar crecimiento (§8).
5. **La métrica que manda no son las descargas:** es **% de altas que llegan al diagnóstico en 48 h** (activación) y **% que paga en 14 días**. Una descarga que no carga su cartera no vale nada.
6. **Ventana de calendario a favor:** el aguinaldo (segunda quincena de diciembre) y "los propósitos de enero" son los dos momentos del año en que más gente piensa en su plata.

---

## 2. Punto de partida (lo que condiciona el plan)

| Hecho | Implicancia para la campaña | Fuente |
|---|---|---|
| La app **no está publicada**. El release 1 tiene 16 bloqueantes (firma, Firebase, legales, abogado, cuenta demo). | No hay fecha de lanzamiento fija: el plan se cuenta en semanas relativas a **L** (día en que ambas tiendas están públicas). Nada de pauta antes de L. | `docs/ops/2026-11-05-release-1-checklist.md` |
| Si la cuenta de Play es personal y nueva, Google pide **prueba cerrada con 12 testers por 14 días** antes de producción. | Convertir la obligación en marketing: **beta cerrada de 30–50 personas de la waitlist**. Da testers, feedback y las primeras reseñas reales. | checklist F3 |
| Ya existe **landing con waitlist y `ref_code`** y preventa por Mercado Pago. | La waitlist es el activo nº1 del pre-lanzamiento: email, beta y referidos de la lista. | `supabase/functions/landing`, `20261013000000_landing_waitlist.sql` |
| IOL conecta la cuenta a ChatGPT/Claude gratis desde el 27/08. | "Chat que ve tu cartera" no diferencia. Mensaje = **multi-cuenta + explicación + hábito semanal**. | `docs/business/research/2026-11-02-que-paga-el-inversor-retail.md` |
| Brókers con conexión directa: eToro, Binance y otros vía SnapTrade (Premium). Los brókers locales argentinos entran por **extracto o captura**. | El mensaje "conectá tu bróker" no aplica a la mayoría de los argentinos. El hero del onboarding para ellos es **"subí una captura o un extracto"**. Es el diferencial más demostrable en video. | `docs/marketing/aso/ficha-google-play.md` |
| Sin datos de conversión todavía (instrumentación nueva desde noviembre). | Los objetivos son de partida; se recalibran en L+2 con `porty-data-analyst`. | `docs/business/metrics/2026-11-02-embudo-a-pago.md` |
| Presupuesto mínimo (piso para publicar ≈ US$124 + abogado). | La campaña tiene que funcionar a costo casi cero en las fases 0–2. El pago es un test, no el motor. | `docs/ops/gastos.md` |

---

## 3. Objetivos

### Objetivo de negocio
Llegar a la **primera base de usuarios que pagan** y a un mensaje validado que se pueda escalar con pauta.

### Objetivos por fase (de partida, se ajustan en L+2)

| Fase | Objetivo | Métrica | Meta de partida |
|---|---|---|---|
| 0 · Pre-lanzamiento | Construir demanda | Inscriptos en la waitlist | 1.000 |
| 0 · Pre-lanzamiento | Validar producto con gente real | Testers activos de la beta (cargaron cartera) | 30 |
| 1 · Lanzamiento (L a L+7) | Convertir la lista | % de la waitlist que instala en la semana L | 25 % |
| 2 · Tracción (L+1 a L+6 sem.) | Instalaciones de calidad | Instalaciones totales (orgánico + US$100/mes de pauta) | 800–1.000 |
| 2 · Tracción | **Activación (métrica que manda)** | % de altas con `diagnosis_seen` en 48 h | ≥ 40 % |
| 2 · Tracción | Hábito | % de activados que abre el informe del sábado en W2 | ≥ 25 % |
| 2 · Tracción | Monetización | % de altas que pagan en 14 días | 2–3 % |
| 2 · Tracción | Confianza en tiendas | Rating promedio / reseñas | ≥ 4,5 / 50 reseñas |
| 3 · Escala | Pauta rentable | CAC por usuario que paga ≤ 1/3 del LTV a 12 meses | ver §8.3 |

Guardarraíles: reseñas que mencionen "me cobró", "no funciona con mi bróker" o "me recomendó comprar"; tasa de bajas de notificaciones; costo de IA por usuario Free.

---

## 4. Público objetivo

### Perfil principal (ICP)
**"El inversor de fin de semana."** 25–45 años, Argentina y Uruguay (después resto de LatAm hispana). Invierte su ahorro en CEDEARs, ETFs, acciones o algo de cripto. Tiene la plata en **dos o más lugares** (un bróker local, eToro o Binance, a veces un exchange). Mira la cartera en momentos puntuales: a la mañana, el fin de semana, después de una noticia. No es trader, no quiere serlo. Le molesta no saber si "le está yendo bien" de verdad.

**Su problema en sus palabras:** "Tengo la plata en tres apps y no sé cuánto gané en total." · "Bajó y no sé por qué." · "No entiendo qué estoy mirando." · "No quiero pasarme el día viendo gráficos."

### Segmentos y qué mensaje recibe cada uno

| Segmento | Quién es | Dolor principal | Mensaje | Prueba que mostrar | Canal principal |
|---|---|---|---|---|---|
| **S1 · Repartido** (prioridad 1) | Tiene cuentas en 2+ brókers/exchanges | No ve el total ni el resultado conjunto | "Tu cartera en un solo lugar, aunque esté en varias apps." | Video: captura del bróker → cartera cargada → diagnóstico | TikTok/Reels, comunidades de inversión, Apple Ads con keywords de brókers [a revisar: uso de marcas] |
| **S2 · Recién empezado** (prioridad 1) | Empezó a invertir en los últimos 2 años, aprende solo | Números crípticos, miedo a no entender | "Porty te explica tu cartera en palabras simples." | Pregunta al chat "¿cómo vengo este mes?" con respuesta en cuenta demo | TikTok, creadores educativos, SEO de la landing |
| **S3 · Ocupado** (prioridad 2) | Invierte hace años, poco tiempo | Mirar todo le lleva tiempo | "Una vez por semana, el informe de tu cartera." | Informe del sábado + widget | Instagram, X, newsletters |
| **S4 · Inglés / global** (prioridad 3) | Inversor retail de habla inglesa con eToro/IBKR | Mismo que S1 | "Your portfolio in one place, explained in plain words." | Igual que S1 | Product Hunt, Reddit, ASO en inglés |

**Fuera de público (no gastar ahí):** traders activos, day traders, gente que busca señales o "qué comprar". Atraerlos trae reseñas malas y riesgo regulatorio.

---

## 5. Posicionamiento y mensajes

### Declaración de posicionamiento (interna)
Para el inversor casual que tiene su plata repartida y no quiere vivir mirando el mercado, **Porty es el asistente que junta su cartera en un solo lugar y se la explica en palabras simples**. A diferencia de los trackers llenos de gráficos y de los chats genéricos conectados a un solo bróker, Porty junta varias cuentas, te muestra lo que no se ve a simple vista y te deja el informe de tu semana, con un tono calmo, sin jerga y sin empujarte a operar.

### Mensaje madre
**"Tu cartera, en un solo lugar y en palabras simples."**

### Concepto creativo de la campaña
**"Vos seguí con tu día. Porty está atento."** [a revisar], con el remate **"Abrí. Entendé. Seguí con tu día."** [a revisar]
Es la antítesis del casino financiero: Porty no te quiere 3 horas en la app. Mira tu cartera por vos, te avisa si pasa algo y te lo explica en 30 segundos. Funciona como línea de los ads, de la landing y como marco para el humor calmo ("abrir la app 14 veces por día" vs "que Porty te avise").

### Mensaje principal de los ads: "Porty está atento y te avisa"

Lo que Porty hace de verdad (verificado en el código, `lib/features/notifications/`, `daily-jobs`, `plan_matrix.dart`):

| Qué hace | Plan | Cómo decirlo en un ad [a revisar] |
|---|---|---|
| Avisa cuando tu cartera o algo que tenés se mueve fuerte (sensibilidad baja/normal/alta, horario silencioso) | Todos | "Si tu cartera se mueve fuerte, Porty te avisa." |
| Alertas de precio | 1 en Free, 20 Premium, 50 Gold | "Elegí un precio y Porty te avisa cuando llega." |
| Resumen de la mañana con lo tuyo | Todos (con 2+ acciones) | "A la mañana, lo que pasó con lo tuyo, en dos líneas." |
| Por qué se movió lo tuyo, con links a las notas | Premium | "Y te cuenta por qué se movió." + línea D |
| Resultados trimestrales de tus empresas | Gold | "Te avisa cuando tus empresas presentan resultados." + línea D |
| Informe del sábado | Completo en Gold | "Los sábados, el resumen de tu semana." + línea D |
| Cómo está compuesta tu cartera (diagnóstico: concentración, solapamientos, sectores) | Free | "Mirá de un vistazo cómo está repartida tu plata." / "Te marca si una posición pesa demasiado." |
| Si le preguntás, ideas para diversificar con simulación educativa | Premium | Ver cuidado legal abajo |

Fórmulas para ads (todas pasan por compliance):
- "No hace falta mirar el mercado todo el día. Porty está atento."
- "Tu cartera se movió. Porty ya te avisó, y te explica qué pasó."
- "¿Cómo viene tu cartera? Preguntale a Porty."
- "Preguntale cómo diversificar y te muestra opciones para que investigues vos." [a revisar, ver abajo]

**Palabras prohibidas en ads:** "recomendaciones", "te recomienda", "te dice qué comprar", "oportunidades", "invertí en", "te dice si estás bien" (en su lugar: "te cuenta cómo viene tu cartera"), "sugerencias de inversión" (en su lugar: "ideas para explorar" o "opciones para que investigues").

**Cuidado legal con la diversificación.** Es la función con más riesgo: cuando le preguntás, Porty muestra tickers concretos con un porcentaje de reparto. Una tarjeta con "comprá X e Y" en un anuncio se lee como asesoramiento, y en `plan_matrix.dart` el equipo ya había decidido no destacarla en el marketing. Propuesta: el ad muestra solo **la pregunta** ("¿Cómo podría diversificar?") y la parte de **composición** (cómo está repartida tu plata), **nunca la tarjeta con los candidatos**. Incluir la frase de diversificación queda sujeto a lo que diga el abogado (bloqueante B15 del release).

**Dependencia técnica:** los avisos necesitan el push funcionando (Firebase y APNs, bloqueante B4 del release). Si el día L el push no anda, **los ads no pueden decir "te avisa"**: se usa el mensaje de composición y explicación hasta que funcione.

### Segundo mensaje: "Hacelo tuyo" (personalizar a Porty)

| Qué | Detalle | Plan |
|---|---|---|
| Vestí a Porty | 12 accesorios, uno por lugar (cabeza, cara, cuello): gorro, galera, sombrero de cowboy, gorra, corona, moño, flor, gorrito de fiesta, anteojos, anteojos de sol, moño de cuello | Todos |
| Porty te recuerda | Anota lo que le contás (tus metas, cuánto ahorrás) y responde con eso; lo ves y lo borrás en Ajustes | Todos |
| Avisos a tu medida | Qué te avisa, con qué sensibilidad y en qué horario | Todos |

Por qué sirve: casi no tiene riesgo legal, es divertido, es compartible y separa a Porty de la fintech fría. Ideas: TikTok "¿Qué le ponemos a Porty?" (encuesta en stories y que gane un accesorio), Porty con gorrito de fiesta para Año Nuevo, "tu Porty y el mío" como formato de creadores. Límite de marca (`PRODUCT.md`: sin gamificación): es un guiño de personalidad, no el centro de la campaña. Proporción sugerida en ads: 60 % "está atento", 25 % "todo junto y explicado", 15 % "hacelo tuyo".
Ojo en la memoria: decirlo siempre como "lo que vos le contás, y lo podés borrar cuando quieras" (privacidad, Ley 25.326).

Variantes de tagline para testear en orgánico antes de pagar por ellas:
- "Tu cartera, explicada." [a revisar]
- "Invertí sin mirar el mercado todo el día." [a revisar: puede leerse como invitación a invertir; alternativa "Seguí tu cartera sin mirar el mercado todo el día"]
- "Tu cartera en un solo lugar, aunque esté en varias apps." (ya aprobado en esencia)

### Pilares de valor (lo que se puede afirmar, con su prueba)

| Pilar | Cómo decirlo (fórmula aprobada) | Prueba en pantalla | Plan |
|---|---|---|---|
| Todo junto | "Tu cartera en un solo lugar: brókers compatibles, un extracto o una captura." | Import por captura | Free (primera importación); conexión automática Premium |
| Entendé | "Porty te explica tus números." / "Las cifras salen de tu cartera y de datos de mercado." | Chat respondiendo sobre la cartera demo | Free (20 consultas/mes) |
| Lo que no se ve | "Te marca lo que no se ve a simple vista." | Diagnóstico: concentración, solapamiento de ETFs | Free |
| Hábito tranquilo | "Los sábados te deja el informe de tu semana." | Informe semanal | Completo en Gold (cortesía al inicio) |
| Tus metas | "Creá metas de ahorro y mirá cuánto te falta." | Pantalla de metas, "Estimación, no garantía." | Premium |
| Confianza | "Solo lectura: Porty nunca opera, ni custodia, ni mueve tu plata." | Pantalla de conexión | Todos |

### Lo que nunca se dice
"Recomendaciones" o "te recomienda", "gratis" a secas o "probala gratis" (siempre "Descargala gratis. Algunas funciones son de planes pagos."), "ganá más", "invertí mejor", "sin inventar", "cada número con su fuente", "siempre", "nunca se equivoca", "tus brókers" sin "compatibles", testimonios inventados, tickers destacados, rendimientos altos aunque sean demo, "conectá tu Binance". Disclaimers A–E de `docs/legal/reviews/2026-11-03-plan-redes.md` §2, en la imagen y en el caption.

---

## 6. Plan por fases

### Fase 0 · Pre-lanzamiento (desde hoy hasta L) — "Armar la lista"

Objetivo: 1.000 inscriptos, 30 testers activos, primeras piezas con datos de qué engancha.

1. **Landing como centro de todo** (`portyassistant.com`). Hero con el mensaje madre, video de 20 s (PR1 ya está renderizado), formulario de waitlist, links con UTM por canal (`?utm_source=tiktok&utm_campaign=prelaunch`). Bloque "¿Qué brókers puedo usar?" con la verdad: compatibles + captura/extracto para el resto (baja reseñas malas el día L).
2. **Waitlist con posición y referidos.** La tabla ya tiene `ref_code`: "Invitá a 3 amigos y entrás a la beta antes". Premio = acceso anticipado (no plata ni plan pago, para no entrar en promociones reguladas) [a revisar].
3. **Beta cerrada "Primeros 50"**. Se invita por mail a la waitlist; el form pide qué brókers usa (dato de oro para el mensaje y para producto). Cumple los 12 testers × 14 días de Play. A cambio: acceso anticipado y un canal directo con el fundador (grupo de WhatsApp o Telegram). Al cierre: pedido de reseña en tienda el día L y permiso explícito para citar comentarios reales.
4. **Build in public (X + LinkedIn del fundador).** 2–3 posts por semana: qué se está construyendo, decisiones ("por qué Porty no te dice qué comprar"), números de la beta. La voz del fundador convierte mejor que la marca en esta etapa.
5. **Orgánico IG/TikTok:** semanas 1–3 del plan existente (PR1–PR5, P4–P8 que están listas para producir). Arrancar ya: el algoritmo tarda en entender la cuenta.
6. **Siembra con creadores (sin pago todavía).** Lista de 30 microcreadores de finanzas personales (5k–100k seguidores, AR/UY, tono educativo, no "gurús" de trading). Se les ofrece acceso a la beta y una charla con el fundador. Si publican, tienen que marcarlo como colaboración [a revisar con compliance antes del primer contacto].
7. **Prensa preparada.** Kit de prensa (logo, capturas, 3 párrafos, foto y bio del fundador, datos de contacto) y una lista de 15 periodistas de tecnología/finanzas. Ángulo de nota: "Un desarrollador uruguayo/rioplatense lanza una app que te explica tu cartera sin empujarte a operar" + contexto de cuántos argentinos empezaron a invertir en CEDEARs [dato a citar con fuente].

### Fase 1 · Lanzamiento (semana L) — "El día que todos se enteran"

Sugerencia de timing: si L cae entre el 1 y el 20 de diciembre, **anclar el lanzamiento al aguinaldo** ("¿Ya sabés cómo viene tu cartera?"). Si cae después del 20/12, **esperar a la primera semana de enero** (propósitos del año, metas de ahorro). Lanzar entre el 24/12 y el 2/1 es tirar el esfuerzo.

| Día | Acción | Dueño |
|---|---|---|
| L-7 | Mail a la waitlist: "Falta una semana". Brief a creadores con la fecha. Notas de versión y ficha final en las dos tiendas | marketing-lead, aso-specialist |
| L-2 | Embargo a periodistas con kit de prensa | fundador |
| **L** | Mail a toda la waitlist con link directo a tienda · Video manifiesto en TikTok, Reels, X, LinkedIn · Post del fundador contando la historia · Pedido de reseña a los beta testers · Stories con link todo el día | fundador + social-media |
| L | Product Hunt en inglés (S4), si la versión en inglés está pulida | fundador |
| L+1 | Posts en comunidades (ver §7) con valor, no con link a secas | fundador |
| L+2 a L+7 | Responder **todas** las reseñas y comentarios en < 24 h · Recap con números reales de la semana | support, social-media |

### Fase 2 · Tracción (L+1 a L+6 semanas) — "Aprender qué mensaje vende"

- Orgánico: semanas 4–5 del plan de redes + nuevas piezas según lo que haya funcionado (rehacer las 3 piezas con más guardados/retención a 3 s).
- Contenido de búsqueda en la landing (SEO, 1 nota por semana): "cómo ver todas mis inversiones juntas", "cómo calcular cuánto gané con mis CEDEARs", "qué es el PnL", "cómo leer el resumen de mi bróker". Son preguntas que el S2 googlea y que Porty resuelve.
- Email de activación (a quien se registró y no cargó cartera): día 1 "Subí una captura y listo", día 3 "Lo que Porty encontró en carteras como la tuya" (diagnóstico demo), día 7 "Tu primer informe del sábado".
- **Pauta de US$100/mes desde L** (ver §8): Apple Ads desde el día L y promoción de los videos orgánicos que mejor retuvieron. Si la activación queda por debajo de 30 %, se pausa la promoción: pagar por instalaciones es pagar por usuarios que se van, primero se arregla el onboarding.
- Lectura semanal de embudo con `porty-data-analyst` (viernes).

### Fase 3 · Escala (L+6 semanas en adelante) — "Poner plata donde ya funciona"

Solo si en fase 2 hay: un mensaje ganador (CTR y activación mejores que el promedio), CAC dentro del objetivo en al menos un canal y retención W4 razonable. Ahí: reinvertir lo que entra por suscripciones en el canal ganador, sumar creadores pagos con contenido de marca, referidos dentro de la app (diseñado por growth, revisado por compliance) y "Tu año en Porty" como pieza compartible de fin de año [idea a evaluar con product-owner].

---

## 7. Canales: rol, costo y prioridad

| Canal | Rol | Costo | Prioridad | KPI |
|---|---|---|---|---|
| Waitlist + email | Convertir demanda acumulada el día L | ~0 (Brevo gratis) | **Alta** | % de la lista que instala |
| TikTok + Reels | Alcance y demostración (S1, S2) | Tiempo | **Alta** | Retención a 3 s, guardados, clics al link |
| Fundador en X/LinkedIn | Confianza, prensa, primeros usuarios, inversores | Tiempo | **Alta** | Clics, menciones |
| ASO (las dos tiendas) | Convertir a quien busca "cartera", "portfolio", "inversiones" | ~0 | **Alta** | Conversión de la ficha |
| Comunidades | Usuarios tempranos muy calificados | Tiempo | Media | Instalaciones con UTM |
| Creadores (microinfluencers) | Credibilidad prestada con S2 | 0 en fase 0, pago en fase 3 | Media | Instalaciones por código |
| PR | Credibilidad y pico de lanzamiento | ~0 | Media | Notas publicadas |
| SEO (landing) | Demanda constante a largo plazo | Tiempo | Media (rinde en meses) | Visitas orgánicas |
| Pauta paga | Amplificar lo que ya funcionó gratis | US$100/mes | Media desde L | Costo por instalación y por activado |
| Product Hunt | Pico en inglés (S4) | ~0 | Baja | Upvotes, instalaciones en |

**Comunidades — regla de oro:** aportar antes de mostrar. Responder dudas de "cómo sé cuánto gané" con una explicación útil y mencionar Porty solo si viene al caso y lo permiten las reglas del grupo. Candidatas: subreddits de inversión de Argentina/LatAm, grupos de Telegram/Discord de inversores en CEDEARs, comunidades de eToro (CopyTrader no, el público es otro). Nunca spam, nunca cuentas falsas.

---

## 8. Pauta paga con US$100 por mes

### 8.1 ¿Alcanza US$100? Sí, para aprender; no para crecer
Con US$100 por mes no se "compra" el crecimiento, pero sí se puede:
- **Saber qué mensaje funciona** antes de gastar más ("está atento" vs "todo junto" vs "hacelo tuyo").
- **Amplificar lo que ya funcionó gratis**: un video orgánico que retiene bien, empujado con US$20–30, llega a decenas de miles de personas en Argentina y Uruguay, donde la publicidad es barata comparada con EE. UU.
- **Cubrir la búsqueda en el App Store** para que nadie más aparezca cuando buscan "Porty" o "cartera de inversiones".

Expectativa honesta: entre 100 y 300 instalaciones por mes por pauta (supuesto; depende mucho de la pieza). El motor sigue siendo el orgánico, la waitlist y la comunidad.

**Lo que no conviene con este presupuesto:**
- Repartir en 4 plataformas: ninguna junta datos suficientes para aprender.
- Google App Campaigns: con US$2–3 por día el algoritmo no sale del aprendizaje. Entra cuando haya US$150+ por mes solo para Google.
- Pagar herramientas de automatización o gestión: todo lo necesario tiene plan gratis (ver el doc de herramientas). Vos subís los videos y la plata va entera a ads y a generar piezas.

### 8.2 Cómo repartir los US$100

| Partida | Mes 1 (semana L) | Meses siguientes | Para qué |
|---|---|---|---|
| **Promocionar en Instagram/Facebook** los 2–3 Reels orgánicos con mejor retención | US$40 | US$40–50 | Alcance barato con un video que ya probó que engancha. Objetivo: clics a la tienda o la landing. Argentina + Uruguay, 22–45 años |
| **TikTok Promote / Spark Ads** del mejor TikTok | US$20 | US$20–30 | Mismo criterio; solo si en orgánico TikTok rinde más que Instagram, si no esa plata va a Meta |
| **Apple Ads** (keywords de marca y categoría) | US$25 | US$20 | Captar a quien ya está buscando una app así en el iPhone |
| **Generar piezas con IA** (planos de video) | US$15 | US$0–15 | Solo el mes que haga falta un lote de planos nuevos (ver doc de herramientas) |
| **Total** | **US$100** | **US$100** | |

Reglas:
- **Nada de pauta antes de L.** Sin app en la tienda, cada clic se pierde.
- **No se promociona una pieza que no funcionó gratis.** Primero 7 días orgánica: si retiene (35 % a 3 s, guardados arriba del promedio), recién ahí se le pone plata.
- **Corte rápido:** si un anuncio gastó US$10 y no trajo ninguna instalación, se apaga.
- Cada promoción usa el mismo copy aprobado por compliance que la pieza orgánica, con los disclaimers en la imagen.
- Antes del primer peso en Meta: verificar si piden verificación de anunciante de servicios financieros para Argentina y Uruguay.

### 8.3 ¿Cuándo subir el presupuesto?
Cuando un canal cumpla dos semanas seguidas con:
- costo por instalación ≤ US$0,50, y
- ≥ 30 % de esas instalaciones llegan al diagnóstico.

Ahí se mueve la plata a ese canal y se suma lo que vaya entrando por suscripciones (reinvertir los primeros ingresos es la forma de crecer sin poner plata propia). Cuenta de referencia (supuestos, sin datos todavía): Premium US$10/mes, neto ~US$8,5 después de la tienda, 4–6 meses de vida por pagador → **LTV ≈ US$34–51 por pagador**; con 2–3 % de instalaciones que pagan, **cada instalación vale ≈ US$0,7–1,5**. Por eso el tope de US$0,50 por instalación. `porty-data-analyst` lo recalcula con datos reales en L+4.

## 9. Medición y atribución

| Qué | Cómo | Estado |
|---|---|---|
| Visitas y fuente en la landing | UTM por canal + analítica de Cloudflare | Por armar |
| Waitlist por canal | `utm_source` y `ref_code` guardados en la tabla de la waitlist | Verificar que se guarda el UTM |
| Instalación por canal | Apple Ads Attribution (AdServices), Google Play Install Referrer, códigos/links por creador | Por armar |
| Activación y pago | `product_events` (`portfolio_loaded`, `diagnosis_seen`, `paywall_viewed`, `purchase_result`) + `subscription_events` | Ya existe (noviembre) |
| Pago por canal en las plataformas de ads | RevenueCat → integraciones con Meta, TikTok, Firebase/Google y Apple Ads | Por configurar |
| Tablero semanal | Una sola vista: canal → visitas → waitlist → instalación → activado → pagador → costo | data-analyst |

Rutina: tablero los viernes, decisión de la semana siguiente los lunes (qué pieza se repite, qué se apaga, a dónde va la plata).

---

## 10. Riesgos y compliance

| Riesgo | Mitigación |
|---|---|
| Que se lea como asesoramiento financiero (CNV) | Nunca "qué comprar", ni tickers destacados; disclaimers A–E; revisión del abogado (B15) antes de L |
| Reglas de ads de servicios financieros (Meta, Google, TikTok) | Antes de pautar: leer la política vigente para Argentina/Uruguay; Meta estaría exigiendo verificación de identidad a anunciantes de servicios financieros (verificar en Meta Business Help). Declaración de funciones financieras en Play Console |
| Restricciones a promover plataformas cripto | No nombrar Binance en anuncios pagos; en orgánico solo como "compatible", sin foco |
| Uso de marcas de terceros (brókers, S&P 500) | Pendiente del abogado; usar "brókers compatibles" e íconos genéricos mientras tanto |
| Prometer brókers que no conectan en tu país | "La disponibilidad depende del país y del bróker" + sección honesta en la landing |
| Pico de usuarios con bugs el día L | Beta cerrada primero; QA de humo; soporte con respuestas preparadas (porty-support) |
| Costo de IA si el lanzamiento explota | Cuotas por plan ya existen; vigilar `ai_turn_usage` diario la semana L |
| Creadores que exageran | Brief por escrito con lo que se puede y no se puede decir; revisión antes de publicar; divulgación de la colaboración |

---

## 11. Quién hace qué

| Tarea | Agente | Aprobás vos |
|---|---|---|
| Copy de landing, mails, kit de prensa | `porty-marketing-lead` | Sí |
| Piezas de redes y calendario | `porty-social-media` (plan existente) | Sí, cada publicación |
| Ficha, keywords, capturas | `porty-aso-specialist` | Sí |
| Estructura de campañas pagas y creatividades | `porty-ads-specialist` | Sí, cada peso |
| Referidos de waitlist, onboarding, mails de activación | `porty-growth-lead` | Sí |
| Revisión de todo lo público | `porty-compliance` | — |
| Tablero y CAC/LTV | `porty-data-analyst` | — |
| Respuestas a reseñas y FAQ | `porty-support` | Sí, las primeras semanas |
| Contacto con creadores y prensa, posts del fundador | **Vos** | — |

---

## 12. Próximos 10 pasos (en orden)

1. Aprobar o ajustar el concepto "Vos seguí con tu día. Porty está atento." y el mensaje madre → pasa a compliance, junto con la frase de diversificación (que además necesita al abogado).
2. Verificar que la waitlist guarda `utm_source` y armar los links con UTM por canal.
3. Abrir la cuenta de TikTok/IG y publicar PR1–PR3 (ya renderizados en `docs/marketing/social/piezas/2026-11-03/`).
4. Mail a la waitlist invitando a la beta "Primeros 50" (marketing-lead redacta, compliance revisa).
5. Empezar los posts de build in public del fundador (2–3 por semana).
6. Armar la lista de 30 microcreadores y 15 periodistas.
7. Kit de prensa en la landing (`/prensa`).
8. Cerrar los bloqueantes del release 1 (sin app publicada no hay lanzamiento).
9. Configurar las integraciones de RevenueCat con Apple Ads y Firebase/Google antes de L, y confirmar que el push funciona (sin push, los ads no dicen "te avisa").
10. Decidir la fecha de L con la regla del §6 (aguinaldo o primera semana de enero).
