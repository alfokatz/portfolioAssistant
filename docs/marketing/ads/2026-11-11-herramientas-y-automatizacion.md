# Herramientas de ads, gestión y automatización de la campaña

Fecha: 2026-11-11 · Estado: recomendación · Acompaña a `docs/marketing/2026-11-11-campana-lanzamiento.md`.

> Precios y condiciones de terceros cambian seguido: todo lo marcado **(verificar)** hay que confirmarlo en el sitio oficial antes de contratar. No se contrata ni se gasta nada sin tu OK.

---

## 1. Respuesta corta

- **Presupuesto real: US$100 por mes.** Con eso: Meta (promocionar los Reels que ya funcionaron) + Apple Ads + algo de TikTok, y un lote de planos con IA solo el mes que haga falta. Google App Campaigns queda para cuando haya US$150+ por mes solo para Google. X, LinkedIn y Reddit no valen la pena para Porty en esta etapa.
- **US$0 en herramientas de gestión y automatización.** Todo lo necesario tiene plan gratis: paneles nativos con reglas, Metricool, Brevo, RevenueCat, Firebase. Vos subís los videos; la plata va entera a ads y a generar piezas.
- **Video con IA: Sunra o Higgsfield, un mes cuando haga falta, no una suscripción fija** (§6). Las piezas que más venden de una app como Porty son pantallas reales + Porty animado, y eso ya lo hacen gratis los scripts de `tools/marketing/`.
- **Para medir:** RevenueCat (ya lo usan) mandando las compras a cada plataforma, más un MMP (AppsFlyer, Adjust, Branch, Tenjin) **recién cuando se pauta en Meta o TikTok**.
- **Para redes orgánicas:** Metricool (en español, tiene plan gratis) o los programadores nativos de Meta y TikTok.
- **¿Se puede automatizar todo el flujo?** Técnicamente casi todo, sí. **Recomiendo automatizar ~80 %** (producción de borradores, revisión previa, programación, reportes, alertas y reglas de presupuesto) y **dejar 3 puertas humanas**: aprobar lo que se publica, aprobar la plata y aprobar cambios de mensaje. En una fintech, un anuncio mal dicho que sale solo puede costar la cuenta publicitaria o un problema regulatorio.

---

## 2. Plataformas de ads: cuál conviene

| Plataforma | Por qué sí | Por qué no / cuidado | Cuándo | Optimizar hacia |
|---|---|---|---|---|
| **Apple Ads** (App Store) · US$20–25/mes | Gente que ya está buscando una app de inversiones: máxima intención. Disponible en Argentina y Uruguay. Protege la búsqueda "Porty". Atribución nativa sin SDK extra (AdServices) | Solo iOS, que en Argentina/Uruguay es minoría. Volumen chico | Desde L | Instalaciones → luego CPA de `portfolio_loaded` |
| **Google App Campaigns** (Play, YouTube, Search, Display) · después, con US$150+/mes | Android es la mayoría del público objetivo. Totalmente automatizada (le das textos, imágenes y videos y ella combina). Se integra con Firebase, que ya usan para push | Poco control fino; necesita eventos in-app bien configurados para no traer instalaciones basura. **Campañas de preinscripción** en Play si hacés pre-registro antes de L | Preinscripción antes de L (opcional); instalaciones desde L+2 | Evento `portfolio_loaded`, después compra |
| **Meta: promocionar Reels** y después Advantage+ app (Instagram, Facebook) · US$40–50/mes | El mejor lugar para video corto con segmentación por intereses; reutiliza las piezas orgánicas que funcionaron | Servicios financieros es categoría restringida; estaría pidiendo verificación de identidad del anunciante (verificar). Sin SDK o MMP la optimización es mala. iOS limitado por ATT | Desde L, como "promocionar publicación" con objetivo de clics a la tienda (no necesita SDK). Advantage+ app recién con más presupuesto | Clics a la tienda; después evento in-app vía SDK/MMP |
| **TikTok Promote / Spark Ads**, después App campaigns · US$20–30/mes | Público joven (S2), CPM bajo, el contenido nativo funciona | Calidad de usuario más variable; restricciones en finanzas y cripto (verificar); necesita SDK o MMP | Desde L con Promote/Spark Ads sobre el mejor TikTok orgánico, solo si TikTok rinde más que Instagram | Clics; después evento in-app |
| X, LinkedIn, Reddit Ads | — | CPI alto o sin buena campaña de apps para LatAm | No por ahora | — |

**Bonus sin costo antes de L:**
- **Pre-pedido en App Store** (las apps se pueden publicar en pre-order) y **pre-registro en Google Play**: la ficha existe antes de L, se juntan interesados y el día L la tienda les avisa sola (verificar requisitos de la cuenta, en Play puede chocar con la prueba cerrada).

---

## 3. Herramientas para gestionar

### 3.1 Gestión de campañas pagas

| Herramienta | Qué hace | Costo | Para Porty |
|---|---|---|---|
| **Paneles nativos** (Apple Ads, Google Ads, Meta Ads Manager, TikTok Ads Manager) | Todo, más reglas automáticas: Meta tiene reglas (pausar si CPA > X), Google Ads tiene reglas y scripts | Gratis | **Usar esto en fases 1–2** |
| SearchAds.com / SplitMetrics Acquire / MobileAction | Automatización de Apple Ads: reglas de pujas, búsqueda de keywords, informes | Planes desde decenas a cientos de US$/mes (verificar); algunos tienen gratis | Cuando Apple Ads > ~US$500/mes |
| Bïrch (ex Revealbot) | Reglas y automatización cruzada Meta/Google/TikTok, informes a Slack | De pago (verificar) | Fase 3 |
| Madgicx | Automatización y creatividades con IA, solo Meta | De pago (verificar) | Solo si Meta es el canal ganador |
| Smartly.io | Plataforma enterprise de creatividad y compra | Cara, para grandes anunciantes | No |

### 3.2 Medición y atribución

| Herramienta | Qué hace | Costo | Para Porty |
|---|---|---|---|
| **RevenueCat** (ya integrado) | Manda compras, renovaciones y bajas a Meta, TikTok, Firebase/Google, Apple Ads, AppsFlyer, Adjust, Branch; guarda la atribución de Apple Ads por usuario | Incluido (integraciones según plan, verificar) | **Configurar antes de L** |
| **Firebase / GA4** | Eventos in-app y vínculo con Google Ads para optimizar App Campaigns | Gratis | **Sí, ya tienen Firebase para push** |
| `product_events` en Supabase | La verdad del embudo propio (activación, paywall, compra) | Ya existe | Base del tablero |
| MMP: AppsFlyer (plan Zero gratis con límites), Tenjin (pensado para apps chicas), Branch, Adjust | Atribución unificada entre Meta, TikTok, Google y Apple; SKAdNetwork; deep links por creador | Desde gratis con límites a pago por volumen (verificar) | **Cuando se pauta en Meta/TikTok.** Recomiendo AppsFlyer Zero o Tenjin para empezar |

Ojo: sumar un SDK de atribución o el SDK de Meta **es un cambio en la app** (porty-flutter-dev), cambia la política de privacidad y las declaraciones de datos de las tiendas, y en iOS puede requerir el pedido de ATT. Pasa por `porty-compliance` y `porty-security-reviewer`. Por eso conviene empezar con Apple Ads + Google (que no lo necesitan) y sumarlo solo si se va a Meta/TikTok.

### 3.3 Redes orgánicas, creatividades y email

| Necesidad | Recomendado | Alternativas | Costo |
|---|---|---|---|
| Programar IG, TikTok, X, LinkedIn y ver métricas | **Metricool** | Buffer, Later; Meta Business Suite + programador de TikTok (nativos) | Metricool y Buffer tienen plan gratis (verificar límites) |
| Diseño de placas y carruseles | **Canva** (conectado a esta sesión) + plantillas de marca | Figma (también conectado) | Gratis / Pro |
| Video | Scripts propios en `tools/marketing/` (ya renderizan PR1 y los cortes), CapCut para edición | Sunra (conectado, video con IA) para planos generados | Bajo |
| Email a la waitlist y de activación | **Brevo** (ya previsto en `gastos.md`) | Loops, Resend | Gratis hasta cierto volumen |
| Links por canal y por creador | UTM en la landing + links del MMP cuando exista | Bitly / Dub | Gratis |
| Tablero | Looker Studio con conectores, o una vista en Supabase | Windsor.ai / Supermetrics para traer datos de ads | Gratis / bajo |

---

## 4. ¿Se puede automatizar todo el flujo?

### 4.1 El flujo de la campaña, paso por paso

| # | Paso | ¿Automatizable? | Cómo | Puerta humana |
|---|---|---|---|---|
| 1 | Brief semanal (qué mensaje, para qué segmento) | Sí | Tarea programada de Claude que lee el tablero y propone el brief | **Sí: aprobás el mensaje** |
| 2 | Copies y guiones | Sí | Agentes `porty-social-media` / `porty-ads-specialist` | No |
| 3 | Revisión de compliance | Sí, la primera pasada | Agente `porty-compliance` con las reglas de `docs/legal/` | Lo nuevo o dudoso → abogado |
| 4 | Creatividades (placas, videos, variantes) | Sí | Scripts de `tools/marketing/`, Canva y Sunra por MCP, capturas de `test/screenshots` | No |
| 5 | Aprobación | **No** | — | **Sí: cada pieza pública** |
| 6 | Programar orgánico | Sí | Metricool (o API de Meta/TikTok) | — (ya aprobado en 5) |
| 7 | Subir creatividades y campañas pagas | Sí | APIs: Apple Ads Campaign Management API, Google Ads API, Meta Marketing API, TikTok Marketing API | **Sí: aprobás presupuesto** |
| 8 | Optimizar pujas y audiencias | Sí, y ya lo hacen las plataformas | Advantage+, App Campaigns y Apple Ads Basic optimizan solas | No |
| 9 | Reglas de seguridad (pausar lo que no rinde) | Sí | Reglas nativas: pausar anuncio con CPA > 2× objetivo tras N gasto; tope diario | Configurás los umbrales una vez |
| 10 | Escalar presupuesto | Parcial | Regla que **propone** +20 % si el CPA está bajo objetivo 3 días seguidos | **Sí: subir plata siempre con OK** |
| 11 | Reporte diario/semanal | Sí | Tarea programada: trae datos de las APIs + Supabase, arma el resumen y lo manda (Slack o mail) | No |
| 12 | Responder comentarios y reseñas | Parcial | Borradores de `porty-support` | Sí al principio |
| 13 | Aprendizaje y nuevo brief | Sí | `porty-data-analyst` lee la semana → vuelve al paso 1 | — |

### 4.2 Cómo se vería (cuando esté todo armado)

```
Lunes 9:00   Tarea programada → lee tablero de la semana → propone brief + 6 piezas
             └─ agentes redactan → compliance revisa → render de creatividades
Lunes 12:00  Te llega UN mensaje: "6 piezas listas, 1 cambio de presupuesto propuesto" → aprobás/rechazás
Mar–Dom      Metricool publica lo aprobado · plataformas optimizan solas · reglas pausan lo que no rinde
Diario 8:00  Resumen corto: gasto, instalaciones, activados, CPA por canal, alertas
Viernes      Informe semanal con aprendizajes → alimenta el brief del lunes
```

Tu tiempo semanal: ~1 hora (aprobar el lunes + leer el viernes), más lo que no se delega (prensa, creadores, posts personales).

### 4.3 Qué hace falta para llegar ahí (y en qué orden)

| Nivel | Cuándo | Qué | Esfuerzo |
|---|---|---|---|
| **1 · Manual con ayuda** | Ahora → L+2 | Agentes generan y revisan; vos publicás con Metricool; paneles nativos con reglas; tablero semanal a mano con data-analyst | Bajo. Sin integraciones nuevas |
| **2 · Semiautomático** | L+2 → L+6 | RevenueCat conectado a Apple Ads y Google; eventos de Firebase; reglas automáticas; tarea programada semanal que arma el informe desde Supabase y te lo manda por Slack | Medio. Un par de días de configuración |
| **3 · Automatizado con APIs** | Cuando la pauta pase ~US$1.500/mes y haya un mensaje ganador | Acceso a las APIs de ads; job diario que trae costos a una tabla de Supabase; propuestas automáticas de cambios de presupuesto que aprobás con un toque | Alto. Requiere aprobaciones de acceso de cada plataforma |

Requisitos de las APIs (por eso el nivel 3 no es para ya):
- **Google Ads API:** pedir un *developer token* y que Google lo apruebe (verificar plazos).
- **Meta Marketing API:** app de desarrollador + negocio verificado en Business Manager.
- **TikTok Marketing API:** solicitud de acceso como desarrollador.
- **Apple Ads Campaign Management API:** credenciales de API desde la cuenta de Apple Ads (la más simple de las cuatro).

### 4.4 Lo que no conviene automatizar

- **Publicar sin aprobación.** Es fintech: un claim de rentabilidad o un "qué comprar" que sale solo puede tumbar la cuenta de ads o traer un problema con la CNV.
- **Subir presupuesto sin tope.** Las reglas pueden pausar solas; para gastar más, siempre una persona.
- **Contacto con creadores y prensa.** Son relaciones; un mail automático quema contactos.
- **Respuestas a reseñas negativas en las primeras semanas.** Son la mejor fuente de producto y un mal tono se ve público.

---

## 5. Recomendación concreta para arrancar (US$100/mes)

1. **Ahora (US$0):** cuenta de Metricool + Brevo; UTM en la landing; Canva con el kit de marca (colores y tipografía de `DESIGN.md`).
2. **Antes de L (US$0):** crear la cuenta de Apple Ads; activar en RevenueCat la integración de Apple Ads; definir `portfolio_loaded` como evento de conversión en Firebase.
3. **Semana L:** Apple Ads con keywords de marca y categoría (~US$0,80/día) + promoción del mejor Reel de la semana 1 (US$20).
4. **L+1 en adelante:** cada semana, promocionar con US$10–15 el video orgánico que mejor retuvo esa semana, en Meta o TikTok según dónde rinda más.
5. **Cuando haga falta un lote de planos nuevos:** un mes de Sunra o Higgsfield (§6), y se cancela.
6. **L+2 en adelante:** tarea programada semanal que arma el informe y te lo manda. No cuesta plata (usa tu plan de Claude). Si querés, la configuro yo cuando haya datos.

---

## 6. Generar piezas con IA: ¿Sunra, Higgsfield u otra?

### Primero: qué piezas necesitan IA y cuáles no

| Tipo de pieza | Cómo se hace | Costo |
|---|---|---|
| Pantallas reales de la app (cartera, diagnóstico, chat, avisos) | Capturas de `test/screenshots` y grabaciones de pantalla | US$0 |
| Porty animado (con accesorios) hablando o reaccionando | `tools/marketing/video/render_companion.mjs` y `render_overlays.mjs` | US$0 |
| La notificación de Porty en pantalla ("Tu cartera bajó 3,2 % hoy. Te cuento por qué") | Plantilla HTML renderizada con los mismos scripts | US$0 |
| Placas y carruseles | Canva (conectado) o `render_social.mjs` | US$0 |
| Edición, subtítulos, música comercial | CapCut (gratis) | US$0 |
| **Planos "de vida real"**: alguien en el colectivo, en la cocina o en el sillón que recibe el aviso y sigue con su día | **Video con IA** (ya se hicieron L1–L5 así con Sunra) | Lo único que cuesta |

Para el mensaje "Porty está atento", la fórmula de ad que proponemos es: **plano de vida real con IA (3–4 s) → la notificación de Porty (render propio) → pantalla real con la explicación → Porty con un accesorio + "Vos seguí con tu día."** Solo el primer plano necesita IA: con 4–6 planos por mes alcanza para variar las piezas.

### Comparación

| | **Sunra** | **Higgsfield** |
|---|---|---|
| Modelos de video | Kling 3.0/4.0, Veo 3.1, Seedance 2.0/2.5, Wan, MiniMax, Happy Horse y más | Kling, Veo, Seedance, Nano Banana y modelos propios (verificar lista actual) |
| Planes | Basic 1.200 créditos/mes, Pro desde 3.500, Creator desde 17.000 (dato del propio Sunra). **Precio en US$: no pude abrir sunra.ai/pricing desde este entorno, verificalo** | Basic US$9 / 120 créditos, Pro US$29 / 600, Max US$79 / 1.800 (fuentes de terceros de oct. 2026 que se contradicen; verificar) |
| Costo medido de un plano | Seedance 2.0 Fast 5 s 720p = **58 créditos**; Kling 3.0 standard 5 s = **63**; Veo 3.1 Fast 8 s = **80**; una imagen Nano Banana Pro = **14** → el Basic alcanza para **~19–20 planos de 5 s** | Depende del modelo; con 120 créditos el Basic puede quedar corto para video (verificar créditos por clip) |
| Gratis | Créditos diarios gratis, pero los modelos de video requieren plan activo | Plan gratis limitado (verificar) |
| Integración con este repo | **Está conectado a esta sesión** y ya hay pipeline (`sunra_gen.mjs`, `live_prompts/`): yo genero, reviso y armo el video final sin que vos toques nada | No está conectado: generás vos a mano en la web y subís los archivos |
| Fuerte | Automatización de punta a punta, mismos prompts versionados en el repo | Interfaz muy cómoda para humanos, presets de cámara y efectos, plantillas pensadas para ads y UGC |
| Tu saldo hoy | 0 créditos, sin plan | — |

### Recomendación
1. **Sunra Basic, un mes por vez, cuando haga falta un lote de planos.** Gana porque está integrado: con un mes saco ~20 planos, los combino con las pantallas y Porty animado, y te entrego los videos listos para subir. Es la opción que más automatiza sin pagar herramientas aparte. **Condición:** que el Basic cueste ≤ US$15 (verificalo en sunra.ai/pricing; si querés que lo vea yo, hay que habilitar `sunra.ai` en la red del entorno).
2. **Si el Basic de Sunra sale más caro, Higgsfield Basic (US$9)**, sabiendo que lo usás vos a mano y que alcanza para menos planos.
3. **En ninguno de los dos hace falta suscripción permanente**: se paga el mes del lote y se cancela. Un lote cada 1–2 meses alcanza con la cadencia de publicación del plan.
4. Modelo por defecto: **Seedance 2.0 Fast o Kling 3.0 standard** para planos de 5 s (los más baratos y suficientes para un plano de 3–4 s en vertical). Veo 3.1 solo si hace falta voz o sonido nativo.

Reglas para los planos con IA (compliance, `docs/legal/reviews/2026-11-03-plan-redes.md`):
- Nada de testimonios: una persona generada con IA no puede "contar su experiencia" con Porty.
- Las plataformas piden marcar el contenido realista generado con IA (Meta y TikTok tienen etiqueta de "hecho con IA"): activarla.
- Ningún ticker ni rendimiento en el plano; los números salen solo de la cuenta demo, con disclaimer.
