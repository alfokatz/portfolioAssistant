# Brief de producto: widget de Porty en la pantalla de inicio

**Fecha:** 2026-11-05 · **Autor:** porty-product-owner · **Siguiente:** porty-architect (spec técnica)
**Estado:** brief listo. Las decisiones del usuario que están abajo no se reabren.

## Decisiones ya tomadas (usuario)

- Contenido v1: valor total, variación del día (monto y %), una frase corta de Porty y 2–3 preguntas rápidas que abren el chat con la pregunta ya enviada. Tocar el resto del widget abre el chat.
- Muestra montos y %; un ajuste permite ocultar los montos.
- Gratis en todos los planes (apuesta a retención y hábito diario).
- No se escribe texto dentro del widget. Datos: al abrir la app + refresco en segundo plano (iOS con presupuesto diario, Android cada 30 min como mucho). El widget siempre dice "actualizado hace X".
- Cara normal de Porty. La cara contenta/triste es solo del informe semanal.
- Todo texto en es/en.

## 1. Problema y para quién

El inversor casual no abre Porty todos los días porque nada se lo recuerda, y el trabajo principal ("cómo va mi plata", PRODUCT.md) necesita abrir la app. **Para:** usuarios recurrentes de cualquier plan que ya tienen la cartera cargada.

Evidencia: intuición declarada. Hoy no medimos la frecuencia de apertura ni de dónde viene cada sesión (no hay evento de apertura). Que un widget suba la frecuencia es un supuesto que este brief mide.

## 2. Métrica de éxito y eventos

**Métrica principal (hábito):** días activos por semana de quienes agregan el widget, comparando las 2 semanas anteriores con las 2 posteriores, para el mismo usuario. Con poco volumen no hay A/B, y comparar a quienes lo tienen con quienes no está sesgado: la comparación es dentro del mismo usuario.

**Métricas de apoyo:**
- Adopción: % de usuarios activos con cartera que tienen el widget a los 30 días.
- Uso: % de las aperturas de la app, entre quienes tienen el widget, que vienen del widget.
- Preguntas rápidas: toques por pregunta y % que termina en una respuesta del chat.

**Umbrales (supuestos, sin línea de base; los ajusta porty-data-analyst):** adopción ≥ 10 % a 30 días; ≥ 25 % de las aperturas de esos usuarios desde el widget; días activos por semana +1 contra sus 2 semanas previas. **Criterio de corte:** con menos de 5 % de adopción a las 6 semanas no se invierte en una v2.

**Eventos mínimos en `product_events`.** Los registra la app al abrirse: el widget no tiene sesión de Supabase y no loguea nada solo.

| Evento | Cuándo | Props |
|---|---|---|
| `app_opened` | Cada apertura o vuelta a primer plano (con un intervalo mínimo que define data) | `source`: `icon` \| `widget` \| `widget_question` \| `push` \| `other` |
| `widget_opened` | La app se abrió desde el widget | `platform`, `size` (`small` \| `medium`), `target` (`chat` \| `question`), `question_id`, `data_age_min`, `amounts_hidden` |
| `widget_presence` | Al abrir la app, solo si cambió desde la última vez | `platform`, `sizes` (lista de los tamaños instalados; vacía = lo sacó) |
| `widget_amounts_toggled` | Cambió el ajuste de privacidad | `hidden` (bool) |

`app_opened` no existe hoy y es el denominador de todo (también le sirve al resto del roadmap). Si porty-data-analyst ya mide la retención con otra fuente, que lo diga en la spec antes de sumarlo.

## 3. Alcance mínimo

### Tamaños

| | iOS (WidgetKit) | Android |
|---|---|---|
| Chico | `systemSmall` | 2×2 |
| Mediano | `systemMedium` | 4×2 |

**Chico:** cara normal de Porty, valor total, variación del día en monto y % y "actualizado hace X". Sin frase ni preguntas: no entran sin romper el aire, y en iOS el widget chico tiene un solo destino de toque. Al tocarlo, abre el chat.

**Mediano:** todo lo del chico, más la frase de Porty (una línea, dos como mucho) y **2 preguntas rápidas** como filas de texto o chips sobrios. Recomiendo 2 en vez de 3 por espacio y calma (PRODUCT.md: *quiet*, sin densidad de trader). Al tocar fuera de las preguntas, abre el chat vacío.

Visual: las reglas de DESIGN.md (paleta clara y cálida, dark mode, cifras tabulares, sin verde neón ni número hero gigante). La variación con signo y color sobrio, como en la Home.

### Preguntas rápidas (fijas en v1, iguales para todos los planes)

Las dos se responden con `ownPortfolio`, que está en Free, así que ningún plan cae en un bloqueo al tocarlas:

| id | es | en |
|---|---|---|
| `today` | ¿Cómo viene mi cartera hoy? | How's my portfolio doing today? |
| `top_mover` | ¿Qué fue lo que más se movió? | What moved the most? |

- La URL lleva solo el `question_id`. La app traduce el id al texto en el idioma activo y lo envía. Nunca se manda texto libre por la URL: un link armado por otro no puede meterle una pregunta al chat.
- Cada pregunta gasta una consulta del mes, como cualquier otra (Free: 20). Si no le quedan consultas, aparece el paywall de cuota de siempre (`quota_zero`). El widget no abre un paywall nuevo.

### Frase de Porty: armada en el teléfono con datos reales, sin IA (recomendación)

**Por qué no IA:** el widget se refresca decenas de veces por día y por usuario. Generar la frase con el modelo cuesta en cada refresco, necesita sesión y red en segundo plano y puede inventar causas ("sube por la Fed") o colar consejos. Con plantillas cuesta cero, es determinístico, se puede testear y queda revisable por compliance.

**Reglas:**
- Solo describe hechos de los mismos números que muestra la Home. Nunca recomienda (sin "mantené", "comprá", "aprovechá"), nunca explica causas y nunca juzga ("buen día", "preocupante"). El tono queda neutro, igual que la cara.
- Plantillas iniciales (las ajusta growth en la voz de Porty y las revisa compliance):

| Caso | es | en |
|---|---|---|
| Movimiento chico (\|Δ%\| < 0,3) | Día tranquilo: tu cartera casi no se movió. | A quiet day: your portfolio barely moved. |
| Sube, con el mayor aporte conocido | Tu cartera sube hoy; lo que más empuja es {TICKER}. | Your portfolio is up today, led by {TICKER}. |
| Baja, con el mayor aporte conocido | Tu cartera baja hoy; lo que más pesa es {TICKER}. | Your portfolio is down today; {TICKER} weighs the most. |
| Sube o baja, sin el dato del mayor aporte | Tu cartera sube hoy. / Tu cartera baja hoy. | Your portfolio is up today. / Your portfolio is down today. |
| Mercado cerrado | Mercado cerrado: así quedó al último cierre. | Market closed: here's the last close. |
| Datos viejos (> 24 h) | Abrí Porty para ponerla al día. | Open Porty to bring it up to date. |

- **Con los montos ocultos no aparece el {TICKER}:** el ticker revela qué tiene. Se usa la versión sin el mayor aporte.

### Ajuste de privacidad

"Ocultar montos en el widget" en Ajustes, apagado por defecto. Prendido, los montos (valor total y variación en $) se ven como `••••`. Siguen visibles el %, la frase sin ticker y las preguntas. Se aplica en el próximo refresco y, si se puede, en el momento.

## 4. Estados

| Estado | Qué ve | Al tocar |
|---|---|---|
| Sin sesión (nunca entró, cerró sesión o borró la cuenta) | Cara normal + "Entrá a Porty para ver tu cartera acá." / "Sign in to Porty to see your portfolio here." Sin números. | Abre la app (login) |
| Sesión, sin cartera | "Cargá tu cartera y la vas a ver acá." / "Add your portfolio to see it here." Sin preguntas. | Abre la app en la carga de cartera (o en la Home si el link no se puede) |
| Datos frescos | Normal + "actualizado hace X" | Según el destino |
| Datos viejos (> 24 h o de otro día) | Números en tono atenuado, la etiqueta dice la fecha ("al 3 nov") en vez de "hoy" y la frase de datos viejos | Abre la app y refresca |
| Mercado cerrado o fin de semana | Valor y variación del último cierre, con la etiqueta "Último cierre" / "Last close" en vez de "Hoy" y la frase de mercado cerrado | Según el destino |
| Sin red o refresco fallido | Últimos datos buenos con su "actualizado hace X". Nunca un error ni ceros. | Según el destino |
| Cartera mixta (cripto 24/7 + acciones) | Mismo número y etiqueta que la Home en ese momento. El widget no calcula nada propio. | — |

Regla general: **el widget nunca muestra un número que la Home no mostraría.** Al cerrar sesión o borrar la cuenta, los datos del widget se borran en el momento: es información financiera a la vista en la pantalla de inicio.

## 5. Fuera de v1

- Widget grande, pantalla bloqueada, StandBy, Apple Watch, Live Activities, macOS o web.
- Widget configurable (elegir preguntas, cuenta o bróker) y preguntas que cambian según el día.
- Lista de posiciones, gráfico o sparkline en el widget.
- Botones que hacen algo sin abrir la app (App Intents interactivos de iOS 17).
- Frase generada por IA. Cara con humor según el rendimiento.
- Preguntas de Premium o Gold (p. ej. "¿por qué se movió lo mío?") y cualquier paywall que salga del widget.
- Alertas, noticias o el informe semanal dentro del widget.
- Refresco forzado por push silencioso. Si el refresco nativo no alcanza, se evalúa en v2 con datos de `data_age_min`.

## 6. Criterios de aceptación de usuario

1. Puedo agregar Porty chico y mediano en iOS y en Android, desde la galería de widgets, con nombre y descripción en mi idioma.
2. Con sesión y cartera, el chico muestra la cara normal, el valor total, la variación del día en monto y % y "actualizado hace X". Los números son los mismos que veo en la Home en ese momento.
3. El mediano agrega la frase de Porty y las dos preguntas rápidas en mi idioma (es o en, según el idioma de la app).
4. Al tocar una pregunta, se abre el chat con esa pregunta enviada y se responde con los datos de mi cartera en cualquier plan, incluido Free. Gasta una consulta. Sin consultas, veo el paywall de cuota de siempre.
5. Al tocar fuera de las preguntas, se abre el chat sin pregunta enviada.
6. La app enviada nunca manda al chat un texto que venga en la URL: solo ids conocidos. Un id desconocido abre el chat vacío.
7. La frase nunca recomienda comprar, vender o mantener, nunca da una causa y nunca juzga. Sale de las plantillas aprobadas por compliance.
8. Con "Ocultar montos" prendido veo `••••` en lugar de los montos, y la frase sin ticker. El % se sigue viendo.
9. Sin sesión veo el mensaje para entrar, sin números. Al cerrar sesión o borrar la cuenta, el widget deja de mostrar mis datos sin que tenga que abrir nada más.
10. Sin cartera veo el mensaje para cargarla y no aparecen preguntas.
11. Con datos de más de 24 h o de otro día, los números se ven atenuados, con su fecha y la frase de datos viejos. Nunca dice "hoy" sobre datos de otro día.
12. Con el mercado cerrado o en fin de semana, la etiqueta dice "Último cierre", no "Hoy".
13. Sin red, el widget mantiene los últimos datos buenos con su antigüedad. Nunca muestra ceros ni un error.
14. Al abrir la app, el widget se actualiza. En segundo plano se actualiza dentro de lo que permite cada sistema.
15. Se ve bien en modo claro y oscuro, con textos grandes del sistema (sin cortar cifras) y con lectores de pantalla: el valor y la variación se leen como una frase.
16. Se registran `app_opened{source}`, `widget_opened`, `widget_presence` y `widget_amounts_toggled` con las props de §2, y no se registra nada sin sesión.

## 7. Impacto y prioridad

- **Negocio:** retención y hábito (principal). Conversión solo de forma indirecta: más días activos son más momentos de intención. Costo de IA marginal ≈ 0, porque la frase es local y las preguntas usan la cuota que ya existe.
- **RICE (supuestos, sin datos):** R = 15 % de los activos con cartera · I = 1 · C = 50 % · E ≈ 7 días-persona (dos plataformas nativas, deep links nuevos, refresco en segundo plano y es/en) → **score ≈ 1,1**. Las apuestas de noviembre del roadmap están entre 7,5 y 18. El widget entra por decisión del usuario, no por RICE: es una apuesta de hábito que el método subestima porque no tenemos ningún dato de frecuencia.
- **Secuencia recomendada:** después del release 1 (borrado de cuenta + paywall medible), sin sacarle gente. La infraestructura de deep links que crea este trabajo después la reusan las notificaciones (`docs/backlog/notificaciones-y-alertas-de-precio.md`) y el link de OAuth sin registrar.

## Decisiones del usuario (2026-11-05)

- Las preguntas del widget **gastan consulta** como cualquier otra.
- **Sin** tercera pregunta en v1 ("¿Por qué se movió lo mío?" queda para después).
- **Arranca ya**, en paralelo con el release 1.

## Puntos que se le plantearon al usuario

1. **¿Las preguntas del widget gastan consulta?** Recomiendo que sí, como cualquier otra. La alternativa (no gastar) premia el hábito, pero abre una puerta a consumo sin tope.
2. **Sumar "¿Por qué se movió lo mío?" como tercera pregunta.** Es la más natural en un widget, pero es de Premium (`heldNews`): en Free terminaría en un aviso de Premium y el widget dejaría de ser 100 % gratis en la práctica. Recomiendo dejarla fuera de v1.
3. **Cuándo entra.** El roadmap de noviembre dice "sin features nuevas"; recomiendo arrancar después de enviar el release 1.

## Revisión de compliance (2026-11-05)

**Autor:** porty-compliance (no es asesoramiento legal) · **Veredicto:** ok con cambios en los textos. No bloquea. Revisé §3 (frase, preguntas), §4 (estados) y el criterio 7. No toqué esas secciones: **las plantillas de abajo reemplazan a las de §3 y §4** y las usa la spec técnica tal cual.

### 1. Plantillas aprobadas de la frase (reemplazan a §3)

| Caso | es (final) | en (final) | Cambio |
|---|---|---|---|
| Movimiento chico (\|Δ%\| < 0,3) | Tu cartera casi no se movió hoy. | Your portfolio barely moved today. | CORREGIR: "Día tranquilo" califica el día (juzga y puede ser falso en un mercado agitado). |
| Sube, con el mayor aporte | Tu cartera sube hoy; {TICKER} sumó más. | Your portfolio is up today; {TICKER} added the most. | CORREGIR: "empuja" / "led by" suena a causa. "Sumó más" es solo aritmética de los números de la Home. |
| Baja, con el mayor aporte | Tu cartera baja hoy; {TICKER} restó más. | Your portfolio is down today; {TICKER} took away the most. | CORREGIR: "pesa" se confunde con el peso en la cartera y sugiere causa. |
| Sube o baja, sin ese dato | Tu cartera sube hoy. / Tu cartera baja hoy. | Your portfolio is up today. / Your portfolio is down today. | Aprobado sin cambios. |
| Último cierre (mercado cerrado o fin de semana) | Valores al último cierre. | Values as of the last close. | CORREGIR: "Mercado cerrado" es falso en una cartera mixta con cripto (24/7). Solo dice a qué momento corresponden los datos. |
| Datos viejos (> 24 h o de otro día) | Datos desactualizados. Abrí Porty para actualizarlos. | Data is out of date. Open Porty to refresh it. | CORREGIR: "ponerla al día" no dice qué pasa. Ahora avisa que el número no es actual. |
| Montos ocultos (con o sin mayor aporte) | Se usa la fila "sin ese dato": Tu cartera sube hoy. / Tu cartera baja hoy. | Your portfolio is up today. / Your portfolio is down today. | Sin cambios de texto: nunca lleva ticker. |

Reglas que se mantienen y se suman (sirven de test para la spec técnica):
- Ninguna plantilla lleva: verbos de acción sobre el usuario (mantené, aprovechá, comprá), adjetivos de valoración (buen, mal, tranquilo, preocupante), causas (por, gracias a, debido a) ni futuro o proyección.
- "Hoy" solo cuando los datos son de hoy. Con datos de otro día o último cierre, la frase direccional (sube/baja) **no se muestra**: solo la frase de cierre o de datos viejos. Si no, "Tu cartera sube hoy" sería falso.
- {TICKER} es el símbolo tal cual (sin nombre de la empresa ni emojis). Con montos ocultos nunca se renderiza ni se manda al widget: el dato no debe llegar al almacén del widget en ese caso, no solo esconderse al dibujar.
- Cada plantilla tiene un test que compara el texto exacto, en es y en. Cualquier plantilla nueva pasa de nuevo por compliance.

### 2. Preguntas rápidas (§3)

Aprobadas sin cambios:
- `today`: "¿Cómo viene mi cartera hoy?" / "How's my portfolio doing today?"
- `top_mover`: "¿Qué fue lo que más se movió?" / "What moved the most?"

Son preguntas neutras y no inducen a operar. Solo ids por URL (criterio 6): correcto. Dos notas:
- SUGERENCIA: en inglés "What moved the most in my portfolio?" evita que alguien entienda "en el mercado". Opcional.
- Las respuestas del chat quedan bajo el prompt y los disclaimers del asistente, no del widget. Con datos de otro día, la pregunta dice "hoy": la app debe responder con la fecha real de los datos, no asumir hoy.

### 3. Estados (§4)

- Sin sesión, Sin cartera, Datos frescos, Sin red: textos aprobados sin cambios. No muestran datos personales.
- Datos viejos y Último cierre: ver frases de la tabla 1. Las etiquetas "al 3 nov" y "Último cierre / Last close" están bien.
- CORREGIR (accesibilidad y privacidad): con montos ocultos, el lector de pantalla debe decir "montos ocultos" y **no** leer el valor aunque esté en el almacén; el texto accesible se arma desde el mismo estado ya ocultado.
- CORREGIR: las vistas previas de la galería de widgets (iOS `getSnapshot` con `isPreview`, selector de Android) usan **datos de ejemplo ficticios**, nunca la cartera real, aunque haya sesión.
- Regla de §4 ("borra al cerrar sesión o borrar la cuenta"): aprobada. Debe cubrir también el caché local de la frase y de la fecha de actualización, no solo los números.

### 4. Pantalla bloqueada y a la vista (riesgo de exposición)

El brief deja fuera el widget de pantalla bloqueada, pero el `systemSmall` de iOS puede verse igual en StandBy (iOS 17+) con el teléfono bloqueado, y en iPad/Mac. Pedido a flutter-dev y architect:
- Marcar valor, variación, % y ticker con `.privacySensitive()` en iOS para que el sistema los oculte con el dispositivo bloqueado. Las fuentes que encontré dicen que el efecto depende de la versión y de los ajustes del usuario (https://developer.apple.com/documentation/swiftui/controlwidgettemplate/privacysensitive(_:), https://developer.apple.com/forums/thread/806236): **probalo en un teléfono real bloqueado y en StandBy** antes de publicar. No lo pude comprobar.
- Riesgo residual que decidió el usuario: con "Ocultar montos" el % y sube/baja siguen visibles. No revela qué tenés ni cuánto, pero sí el rendimiento. Aceptable, y lo dejo anotado por si querés una opción "ocultar todo" en v2.
- Android: los widgets de inicio no aparecen bloqueados en teléfonos. Sin condiciones extra.

### 5. Política de privacidad, ficha de tiendas y disclaimers

**Datos en el teléfono (política de privacidad): sí, sumar una frase.** El widget guarda un resumen de la cartera (valor, variación, ticker, hora, ajuste de ocultar) en el almacenamiento compartido de la app (App Group en iOS, almacenamiento privado de la app en Android). No sale del teléfono ni suma terceros, así que **no cambia las etiquetas de privacidad de Apple ni el Data safety de Google** por sí mismo (no es "recopilación" si no se transmite). Pero transparencia y minimización lo piden (Ley 25.326 art. 4; GDPR art. 13: https://eur-lex.europa.eu/eli/reg/2016/679/oj). Texto propuesto para Privacidad:
- es: "Si agregás el widget de Porty, guardamos en tu teléfono un resumen de tu cartera (valor total, variación del día y el activo que más aportó) para mostrarlo en la pantalla de inicio. No sale de tu teléfono. Se borra cuando cerrás sesión o borrás tu cuenta. Podés ocultar los montos en Ajustes."
- en: "If you add the Porty widget, we store a summary of your portfolio (total value, daily change and the top contributor) on your phone to show it on your home screen. It does not leave your phone. It is deleted when you sign out or delete your account. You can hide amounts in Settings."

**Eventos del widget:** `app_opened`, `widget_opened`, `widget_presence` y `widget_amounts_toggled` son uso de la app ligado a la cuenta. Verificar que la etiqueta de Apple (Product Interaction, vinculado al usuario) y el Data safety de Google (App activity) ya lo declaren. Si hoy no hay analítica declarada, hay que sumarla antes de enviar. No pude abrir las páginas de Privacidad/Términos ni los formularios de las tiendas desde acá.

**Texto en la app (Ajustes), junto a "Ocultar montos en el widget":**
- es: "El widget guarda un resumen de tu cartera en este teléfono. Se borra al cerrar sesión."
- en: "The widget keeps a summary of your portfolio on this phone. It's deleted when you sign out."

**Disclaimer en el widget: no hace falta.** La frase es descriptiva, sin recomendación, y un disclaimer en un widget es ruido. El "información, no asesoramiento" va en la app y en la ficha como ya corresponde. Si en el futuro la frase pasa a IA o recomienda algo, hay que volver a revisar.

**Galería de widgets (nombre y descripción, criterio 1), propuesta:**
- es: "Porty" / "Mirá cómo viene tu cartera sin abrir la app."
- en: "Porty" / "See how your portfolio is doing without opening the app."
- Sin "en tiempo real" ni promesas de ganancia: los datos tienen retraso y el widget lo dice.

**Ficha de tiendas y capturas:** si se muestra el widget, usar datos de ejemplo claramente ficticios, sin porcentajes de ganancia llamativos, y no decir "tiempo real" ni "no te pierdas ningún movimiento". Apple 2.3 exige que metadata y capturas reflejen lo que la app hace de verdad: https://developer.apple.com/app-store/review/guidelines/#accurate-metadata. Pasar el texto por compliance antes de publicar.

**Guidelines de las tiendas:**
- Apple 2.5.16: los widgets deben estar relacionados con el contenido y la funcionalidad de la app. Cumple (https://developer.apple.com/app-store/review/guidelines/). No encontré condiciones extra para widgets de apps financieras. Aplican las condiciones generales de privacidad 5.1.1(i) (política de privacidad que diga qué datos se guardan y cómo se borran: ver frase de arriba) y 5.1.2(i).
- Google Play: la política de borrado de cuenta (https://support.google.com/googleplay/android-developer/answer/13327111) pide que se borren los datos al borrar la cuenta; los datos del widget entran. No encontré reglas específicas de widgets. No pude abrir las demás políticas de Play: confirmar la declaración de "funciones financieras" de la Play Console, que aplica a la app, no al widget.
- SUGERENCIA para devops: excluir el almacenamiento del widget del backup automático de Android (`dataExtractionRules`/`fullBackupContent`) para que un dato financiero no viaje a otro dispositivo.

### 6. Requiere abogado

- **Sí, pero no por el widget:** Apple 3.2.1(viii) y 5.1.1(ix) piden que las apps de inversión o dinero ("trading, investing or money management") y de campos regulados las envíe una entidad legal con licencias en cada país, no un desarrollador individual. Porty se define como información, no asesoramiento ni ejecución, pero la línea no es obvia para una app con cuentas de brókers. Un abogado debería confirmar cómo se publica (cuenta de organización) y si hace falta alguna licencia en Argentina y LatAm. Ya aplica a la app entera.
- Revisión humana de la frase de privacidad de arriba antes de publicarla en la política (no pude verificar la política actual).

### 7. Criterio de aceptación 7, ajustado

> La frase sale solo de las plantillas de esta sección. Nunca recomienda, da una causa, juzga ni proyecta. Nunca dice "hoy" sobre datos de otro día ni "mercado cerrado". Con montos ocultos, nunca lleva ticker.

## Ampliación: noticias y resultados (2026-11-05)

**Autor:** porty-product-owner · **Siguiente:** porty-compliance (preguntas de abajo) → porty-architect (spec).
Entra en v1 por decisión del usuario. **Esta sección reemplaza** las líneas de §5 "Widget grande", "Preguntas de Premium o Gold… y cualquier paywall que salga del widget" y "Alertas, noticias… dentro del widget". El resto de §1–§7 y la revisión de compliance siguen vigentes.

Decisiones del usuario (no se reabren): gating según `PlanMatrix` (noticias de lo que tiene = `heldNews`, Premium y Gold; earnings = `earnings`, solo Gold); Free y Premium ven un aviso que abre el paywall; el chico no cambia; en el mediano el ítem más importante reemplaza a la frase; widget grande nuevo con resumen y hasta 4 ítems; noticias y earnings se actualizan solo al abrir la app (el refresco en segundo plano no tiene sesión).

**Problema y apuesta.** Hoy el widget dice *cuánto* se movió la cartera, pero no *qué pasó* con lo que tenés. Lo que tiene que saber un inversor casual es que hay una noticia de su acción o que presenta resultados el jueves: le da un motivo para abrir la app y, en Free y Premium, es el momento más natural para mostrar el plan siguiente. Evidencia: intuición del usuario. No hay datos de conversión ni de uso del widget (sale sin probar).

### A1. Qué es "importante" (sin IA)

Se calcula en el teléfono al abrir la app, con datos que ya existen (`CompanyNewsItem`, `EarningsCalendarEntry`), sin modelo ni costo de IA.

**Universo:** posiciones de acciones y ETF con ticker de Finnhub, las **5 de más peso** en la cartera (limita las llamadas a Finnhub y la lista a lo que mueve la plata). Cripto queda afuera en v1 (Finnhub company news no la cubre).

**Orden de prioridad:**
1. **Resultados en los próximos 7 días** (desde hoy, inclusive), primero el más cercano y, en el mismo día, la posición de más peso. Máximo 2.
2. **Noticia de las últimas 48 h**, ordenadas por **peso de la posición** (no por recencia). Una noticia por ticker (la más reciente) y sin titulares repetidos (mismo titular normalizado = una).
3. Desempate: la más reciente.

No se usan "palabras clave importantes" ni sentimiento: sería una forma de juicio que no podemos testear bien sin IA. El peso de la posición es el proxy de "importa para tu plata".

**Cuántos ítems:** mediano 1 · grande hasta 4 · chico 0.

**Antigüedad máxima:** noticia **48 h** desde su publicación; resultado, hasta el **fin del día** de la fecha de presentación (hora local). Como el refresco en segundo plano no puede buscar datos nuevos pero sí volver a dibujar, **en cada refresco el widget recalcula la antigüedad y descarta lo vencido** con datos locales. Así nunca muestra una noticia de hace 4 días por no haber abierto la app.

### A2. Formato y destino del toque

**Noticia:** `{TICKER} · {fuente} · {antigüedad}` en una línea chica y el titular en hasta 2 líneas (corta con "…"). Antigüedad: "hace 25 min", "hace 3 h", "ayer" (es) / "25m ago", "3h ago", "yesterday" (en). Sin resumen ni imagen. El titular va **tal cual en el idioma de origen** (casi siempre inglés): traducirlo pide IA y no entra en v1.

**Resultados:** `{TICKER} presenta resultados {hoy | mañana | el jue 7 nov}` + "antes de la apertura / después del cierre" si Finnhub trae `hour` (`bmo`/`amc`); si no, sin hora. En: "{TICKER} reports earnings {today | tomorrow | Thu, Nov 7}" + "before the open / after the close". Sin estimaciones de ganancias, sin "sorpresa" y sin flecha.

**Al tocar un ítem (decisión):** abre Porty en una **hoja de "Novedades de tu cartera"** con el ítem tocado arriba y el resto de la lista. Desde ahí:
- "Leer en {fuente}" abre el artículo en el navegador del sistema (no gasta consulta).
- "Preguntale a Porty" abre el chat con una pregunta fija por id (`news_why` "¿Qué pasó con {TICKER}?" / `earnings_when` "¿Cuándo presenta {TICKER} y qué presentó la última vez?"). **Gasta una consulta**, igual que las preguntas del widget, pero solo si el usuario la toca: tocar el widget nunca gasta una consulta sin una segunda confirmación.
- Si la app ya tiene una pantalla de noticias o de la posición que sirva, el architect puede usarla en vez de la hoja nueva. Lo que importa: un toque abre la app (hábito), no el navegador.

**Seguridad del link:** la URL lleva solo `type` (`news` | `earnings` | `teaser_news` | `teaser_earnings`) y un id de ítem local. La app busca el ítem en su caché; si no existe o venció, abre la Home. Nunca se arma texto, URL externa ni pregunta desde el link.

**Aviso de plan (teaser):**
- Free, con noticias de su cartera: "Hay 2 noticias de tu cartera · Premium" / "2 news on your holdings · Premium". Con 1: "Hay 1 noticia…" / "1 news story…".
- Premium, con resultados en 7 días: "Una acción de tu cartera presenta resultados esta semana · Gold" / "One of your holdings reports earnings this week · Gold". Con varias: "2 acciones de tu cartera…".
- **El aviso no muestra el ticker (decisión).** El ticker y la fecha son el valor del plan (decir "NVDA presenta el jueves" ya es el calendario de earnings regalado), y además mantiene la regla de privacidad de abajo sin dos variantes. El número sí se muestra: es concreto y verificable.
- Un solo aviso por widget y siempre **del plan siguiente**: Free ve solo el de Premium (aunque haya resultados); Premium solo el de Gold. Gold no ve avisos.
- Tocarlo abre el paywall con `source` = `widget_held_news` o `widget_earnings` (la medición de paywall del release 1 tiene que aceptar esas fuentes).
- Si hay ítems desbloqueados, el aviso va **después** de ellos (en el grande, como última fila). En el mediano, el aviso reemplaza a la frase solo si no hay ningún ítem desbloqueado y hay al menos una noticia de las últimas 24 h (no de 48): limita cuánto tiempo el widget de un Free es un aviso de pago.
- Interruptor `app_config.widget_teasers` (se lee al abrir la app) para apagar los avisos sin una versión nueva.
- Si para contar noticias de un Free hace falta que el proxy de Finnhub lo permita y hoy lo bloquea por plan, el aviso va **sin número** ("Noticias de tu cartera · Premium"). Lo decide el architect; no se abre el contenido al cliente Free para contarlo.

### A3. Widget grande (iOS `systemLarge`, Android 4×4)

De arriba a abajo:
1. Encabezado igual al chico: cara normal, valor total, variación del día (monto y %), "actualizado hace X".
2. La frase de Porty (una línea), con las plantillas aprobadas.
3. **Novedades de tu cartera / Your holdings news**: hasta 4 ítems (A1) y, si corresponde, el aviso de plan como última fila (cuenta dentro de los 4).
4. Las 2 preguntas rápidas (`today`, `top_mover`) en una fila.

Sin gráfico, sin lista de posiciones y sin colores de alarma (PRODUCT.md: *quiet*). Los ítems se separan con líneas finas, no con cards.

**Mediano (cambio):** encabezado + **el ítem más importante en lugar de la frase** (si no hay, la frase como antes) + las 2 preguntas. El aviso de plan solo entra según la regla de A2.

### A4. "Ocultar montos"

Con el ajuste prendido, **no se guardan en el almacén del widget ni el ticker ni el titular ni la fuente** (un titular delata qué tenés tanto como el ticker). Se guarda y se muestra solo el tipo y la antigüedad:
- Noticia: "Noticia de tu cartera · hace 3 h" / "News on your holdings · 3h ago".
- Resultados: "Una acción de tu cartera presenta resultados el jue" / "One of your holdings reports earnings Thu".
- El toque abre la hoja en la app, donde sí se ve todo (la app ya está desbloqueada).
- Los avisos de plan no cambian (ya no llevan ticker).
- Como el ajuste ahora cubre más que montos, el texto en Ajustes pasa a "Ocultar montos y posiciones en el widget" / "Hide amounts and holdings in the widget" (cambio de texto; lo revisa compliance con el resto).

### A5. Estados

| Estado | Mediano | Grande |
|---|---|---|
| Sin noticias ni resultados vigentes | La frase de Porty (como antes) | Sección de novedades con "Sin novedades de tu cartera en las últimas 48 h" / "No news on your holdings in the last 48h" |
| Sin resultados próximos, con noticias | Noticia de más peso | Solo noticias; no se muestra "sin resultados" |
| Todo venció y no abrió la app | La frase | "Abrí Porty para ver las novedades de tu cartera" / "Open Porty to see your holdings news" |
| Plan vencido (Premium o Gold que caducó) | Al abrir la app se recalcula con el plan nuevo. En segundo plano, el widget guarda la fecha de vencimiento conocida del plan (si RevenueCat la da) y, pasada esa fecha, se dibuja como el plan inferior (borra los ítems bloqueados del almacén y muestra el aviso). Si no hay fecha, los ítems ya cargados se ven hasta vencer por antigüedad (máx. 48 h / 7 días): aceptable | Igual |
| Datos de cartera viejos (> 24 h) | Encabezado atenuado como en §4; los ítems se muestran si todavía no vencieron, con su propia antigüedad | Igual |
| Falla Finnhub o sin red al abrir | Se mantienen los ítems anteriores que no vencieron; nunca un error | Igual |
| Sin sesión / sin cartera | Como §4, sin novedades ni avisos | Igual |
| Cartera solo cripto | Sin novedades (fuera de v1); la frase | Sección oculta, se agrandan las preguntas |
| Gold | Sin avisos | Sin avisos |

Al cerrar sesión o borrar la cuenta se borran también los ítems y los avisos del almacén (regla de §4).

### A6. Eventos nuevos

El widget no tiene sesión: todo se registra al abrir la app. Las **impresiones no se pueden medir con fidelidad** (un refresco del sistema no es una vista del usuario), así que se mide lo que se dibujó como aproximación y se dice así.

| Evento | Cuándo | Props |
|---|---|---|
| `widget_opened` (amplía §2) | Se abrió la app desde el widget | `size` suma `large`; `target` suma `news` \| `earnings` \| `teaser_news` \| `teaser_earnings`; nuevas `item_rank` (1–4), `item_age_h`, `tier` |
| `widget_items_rendered` | Al abrir la app, si el widget dibujó novedades desde la última apertura (contador local) | `size`, `news_count`, `earnings_count`, `teaser` (`none` \| `news` \| `earnings`), `tier`, `amounts_hidden` |
| `widget_item_action` | Acción en la hoja de novedades | `action` (`read_source` \| `ask_porty`), `type` (`news` \| `earnings`), `from_widget` (bool) |
| `paywall_viewed` (existente) | Paywall abierto desde el aviso | `source` = `widget_held_news` \| `widget_earnings` |

`widget_presence.sizes` suma `large`.

**Métricas de éxito de la ampliación** (umbrales supuestos; los ajusta porty-data-analyst):
- Toques en ítems / aperturas desde el widget: ≥ 30 % de las aperturas desde el widget vienen de un ítem (si es mucho menor, las novedades no atraen y se sacan del mediano).
- Días activos por semana de los que tienen el widget mediano o grande con novedades vs. sus 2 semanas previas (misma métrica principal de §2).
- Conversión: compras con `source` del widget / avisos tocados. Sin línea de base: la primera lectura sirve de base, no de veredicto. Con poco volumen, no hay A/B; sí se compara con el interruptor `widget_teasers` apagado y prendido por períodos, si hace falta.
- Señal de alarma: si después de los avisos crece `widget_presence` con la lista vacía (gente que saca el widget) en Free, apagar `widget_teasers`.

### A7. Criterios de aceptación nuevos

17. Puedo agregar el widget grande en iOS (`systemLarge`) y Android (4×4), con nombre y descripción en mi idioma. El chico se ve igual que antes.
18. Como Premium o Gold, el mediano muestra la novedad más importante en lugar de la frase; si no hay ninguna vigente, muestra la frase.
19. El grande muestra el encabezado, la frase, hasta 4 novedades y las 2 preguntas.
20. Las novedades siguen el orden de A1: resultados en 7 días primero, después noticias de 48 h por peso de la posición, una por ticker, sin repetidas. Solo de las 5 posiciones de más peso.
21. Solo Gold ve resultados; Premium y Gold ven noticias. Free nunca ve un titular ni un ticker de novedades; Premium nunca ve una fecha de resultados.
22. Free con noticias ve "Hay N noticias de tu cartera · Premium"; Premium con resultados ve el aviso de Gold. Ningún aviso lleva ticker. Hay un solo aviso por widget, del plan siguiente, y Gold no ve avisos. Tocarlo abre el paywall con `source` del widget.
23. Una noticia de más de 48 h o un resultado de un día pasado desaparece del widget aunque no abra la app.
24. Tocar una novedad abre la app en la hoja de novedades, con ese ítem arriba. No gasta consulta. "Leer en {fuente}" abre el artículo; "Preguntale a Porty" abre el chat con la pregunta y gasta una consulta.
25. Un link con un id desconocido o vencido abre la Home, sin error.
26. Con "Ocultar montos y posiciones" prendido, ninguna novedad muestra ticker, titular ni fuente, y esos datos no están en el almacén del widget. El lector de pantalla tampoco los lee.
27. Si mi plan venció, el widget deja de mostrar lo que ya no tengo a más tardar al abrir la app (o en la fecha de vencimiento si se conoce).
28. Con `app_config.widget_teasers` apagado no aparece ningún aviso de plan.
29. Las vistas previas de la galería usan novedades ficticias (ticker y titular inventados), nunca las mías.
30. Se registran los eventos de A6 con sus props, y nada sin sesión.

### A8. Preguntas para porty-compliance

1. **Derechos sobre los titulares:** ¿los términos de Finnhub (plan actual) y de las fuentes permiten mostrar titular + fuente + link fuera de la app, en un widget del sistema, y cachearlos hasta 48 h en el teléfono? ¿Hace falta atribución a Finnhub además de la fuente? ¿Cambia si el usuario es Free y solo ve el conteo?
2. **No es asesoramiento:** un titular de terceros puede decir "Buy now" o "stock to sell". ¿Alcanza con mostrar la fuente y que no sea texto de Porty, o hay que filtrar titulares con lenguaje de recomendación? ¿El orden por peso de la posición puede leerse como "Porty te marca qué mirar"? ¿Los textos de resultados ("presenta resultados", "antes de la apertura") y las preguntas `news_why` / `earnings_when` están bien?
3. **Aviso de pago en la pantalla de inicio:** ¿un aviso "· Premium" o "· Gold" dentro del widget choca con Apple 2.5.16 (widgets ligados al contenido de la app), 3.1.1/3.1.2 o las reglas de Google sobre publicidad y widgets? ¿Aplican las limitaciones del aviso (uno solo, solo plan siguiente, tope en el mediano, interruptor remoto) o hace falta algo más? ¿El conteo de noticias para un Free implica procesar contenido pago para un usuario que no paga?
4. **Privacidad:** la frase de la política de privacidad aprobada (§5 de compliance) tiene que sumar "y titulares de noticias de tus posiciones". Revisar el nuevo texto del ajuste "Ocultar montos y posiciones".
5. **Ficha y capturas:** si se muestra el widget grande con novedades, ¿qué condiciones (titulares ficticios, sin marcas de medios reales)?

### A9. Impacto y prioridad

- **Negocio:** retención (motivo concreto para abrir) y **conversión** (primer aviso de pago fuera de la app, con fuente medible). Costo de IA: 0. Costo de Finnhub: hasta 5 llamadas de noticias + 1 de calendario por apertura, con la caché que ya tienen los repositorios; el architect confirma que entra en el límite del plan de Finnhub y en la cuota del proxy.
- **Esfuerzo extra estimado:** +4–5 días-persona sobre v1 (tamaño grande en dos plataformas, selección y vencimiento local, hoja de novedades, gating, avisos y eventos). Sin datos para un RICE serio; entra por decisión del usuario.
- **Riesgo principal:** que el widget de un Free se vuelva un aviso de pago y lo saquen. Mitigación: reglas de A2, interruptor y la señal de alarma de A6.

### Decisiones del usuario sobre la ampliación (2026-11-05)

- **"Ocultar montos" oculta SOLO montos.** Con el ajuste activado, las noticias y los resultados se siguen mostrando con ticker, titular y fuente. El nombre del ajuste no cambia. (Esto reemplaza lo propuesto en A sobre ocultar ticker/titular/fuente; la regla previa de la frase de Porty sin ticker con montos ocultos se mantiene.)
- **Titulares en inglés, sin traducir.**
- **Cripto afuera en v1** (solo acciones y ETFs).

## Revisión de compliance: ampliación (2026-11-05)

**Autor:** porty-compliance (no es asesoramiento legal) · **Veredicto: bloquea** hasta resolver H1 (fuente de datos) y H2 (aviso de pago en iOS). El resto es ok con cambios de texto. Revisé A1–A9 y las decisiones del usuario. **Las decisiones del usuario se respetan:** "Ocultar montos" solo oculta montos y no lo revierto; lo que sigue son condiciones para hacerlo bien. Mi revisión de la v1 (arriba) sigue vigente, salvo donde esta la completa.

### Hallazgos

```
[BLOQUEA] A1 / A8.1 — La fuente de datos de la ampliación no tiene licencia para esto
Por qué: A1 usa CompanyNewsItem y EarningsCalendarEntry, que son Finnhub (company-news y calendar/earnings). Los términos de Finnhub (https://finnhub.io/terms-of-service, leídos hoy) dicen que no se puede "redistribute or share access to data or derived results from the data" sin aprobación escrita, que los planes publicados son "strictly for personal use unless explicitly stated otherwise", que un plan personal no puede usarlo ningún negocio, y que "all data must be deleted" si termina la suscripción. Un widget que muestra titulares a usuarios que pagan una suscripción es uso comercial y redistribución. El proyecto ya lo sabía: docs/runbooks/news-sources-v2.md reemplaza Finnhub free por SEC, búsqueda web y GDELT justamente por esto, y la Fase 4 borra los repositorios de Finnhub de noticias y earnings. Los términos no hablan de atribución ni de mostrar en widgets: no es un permiso, es un silencio, y la regla de no redistribuir manda.
Texto propuesto: la ampliación lee del camino v2 (`headlines` de GDELT + allowlist para noticias; `sec` para resultados), no de Finnhub. Si se quiere Finnhub, solo con plan comercial y permiso escrito de Finnhub para mostrar en una app/widget de terceros (hay que pedirlo).
Revisión humana: sí
```

Consecuencias de pasar a v2 que cambian la spec (se las paso a `porty-product-owner`):
- **Las fechas de resultados son estimadas** (EDGAR no tiene calendario: último reporte + 364 días o + 91). "Presenta resultados el jueves" sería afirmar algo que no sabemos. Textos nuevos abajo. No hay `hour` (bmo/amc): se elimina "antes de la apertura / después del cierre".
- **`headlines`, `sec` y `news-context` hoy responden 403 a quien no es Gold** (más cortesías). Premium no podría ver `heldNews` y Free no podría ni contar. Hay que cambiar el gating del servidor o el alcance (architect). Esto toca A2 y `PlanMatrix`.
- **GDELT:** "unlimited and unrestricted use … commercial" según https://www.gdeltproject.org/about.html, y blogs que copian los términos piden citar el proyecto y linkear (no pude confirmarlo en la página viva). Poner "Titulares vía GDELT Project" en la hoja de novedades y mantenerlo en Ajustes > Fuentes de datos. Los derechos sobre cada titular son de cada medio: mostrar titular corto + fuente + link es práctica habitual, pero no es una licencia (ver "Requiere abogado").
- **Caché de 48 h en el teléfono:** con GDELT/SEC no veo impedimento; con Finnhub, la regla de borrar al terminar la suscripción.
- **Free solo ve el conteo:** el conteo es un dato derivado. Calcularlo en el servidor sin mandar el contenido al cliente (como ya propone A2) es lo correcto; no cambia la licencia.

```
[BLOQUEA] A2 teaser — Aviso "· Premium" / "· Gold" dentro del widget de iOS
Por qué: Apple 4.4 dice que las extensiones "may not include marketing, advertising, or in-app purchases" (https://developer.apple.com/app-store/review/guidelines/); el Apple Developer Program License Agreement 3.3.7(E), según lo que encontré (no pude abrir el PDF), prohíbe "advertising, product promotion, direct marketing, or In-App Purchase offers" en la vista de una extensión. Un widget es una extensión de WidgetKit. 2.5.18 limita la publicidad de display a la app, y 2.5.16 exige que el widget se relacione con la app (cumple). Un aviso que nombra un plan de pago es promoción de producto dentro de la extensión. No encontré un caso resuelto sobre widgets propios que promocionan su suscripción: es zona gris con riesgo real de rechazo en la revisión.
Texto propuesto: en iOS, aviso informativo sin nombre de plan ni llamado a comprar (texto abajo); el toque abre la hoja de novedades en la app, que muestra el estado bloqueado y el paywall ahí adentro. En Android se puede mantener el aviso con "· Premium"/"· Gold" (no encontré una regla de widgets en Google Play; la de anuncios https://support.google.com/googleplay/android-developer/answer/9857753 habla de anuncios inesperados fuera de la app, pensada para anuncios de terceros y no pude abrirla). Dejar `app_config.widget_teasers` por plataforma.
Revisión humana: sí (cómo lo lee App Review no se puede predecir)
```

```
[CORREGIR] A4 + decisión del usuario — "Ocultar montos" no oculta posiciones: hay que decirlo y marcar los datos
Por qué: con el ajuste prendido el widget muestra ticker, titular y fuente, también bloqueado y en StandBy. Eso revela qué tenés (no cuánto). Dos riesgos: (1) el usuario entiende "ocultar" como "privado" y se lleva una sorpresa (Ley 24.240 art. 4 información clara: https://servicios.infoleg.gob.ar/infolegInternet/anexos/0-4999/638/texact.htm; GDPR art. 5(1)(a), transparencia); (2) cualquiera con el teléfono a la vista lee las posiciones. Mitigaciones que no cambian la decisión: `.privacySensitive()` en ticker, titular, fuente y línea de resultados (no solo en montos), con reemplazo neutro cuando el sistema los redacta; probarlo en teléfono real bloqueado y en StandBy (el efecto depende de versión y ajustes: https://developer.apple.com/forums/thread/806236); y el texto aclaratorio de abajo en Ajustes. Android: los widgets de inicio no se ven bloqueados en teléfonos; en tablets con widgets en pantalla bloqueada no lo verifiqué.
Texto propuesto: abajo.
Revisión humana: no
```

```
[CORREGIR] A1 — Titulares de terceros con lenguaje de recomendación
Por qué: un titular "Buy now" o "3 stocks to buy" junto al ticker del usuario, en un widget con la marca Porty y sin espacio para disclaimer, se lee como que Porty lo marca. Mostrar la fuente no alcanza. El orden por peso de posición no es juicio sobre la noticia (no hay sentimiento ni palabras clave), pero el título de sección "Novedades de tu cartera" no debe decir "importante", "destacado" ni "top".
Texto propuesto: filtrar (descartar, no reescribir) titulares con imperativo o recomendación directa al lector. Regla mínima testeable en es/en: `should you (buy|sell)`, `(stocks?|shares?) to (buy|sell)`, `(buy|sell) (now|today|this)`, `time to (buy|sell)`, `must[- ](buy|sell)`, `best .* to (buy|sell)`, `comprá|vendé|aprovechá`. No filtrar "analyst upgrades to Buy" (es informar un hecho). Es una red parcial: la hoja lleva la leyenda de abajo, y el test cubre la lista con ejemplos reales. Si tras filtrar no queda nada: estado "sin novedades".
Revisión humana: no
```

```
[CORREGIR] A5 — "Sin novedades" afirma algo que no sabemos
Por qué: "Sin novedades en las últimas 48 h" es falso si la fuente falló o no cubre ese ticker.
Texto propuesto: abajo.
Revisión humana: no
```

```
[CORREGIR] A8.4 / §5 — Política de privacidad y ajuste: sumar titulares y fechas
Por qué: ahora el almacén del widget guarda tickers de noticias, titulares y fechas de resultados (hasta 48 h / 7 días). Transparencia: Ley 25.326 art. 4, GDPR art. 13, Apple 5.1.1 (https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage). No cambia por sí mismo las etiquetas de Apple ni el Data safety (no sale del teléfono). Los eventos nuevos de A6 no llevan ticker ni titular: mantenerlo así (test). Las consultas a Finnhub/GDELT/SEC las hace el servidor por ticker, sin identificar al usuario: confirmarlo al verificar el código.
Texto propuesto: abajo.
Revisión humana: sí (la frase de la política, antes de publicarla)
```

```
[SUGERENCIA] A2 — Las preguntas fijas
Por qué: `news_why` "¿Qué pasó con {TICKER}?" es neutra, aprobada. `earnings_when` presupone una fecha que ahora es estimada.
Texto propuesto: abajo.
Revisión humana: no
```

### Textos aprobados (es / en)

Todos con test de texto exacto en los dos idiomas. Cualquier variante nueva vuelve a compliance. Ninguno lleva verbos de acción sobre el usuario, adjetivos de valoración, causas ni proyecciones.

**Novedades (A2, A3)**

| Elemento | es | en |
|---|---|---|
| Sección (grande) y hoja | Novedades de tu cartera | Your holdings news |
| Noticia, línea chica | {TICKER} · {fuente} · hace 25 min / hace 3 h / ayer | {TICKER} · {source} · 25m ago / 3h ago / yesterday |
| Noticia, titular | tal cual, en su idioma, hasta 2 líneas | as published, original language, up to 2 lines |
| Resultados, fecha **estimada** (fuente v2) | {TICKER} · fecha estimada de resultados: hoy / mañana / jue 7 nov | {TICKER} · estimated earnings date: today / tomorrow / Thu, Nov 7 |
| Resultados, fecha **confirmada** (solo si la fuente es licenciada y la confirma) | {TICKER} presenta resultados hoy / mañana / el jue 7 nov (+ "antes de la apertura" / "después del cierre" si hay `hour`) | {TICKER} reports earnings today / tomorrow / Thu, Nov 7 (+ "before the open" / "after the close") |
| Leyenda en la hoja | Titulares de terceros, ordenados por el peso de cada posición en tu cartera. Porty no los escribe ni los recomienda. Fechas de resultados estimadas. Titulares vía GDELT Project. | Third-party headlines, ordered by each position's weight in your portfolio. Porty doesn't write or recommend them. Earnings dates are estimates. Headlines via GDELT Project. |
| "Leer en {fuente}" / "Preguntale a Porty" | Leer en {fuente} / Preguntale a Porty | Read on {source} / Ask Porty |
| Pregunta `news_why` | ¿Qué pasó con {TICKER}? | What happened with {TICKER}? |
| Pregunta `earnings_when` (cambia) | ¿Cuándo se espera que {TICKER} presente resultados y qué presentó la última vez? | When is {TICKER} expected to report, and what did it report last time? |
| Lector de pantalla, noticia | Noticia de {TICKER}, {fuente}, hace 3 horas: {titular} | News on {TICKER}, {source}, 3 hours ago: {headline} |

**Avisos de plan (A2)**

| Caso | es | en |
|---|---|---|
| Android, Free con noticias | Hay 2 noticias de tu cartera · Premium / Hay 1 noticia de tu cartera · Premium | 2 news stories on your holdings · Premium / 1 news story on your holdings · Premium |
| Android, Free sin número | Noticias de tu cartera · Premium | News on your holdings · Premium |
| Android, Premium con resultados (fechas estimadas) | Una acción de tu cartera tiene resultados estimados esta semana · Gold / 2 acciones de tu cartera tienen resultados estimados esta semana · Gold | One of your holdings has an estimated earnings date this week · Gold / 2 of your holdings have estimated earnings dates this week · Gold |
| Android, Premium (fecha confirmada) | Una acción de tu cartera presenta resultados esta semana · Gold | One of your holdings reports earnings this week · Gold |
| **iOS** (sin nombre de plan, ver hallazgo) | Hay 2 noticias de tu cartera en Porty / Hay 1 noticia de tu cartera en Porty / Una acción de tu cartera tiene resultados estimados esta semana | 2 news stories on your holdings in Porty / 1 news story on your holdings in Porty / One of your holdings has an estimated earnings date this week |
| Hoja, ítem bloqueado (en la app) | Esto viene con Premium / Esto viene con Gold | This comes with Premium / This comes with Gold |

Sobre los avisos: no hay urgencia, escasez ni promesa; el conteo es verificable; solo uno, del plan siguiente; tope en el mediano; interruptor remoto. Eso alcanza para nuestra parte. Lo que no resuelven es la regla de Apple 4.4 (ver hallazgo). Pasar a v2 no cambia estos textos salvo el cambio "estimados".

**Estados (A5)**

| Estado | es | en |
|---|---|---|
| Sin novedades (grande) | No encontramos novedades de tu cartera en las últimas 48 h | We didn't find news on your holdings in the last 48h |
| Todo venció | Abrí Porty para ver las novedades de tu cartera | Open Porty to see your holdings news |
| Redactado por el sistema (pantalla bloqueada / StandBy) | Desbloqueá tu iPhone para ver las novedades | Unlock your iPhone to see the news |
| Sin sesión, sin cartera, falla de red, plan vencido, solo cripto | Sin cambios: textos de la v1 y de A5. En falla de red se mantienen los ítems vigentes con su propia antigüedad, sin error | Same |

**Ajustes (el nombre del ajuste no cambia: "Ocultar montos en el widget")**
- es: "Oculta solo los montos. Las noticias y los resultados del widget siguen mostrando tus tickers. El widget guarda un resumen de tu cartera en este teléfono. Se borra al cerrar sesión."
- en: "This hides amounts only. News and earnings in the widget still show your tickers. The widget keeps a summary of your portfolio on this phone. It's deleted when you sign out."

**Política de privacidad (reemplaza la frase de §5 de mi revisión v1)**
- es: "Si agregás el widget de Porty, guardamos en tu teléfono un resumen de tu cartera (valor total, variación del día y el activo que más aportó) y, según tu plan, titulares de noticias y fechas estimadas de resultados de tus posiciones principales, para mostrarlos en la pantalla de inicio. No salen de tu teléfono por el widget. Se borran cuando cerrás sesión o borrás tu cuenta. Podés ocultar los montos en Ajustes; los tickers y titulares siguen visibles en el widget."
- en: "If you add the Porty widget, we store on your phone a summary of your portfolio (total value, daily change and the top contributor) and, depending on your plan, news headlines and estimated earnings dates for your main positions, to show them on your home screen. They do not leave your phone through the widget. They are deleted when you sign out or delete your account. You can hide amounts in Settings; tickers and headlines remain visible in the widget."

**Galería (widget grande)**
- es: "Porty" / "Mirá cómo viene tu cartera y las novedades de tus acciones, sin abrir la app."
- en: "Porty" / "See how your portfolio is doing and news on your holdings, without opening the app."

**Ficha y capturas (A8.5):** tickers y empresas inventados (no reales), titulares inventados y neutros, fuente "Fuente Ejemplo", sin nombres ni logos de medios reales (marcas ajenas), sin porcentajes llamativos, sin "tiempo real" ni "no te pierdas nada". Mostrar el aviso de plan en la captura solo si finalmente se publica en esa plataforma. Apple 2.3: lo que se muestra tiene que existir tal cual. Pasar el texto por compliance antes de publicar.

### Respuestas a A8

1. **Derechos:** no con Finnhub free (H1); con el camino v2 sin impedimento de licencia visible para GDELT/SEC, pero el derecho sobre cada titular es del medio. Atribución: a la fuente en cada ítem y a GDELT en la hoja. Free solo con conteo: no cambia la licencia.
2. **Asesoramiento:** filtro de imperativos + leyenda "de terceros" + título sin "importante". El orden por peso no es asesoramiento: es un criterio objetivo de los datos del usuario, y la leyenda lo dice. Los textos de resultados, con fecha estimada y sin "sorpresa" ni estimaciones de ganancias, están bien.
3. **Aviso de pago:** Apple, riesgo alto (4.4 y DPLA 3.3.7(E)); Google Play, riesgo bajo-medio, sin regla específica que encontré y sin poder abrir las políticas actuales. Las limitaciones de A2 son buenas, no suficientes para Apple. Contar noticias para un Free no es un problema de licencia si el contenido no sale del servidor.
4. **Privacidad:** textos arriba.
5. **Ficha:** condiciones arriba.

### Requiere abogado

- **Sí:** (a) licencia o permiso para mostrar titulares de terceros (GDELT/medios, o Finnhub comercial) dentro de un widget y cachearlos; (b) si el aviso de plan en iOS es admisible según DPLA 3.3.7(E); (c) lo que ya venía (entidad legal que publica en Apple, 3.2.1(viii) y 5.1.1(ix)).
- **No pude verificar:** la política de privacidad actual, el DPLA completo, las políticas de Google Play (no abrieron) ni los términos de GDELT en su página viva.

### Qué decide el usuario

1. Fuente de datos: ¿v2 (GDELT + SEC, fechas estimadas, hoy solo Gold en el servidor) o Finnhub comercial con permiso escrito? Sin esto no sale.
2. Aviso de pago en iOS: aviso informativo sin nombre de plan, o nada en v1. Android puede llevar "· Premium".
3. Aceptar el riesgo residual de mostrar tickers y titulares en StandBy aun con montos ocultos, con `.privacySensitive()` y el texto de Ajustes (ya decidido; solo confirmar las condiciones).

### Criterios de aceptación ajustados

- 26 (reemplaza): Con "Ocultar montos" prendido, no hay ningún monto en el almacén ni en pantalla; tickers, titulares y fuentes sí se ven. Ticker, titular, fuente y línea de resultados están marcados `.privacySensitive()` y con el sistema redactando se ve el texto "Desbloqueá tu iPhone…". El lector de pantalla no lee montos.
- Nuevo: ningún titular con lenguaje de recomendación llega al widget (test con lista).
- Nuevo: ningún evento de A6 lleva ticker ni titular.
- Nuevo: ninguna fecha de resultados estimada se muestra como confirmada.

### Decisiones del usuario tras compliance de la ampliación (2026-11-05)

- **Fuente:** v2 (GDELT + SEC), no Finnhub. Fechas de resultados estimadas y sin horario.
- **Aviso en iOS:** neutro ("Hay novedades de tu cartera"), sin plan ni pago; abre la app. Android mantiene "· Premium/Gold" y abre el paywall.
- **Privacidad:** sí a las tres: `.privacySensitive()` en ticker/titular/fuente en iOS, texto aclaratorio en Ajustes y frase de privacidad actualizada.
