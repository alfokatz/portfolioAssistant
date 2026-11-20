# Personalización de Porty: memoria, metas de compra, dictado y accesorios

**Fecha:** 2026-10-11 · **Estado:** implementado en la rama (sin deploy) · **Origen:** feedback de una usuaria probando la app

## El feedback

1. **Micrófono en el chat**: un botón al lado de enviar para dictar el mensaje (se transcribe solo en el campo).
2. **Accesorios para Porty**: gorros, moños y accesorios para personalizarlo.
3. **Personalización real (lo más importante)**: la usuaria pidió "¿cuánto tengo que invertir para comprarme una compu?" y Porty:
   - lo leyó como "invertir en empresas de tecnología";
   - ante "una mac" mostró la card de la acción AAPL;
   - ante "la neo rosada" perdió el hilo ("No soy un asistente de belleza");
   - al final inventó un precio (1500 USD), asumió que toda la cartera era para la compu ("tu capital actual cubre ese monto") y propuso 30% acciones para un plazo de 14 meses.
4. **Texto libre en el perfil del inversor** donde aplique (objetivo, horizonte, experiencia).
5. **Guardar lo que Porty va aprendiendo** del usuario (ej. "quiere comprarse una MacBook Neo rosa") para conocerlo cada vez más.
6. **Acotar a Porty a inversiones / finanzas**: ante "decime una receta de tallarines con tuco" contestó la receta.
7. **Buscar en la web** lo que Porty no sabe (ej. el precio de la MacBook Neo) en vez de inventarlo o preguntarlo siempre.

## Decisiones (tomadas por defecto; revisables)

| Tema | Decisión | Por qué |
|---|---|---|
| Dictado | `speech_to_text` (reconocimiento del sistema, en el dispositivo cuando está disponible) | Gratis, sin cambios de servidor, transcribe en vivo. Whisper vía proxy queda como alternativa si la calidad no alcanza |
| Dictado → envío | El texto queda en el campo; el usuario revisa y toca enviar | Evita mandar una transcripción mal reconocida (y gastar una consulta) |
| Memoria | Tabla `user_memories` en Supabase, una fila por dato | Sobrevive reinstalls, se comparte entre dispositivos, RLS por usuario |
| Quién guarda | El modelo, con la tool `remember_about_user` (escribe directo, como `save_goal`) | Recordar es reversible y de bajo riesgo; pedir confirmación por cada dato cortaría la charla |
| Transparencia | Debajo de la respuesta: "Porty anotó: …" + pantalla **Ajustes → Lo que Porty sabe de vos** para ver, agregar y borrar | El usuario tiene que poder ver y controlar lo que se guarda |
| Qué NO se guarda | Salud, religión, política, orientación, datos de cuentas/contraseñas/documentos, preguntas puntuales | Privacidad; regla en la descripción de la tool |
| Plan | Memoria y accesorios para todos los planes | Es la base de la personalización; se puede gatear después |
| Metas de compra | `goal_type: purchase` en `get_goal_projection`: arranca de 0 si no dijo cuánto tiene, y a menos de 3 años la cartera es de corto plazo (70% liquidez / 30% bonos cortos) | Nunca asumir que la cartera es para la compra; no poner en acciones plata que se necesita en meses |
| Precio del producto | Porty lo pregunta; nunca lo inventa | Regla de grounding existente |
| Accesorios | Dibujados en el mismo `CustomPainter` de Porty (se mueven con él); guardados en el dispositivo | Sin assets nuevos, nítidos a cualquier tamaño, animados |
| Alcance | Regla SCOPE en el prompt: fuera de inversiones/finanzas personales no se contesta ni en parte (una línea + un ejemplo de qué preguntar). La regla de CONTINUIDAD evita rechazar respuestas cortas ("la neo rosada") | Es un asistente de finanzas; contestar cualquier cosa diluye el producto y gasta cuota |
| Búsqueda web | Tool `search_web` → edge function `web-search` (OpenAI `gpt-4o-mini-search-preview`, configurable con `WEB_SEARCH_MODEL`), con fuentes citadas, caché compartida 24 h y tope diario por plan (Free 3, Premium 10, Gold 25 en `plan_limits.web_searches_per_day`) | La key queda en el servidor; el costo por búsqueda está acotado; la propia función rechaza consultas fuera de tema |
| Texto libre del perfil | Columna `notes jsonb` en `investor_profiles` (`{objective, horizon, experience}`) | Una columna flexible; viaja en `user_profile.notes` del brief |

## Cambios

### A. Metas de compra a corto plazo (prompt + tool)
- `assistant_prompt_rules.dart`: sección **PURCHASE GOALS** dentro de `[W:GOAL]`: "comprarme una compu / un auto / un viaje" es una meta de ahorro, **nunca** una idea de inversión en la marca (Apple ≠ AAPL); respuestas cortas ("una mac", "la neo rosada") contestan la pregunta anterior de Porty y siguen la meta; pedir precio y fecha si faltan; nunca inventar precios; nunca asumir que la cartera es para la meta.
- Regla general de **CONTINUIDAD**: una respuesta corta continúa el tema de la conversación.
- `GetGoalProjectionTool`: parámetro `goal_type` (`retirement | purchase | other`). Para `purchase`: `current_savings` por defecto 0 (`starting_capital_source: assumed_zero`) y, con menos de 36 meses, `short_term: true` → asignación de corto plazo.
- `SavingsPlanInputs.shortTerm` + `PlanAssumptions.allocationFor(risk, shortTerm:)`: la card recalcula con el mismo flag.
- Cambia el hash del prompt: **regenerar la allowlist y desplegar `ai-chat` antes de publicar** (ver `docs/runbooks/ai-proxy-cutover.md`).

### A2. Alcance y búsqueda web
- `assistant_prompt_rules.dart`: secciones **SCOPE** y **CONTINUITY**; en metas de compra, si falta el precio → `search_web` una vez, citar la fuente, y si no hay resultado (o se llegó al tope) preguntarlo.
- Migración `20261011060000_web_search.sql`: `web_search_cache`, `web_search_usage`, `plan_limits.web_searches_per_day` y RPC `web_search_hit`.
- `supabase/functions/web-search/` (+ `tests/web_search_test.ts`, `verify_jwt = false` en `config.toml` como el resto).
- App: `WebSearchClient` y `SearchWebTool` (`lib/features/assistant/tools/web_tools.dart`).

### B. Memoria de Porty
- Migración `20261011040000_user_memories.sql`: tabla + RLS + tope de 60 filas por usuario (trigger).
- Dominio: `UserMemory`, `UserMemoryRepository`; infra: `UserMemorySupabaseDataSource`; estado: `userMemoryProvider`.
- Tools: `remember_about_user {fact, category, replaces_id?}` y `forget_about_user {memory_id}`.
- Brief: `user_memory: [{id, fact, category, since}]` (las 30 más recientes) + guía de uso en el contexto fijado (no cambia el hash).
- Chat: footer "Porty anotó: …" tocable → pantalla de memoria.
- Ajustes: fila **Lo que Porty sabe de vos** → lista por categoría, agregar a mano, borrar uno, borrar todo.

### C. Perfil del inversor con texto libre
- Objetivo, horizonte y experiencia muestran "Contale más a Porty (opcional)" debajo de las opciones. Esas preguntas ya no avanzan solas al elegir: se confirma con Siguiente / Guardar.
- `InvestorProfile.notes`, guardado en `notes jsonb` (con fallback si falta la migración). El resumen muestra la nota debajo de la respuesta.

### D. Dictado en el chat
- `AssistantMicButton` al lado de enviar: tocar empieza a escuchar (pulso terracota), los parciales se escriben en el campo, tocar de nuevo (o silencio) termina. Sin permiso o sin reconocimiento disponible → aviso.
- Permisos: `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription` (iOS); `RECORD_AUDIO` + `queries` de `RecognitionService` (Android).

### E. Accesorios de Porty
- `PortyOutfit` (cabeza / cara / cuello) con 12 accesorios: gorro de lana, gorro de fiesta, galera, gorra, corona, moño, flor; anteojos, anteojos de sol; moño corbata.
- `PortyAvatarPainter` los dibuja dentro de la transformación del cuerpo (respiran, se inclinan y saltan con Porty); los de la cara siguen a los ojos.
- Preview: `2026-10-11-porty-accesorios.png` (arriba en reposo, abajo pensando).
- `PortyOutfitScope` en la raíz de la app: todo `PortyAvatar` lo usa sin cambiar los call sites. Solo con la paleta de marca.
- Ajustes → **Personalizá a Porty**: preview grande + grilla por categoría.

## Pendiente / siguiente iteración
- Correr las evals nuevas de metas de compra contra el proxy (necesitan key): `RUN_ASSISTANT_EVALS=1 flutter test test/evals/assistant_tool_evals_test.dart`.
- Deploy: `supabase db push` (migraciones `user_memories`, `investor_profile_notes` y `web_search`) → `supabase functions deploy web-search` (usa el mismo `OPENAI_API_KEY`) → deploy de `ai-chat` con la allowlist nueva → publicar la app.
- Confirmar que el modelo de búsqueda (`gpt-4o-mini-search-preview`) siga disponible en la cuenta de OpenAI; si no, setear `WEB_SEARCH_MODEL`.
- `deno task test` con `supabase start` para los tests nuevos de `web-search` (acá solo se pudo correr `deno check`).
- Probar el dictado en dispositivo real (el simulador de iOS no tiene micrófono confiable).

## Segunda ronda: Metas (2026-10-11)

Feedback de la prueba con la MacBook: (1) "¿Cuánto paga de dividendos cada uno?" respondió sobre toda la cartera en vez de BIL/SHV; (2) faltaba una sección donde queden las metas con su plan y un análisis de si se cumple; (3) "Guardá esta meta" volvía a pedir el monto y Porty inventó una sección "Metas" que no existía; (4) "Armá mi compra mensual" contestó "primero necesito generar el plan" sin hacerlo.

- **Pestaña Metas** (Inicio · Metas · Porty · Ajustes): tarjetas con monto, fecha, barra de progreso y veredicto (Recién empezás / En camino / Adelantada / Atrasada / ¡Lograda! / Venció). Preview: `2026-10-11-metas.png`.
- **Detalle de la meta:** cuánto lleva, el **análisis de Porty** (determinístico, `GoalProgress`: compara lo juntado con lo que el plan esperaba a esta altura y calcula el aporte mensual necesario desde hoy), el plan (ahorro mensual, cartera, compra mensual si la armó), los aportes (registrar / borrar, aporte o retiro), "Preguntarle a Porty", marcar como lograda, borrar.
- **Guardar:** botón **"Guardar en Metas"** en la card del plan y en la de la compra mensual (directo, sin el modelo ni cuota; después dice "Guardada en Metas · Ver"). Porty además pregunta si la quiere guardar; si dice que sí → `save_goal {plan_id}` (ya no pide monto ni fecha).
- **Aportes por chat:** `add_goal_contribution` ("ya puse 200 para la compu").
- **Brief:** `saved_goals` con el progreso ya calculado, para "¿cómo va mi meta?".
- **Prompt:** ACT, DON'T ANNOUNCE; "cada uno" = los instrumentos de la respuesta anterior; WHERE THINGS ARE (nunca inventar secciones). El chip de la compra mensual ahora nombra los tickers ("¿Cuánto paga de dividendos BIL y SHV?").
- **Datos:** migración `20261011070000_user_goals.sql` (`user_goals` + `goal_contributions`, RLS, tope de 20 activas, `plan_key` único para no duplicar).
- **Deploy:** `supabase db push` y volver a desplegar `ai-chat` (hash nuevo del prompt en la allowlist).

### Progreso automático (reemplaza los aportes manuales)

Feedback: cargar aportes a mano no lo va a hacer nadie, y una meta podía decir "Atrasada" aunque el usuario ya tuviera la plata.

- **Lo que cuenta para la meta se suma solo:** `linked_tickers` (inversiones de la cartera asignadas a la meta; su valor de mercado de hoy) + `external_savings` (lo que tiene fuera de la app, un solo monto que actualiza cuando quiere o contándoselo a Porty). Migración `20261011080000_goal_funding.sql` (borra `goal_contributions`, que nunca se publicó).
- **Al guardar** se asignan solas las inversiones de su compra mensual (aunque todavía no las tenga: cuando las compre, se suman) o, para la jubilación, toda la cartera. Cada ticker cuenta para una sola meta (asignarlo a otra lo mueve).
- **Si ya tiene el monto** (en la app o afuera), la meta dice "¡Ya la tenés!", nunca "Atrasada".
- Detalle: sección "Qué cuenta para esta meta" (cada inversión con su valor, ahorros fuera de la app, "Elegir qué cuenta").
- Chat: `update_goal_savings` reemplaza a `add_goal_contribution`; el brief trae `counted_holdings` y `outside_savings`.

### Planes: preguntar primero, arrancar de cero y decir en qué invertir

Feedback: "Quiero armar un plan para una meta" tomó la MacBook de la memoria y usó la cartera entera ($55.374) como punto de partida ("ya alcanzada"); el plan "aparte" no decía en qué invertir y usaba 30% acciones a 12 meses.

- **Preguntar primero:** sin saber qué meta, Porty pregunta qué quiere lograr, cuánto cuesta, para cuándo y si ya tiene algo; lo de la memoria es solo una pista ("¿es para la MacBook que me contaste?").
- **Arranca de cero:** solo la jubilación parte de la cartera; cualquier otra meta, de 0 salvo que diga "usá lo que tengo" (`current_savings`). Lo aplica el código, no depende del modelo.
- **Menos de 3 años = sin acciones** para toda meta que no sea el retiro (antes solo si el modelo pasaba `goal_type: purchase`).
- **Instrumentos en cada plan:** `suggested_instruments` (un ETF amplio por clase de activo: SGOV liquidez; VGSH bonos cortos / BND bonos; VT acciones, SCHD si vive de dividendos) con el monto mensual de cada uno. La card muestra "Dónde invertir cada mes" (preview: `2026-10-11-plan-con-instrumentos.png`) y la meta se guarda con ellos (y los cuenta solos).
- **Sin duplicados:** guardar un plan para una meta con el mismo nombre la actualiza ("Actualizar en Metas").

### La meta se propone y se confirma

Feedback: "un auto de 25 mil en 3 años" se contestó solo con texto (651/mes, 85% acciones): sin la card del plan, sin el desglose de en qué invertir, y la meta recién se guardó después de insistir y decir "sí".

- **La card siempre aparece:** si en el turno se calculó un plan completo y la respuesta no lo muestra, `AssistantAnswerReview.postProcess` agrega `QaSavingsPlan` (o `QaBuyPlan`) después del texto; si el modelo puso un `planId` que no existe, se corrige al del plan del turno.
- **Confirmar para crear:** la card es la propuesta y termina con "Confirmar y crear meta" (o "Confirmar y actualizar meta" si ya hay una con ese nombre); después queda "Meta creada en Metas · Ver". El prompt pide invitar a revisar y confirmar en la card, sin "¿la guardo?" (un "sí" verbal sigue funcionando con `save_goal`). Preview: `2026-10-11-meta-confirmar.png`.
- **3 años es corto plazo:** el corte pasa a `<= 36` meses (antes 36 meses justos caía en la cartera del perfil, con acciones).

### Rediseño del detalle de una meta

Feedback: "El plan de Porty" era texto plano y confuso; "Preguntarle a Porty" con el ícono de chat viejo; sin logos en "Qué cuenta"; el modal "Elegir qué cuenta" se abría hasta arriba y tapaba la manija; Porty siempre con la misma cara.

- **Cómo vas:** monto + porcentaje, barra, tres datos (por mes — o "desde hoy" si vas atrasado —, meses que quedan, cuánto falta) y el análisis de Porty en una burbuja del color del estado. Porty cambia de cara (`goalMood`): sonrisa leve al empezar o al día, sonrisa grande si vas adelantado o ya la tenés, preocupado si vas atrasado o venció.
- **El plan de Porty** (ahora antes de "Qué cuenta"): "Invertí cada mes" grande con la etiqueta del perfil o "Corto plazo", barra de composición con leyenda, nota de corto plazo y "En qué invertir" con logo, nombre, monto por mes y % del aporte (el puntito de color une cada inversión con su parte de la barra).
- **Qué cuenta para esta meta:** logos; las inversiones que tenés llevan chevron y abren el detalle de la acción; ahorros fuera de la app con ícono de editar; "Elegir qué cuenta" como fila dentro de la card.
- **Modal "Elegir qué cuenta":** `useSafeArea` y máximo 75% de la pantalla (la manija siempre se ve); logos en la lista. El de "ahorros fuera de la app" también respeta el área segura.
- **Preguntarle a Porty:** card con el avatar de Porty y un subtítulo, en vez del ícono de chat.
- Texto de borrar actualizado ("Tus inversiones no se tocan"; ya no hay aportes registrados).
- Preview (claro, oscuro y el modal): `2026-10-11-meta-detalle.png`.

### Barra de abajo y borrar metas desde la lista

- **Orden de la barra:** Inicio · Porty · Metas · Ajustes. Porty es lo principal de la app y queda más cerca del pulgar; Metas, que se arman con Porty, va después. (`AppNavDestination` y las ramas del shell en `app_router` cambian juntos.)
- **Borrar desde Metas:** deslizar una meta a la izquierda (con confirmación; si se cancela vuelve a su lugar) o mantenerla apretada (opciones: marcar como lograda / borrar). La lógica se comparte con el detalle (`GoalActions`). El diálogo nombra la meta y al borrar hay un aviso.

### Metas nuevas sin confundirse y plan editable

Feedback: "quiero comprarme una silla herman miller" → "2000usd" salió como "MacBook M5 Pro, 2.000 en 1 año" y con "Confirmar y actualizar meta".

- **Causa:** `get_goal_projection` completaba lo que el modelo no pasaba (nombre, fecha) con la **última meta guardada** (la MacBook, a 1 año). Con solo el monto de la silla, la meta nueva tomaba el nombre y la fecha de la MacBook, y como el nombre coincidía, la card ofrecía actualizarla.
- **Ahora:** una meta nueva nunca toma datos de otra. Lo que falta vuelve en `missing` y Porty lo pregunta (nunca asume "en un año"). Solo se completa desde otra meta si el modelo la nombra: `goal_id` (una de Metas) o `base_plan_id` (un plan de esta charla).
- **Pedirle cambios a Porty:** "hacelo en 2 años", "ponele Silla", "ya tengo 500" → `get_goal_projection {base_plan_id, solo lo que cambia}`: mantiene el resto (nombre, monto, lo que ya tiene, riesgo, tipo) y muestra la card nueva.
- **Editar en la card:** botón "Editar plan" (nombre, monto, fecha con atajos de 1-10 años, lo que ya tiene y riesgo cuando no es corto plazo). Recalcula al toque con el mismo cálculo (`GoalProjectionBuilder.edit`), muestra "Editaste este plan · Volver al de Porty", y lo que se confirma se guarda así. La edición queda en el store de la conversación (`SavingsPlanStore.recordEdit`): si después se le pide un cambio a Porty, la compra mensual o guardarla, se parte de lo editado. Preview: `2026-10-11-plan-editable.png`.

### Detalle de una meta: monto entero, opciones, editar y lo que no cuenta

- **Monto ahorrado:** monto y "de X" se achican juntos si no entran, en vez de cortarse ("2.00…").
- **Opciones (⋯):** en lugar del menú flotante de Material, una hoja con el nombre de la meta y cada opción con ícono en círculo, título y una línea que explica qué hace: Editar plan, Marcar como lograda / Volver a activa y Borrar meta (en rojo, separada). La misma hoja sale al mantener apretada una meta en la lista.
- **Editar plan desde Metas:** botón en la card del plan y opción del menú; abre el mismo editor que el chat (`GoalActions.editPlan`). Si la cartera no cambia, se mantiene la compra mensual con los montos nuevos; si cambia (p. ej. pasa a corto plazo), van los instrumentos del plan nuevo. Lo que el usuario sacó de "Qué cuenta" no vuelve; solo se suman las inversiones nuevas del plan (`GoalsNotifier.updatePlan`). Los atajos de fecha cuentan desde hoy.
- **VOO al 0%:** salía de una compra mensual con una acción en un plan de corto plazo (sin acciones). Ya no se arma ni se guarda una inversión con 0%, y las guardadas así no se muestran. Si el usuario saca de "Qué cuenta" una inversión que el plan sigue sugiriendo, la fila dice "No cuenta para esta meta".
- Preview: `2026-10-11-meta-detalle-editar.png`.
