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
- `PortyOutfit` (cabeza / cara / cuello) con 10 accesorios: gorro de lana, gorro de fiesta, galera, gorra, corona, moño, flor; anteojos, anteojos de sol; moño corbata.
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
