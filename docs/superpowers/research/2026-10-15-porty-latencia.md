# Porty: cómo bajar el tiempo de respuesta sin perder calidad

**Fecha:** 2026-10-15 · **Estado:** D y C1 implementados (ver §5); el resto, propuesto

Hoy una consulta tarda 10-15 s, y más de 20 s cuando busca noticias. Este documento muestra en qué se va ese tiempo y qué se puede cambiar, ordenado por impacto. Ningún cambio toca qué datos ve el modelo ni qué responde. Lo que cambia es cuánto texto escribe, cuántas cosas se esperan una detrás de otra y cuándo ve el usuario la respuesta.

> Los números de cada tramo son **estimaciones** hechas leyendo el código y con datos públicos de Luna. Hoy no hay medición por tramo (ver §4). Lo primero es medir.

---

## 1. Dónde se va el tiempo en un turno

Un turno típico tiene 2 rondas con el modelo: una para pedir tools y otra que escribe la respuesta A2UI.

| Tramo | Qué pasa | Estimado | Dónde está |
|---|---|---|---|
| Antes de llamar al modelo | `subscription.refresh()`, posiciones cerradas, perfil, memorias y metas, **uno detrás del otro** | 0,5-1,5 s | `AssistantProvider.submitMessage` |
| Proxy, por ronda | `auth.getUser(jwt)` (un viaje al servidor de Auth), hash del prompt, RPC `ai_begin_request`. Al final **espera** `ai_record_round` antes de devolver la respuesta | 0,3-0,8 s × 2-3 rondas | `ai-chat/handler.ts` |
| Ronda 1 | TTFT de Luna (~0,8 s sin razonamiento) + ~50-100 tokens de tool calls | ~1,5 s | — |
| Tools | Yahoo/Finnhub/SEC: 0,5-3 s. **`get_news` v2: 5-11 s** (búsqueda web con gpt-5-mini), con tope de 22 s | 1-11 s | `GetNewsTool`, `news-context` |
| Ronda final | TTFT + **toda** la respuesta A2UI (600-1.300 tokens a ~125 tok/s en `fast`) | **5-11 s** | — |
| Render | Nada se ve hasta que llega el último token (sin streaming) | — | `OpenAIGenUiService` |

**Conclusión:** lo que más pesa es **escribir la respuesta final** (~50-60 % del turno), y en preguntas de noticias, **la búsqueda web**. Las esperas en serie del proxy y de la app suman 1-3 s más, y bajarlas no cuesta nada.

---

## 2. Cambios, de mayor a menor impacto

### A. Escribir menos tokens en la respuesta final (−30 a −50 % de la ronda final)

La guía de latencia de OpenAI lo pone primero: la latencia escala casi lineal con los tokens de salida, y *"cortar 50 % de los tokens de salida puede cortar ~50 % de la latencia"*. En Porty, buena parte de la salida no es contenido: es envoltorio A2UI y números que el modelo **copia** de las tools.

1. **Que los widgets tomen los números de la evidencia, no del modelo.** Hoy el modelo copia en `QaPriceChart` `currentPrice`, `dayChangePct`, `weekChangePct`, `monthChangePct`, `priceStart`, `priceEnd`… y lo mismo en `QaPeriodChange`, fundamentals y earnings. Esos datos ya están en los resultados de las tools del turno, y la app ya los tiene (`evidenceListenable(surfaceId)`). El modelo escribiría solo `{"component":"QaPriceChart","ticker":"AAPL","initialRange":"1W"}` y el widget llenaría el resto desde la evidencia. **Mejora la calidad**: no hay números mal copiados y `AssistantGroundingCheck` tiene menos que vigilar. Se puede hacer widget por widget, empezando por los de más campos.
2. **No pedir `createSurface`.** `A2uiResponseNormalizer` ya lo agrega si falta, y cada respuesta lo trae con el `catalogId` (una URL larga): ~40-60 tokens por turno, unos 0,4 s. Verificar en el prompt de genui que no se lo pida al modelo.
3. **Ids y estructura mínimos.** Ids de 1-2 caracteres, sin `Column` raíz cuando hay un solo hijo (que lo arme el normalizer).

Cómo validar que no se pierde calidad: correr los evals (`RUN_ASSISTANT_EVALS=1`) antes y después, comparando tokens de salida por turno (`ai_turn_usage.completion_tokens`) y la tasa de rechazos de `AssistantGroundingCheck`.

### B. Streaming con render progresivo (el usuario ve algo a ~1-2 s de la ronda final, no a los 6-10 s)

El proxy **ya** soporta `stream: true` (pass-through SSE con registro de uso). La app no lo usa: *"la respuesta A2UI solo sirve completa"*. A2UI se diseñó para streaming: es una lista plana de componentes con ids, pensada para renderizar a medida que llega ([spec v0.8/v0.9](https://a2ui.org/specification/v0.8-a2ui/)).

- Pedir la ronda final con `stream: true` y parsear `components` **de a un objeto completo**: cuando cierra el `}` de un componente, se despacha.
- `QaAnswerText` puede mostrar el texto a medida que llega (el resto de los widgets aparecen enteros).
- Que el prompt pida poner primero el texto principal (en general ya pasa).
- El sanitizer y los checks (grounding, layout) siguen corriendo sobre la respuesta completa. Si la rechazan, se reemplaza la surface, igual que hoy con la reparación.

No baja el tiempo total, pero sí el **percibido**, que es lo que el usuario siente. Es el cambio con más efecto en la sensación de "fluido". Combinado con A, la respuesta completa también llega antes.

### C. Noticias: de 5-11 s a ~0 s en la mayoría de los casos

1. **Caché y búsqueda por ticker.** Hoy la caché de `news-context` es por combinación (`MSFT,GOOGL,VOO|pregunta`): "¿por qué se movió mi cartera?" casi nunca pega en caché. Propuesta: sin `question`, una búsqueda **por ticker, en paralelo** (la latencia es la de la más lenta, no la suma), con caché por ticker. "Noticias de MSFT", la cartera de un usuario y la de otro reusan la misma entrada. Además mejora la calidad: cada empresa se busca por separado.
2. **Precalentar.** Un job (`daily-jobs`, cada 30-45 min en horario de mercado) que refresque el contexto de los tickers que tienen en cartera los usuarios Gold. La consulta del usuario sale de caché. Costo acotado: una búsqueda por ticker distinto, no por usuario.
3. **Modelo de la búsqueda.** `news-context` usa gpt-5-mini con `reasoning: low`. Probar `gpt-6-luna` con `reasoning: low` (TTFT medido por terceros ~2,5 s) solo si los evals de noticias dan igual o mejor. No cambiar a ciegas.
4. **GDELT (titulares).** Tiene un limitador global de 1 pedido cada 5,5 s: con usuarios simultáneos, la cola hace que los titulares lleguen tarde o fallen (fue parte del bug de "no aparecieron titulares"). El precalentado del punto 2 lo cubre también.

### D. Sacar esperas en serie (−1 a −3 s por turno, sin tocar al modelo)

**App (`AssistantProvider.submitMessage`):**
- `subscription.refresh()`, `_fetchClosedPositions()`, `_profileForTurn()`, `_memoriesForTurn()` y `_goalsForTurn()` van uno detrás de otro. Pasarlos a `Future.wait` (son independientes) o, mejor, tenerlos cargados de antes: al abrir el chat, o reusando lo que ya cargó Inicio.
- El plan (`tier`) recién importa cuando corre una tool (la lista de tools es fija), y el proxy ya aplica la cuota. El refresh puede correr en paralelo con la ronda 1.

**Proxy (`ai-chat`), en cada ronda:**
- **`ai_record_round` en background.** En el camino sin streaming se hace `await recordRound(...)` **antes** de devolver la respuesta. Pasarlo a `deps.background(...)`, como ya se hace en el camino con streaming.
- **JWT verificado localmente.** `auth.getUser(jwt)` va al servidor de Auth en cada ronda. Con claves asimétricas de firma (JWT Signing Keys), `auth.getClaims(jwt)` verifica localmente con la clave pública cacheada ([Supabase](https://supabase.com/blog/jwt-signing-keys), [changelog](https://supabase.com/changelog/29289-supabase-auth-asymmetric-keys-support-in-2025)). Ojo: con la clave simétrica legacy `getClaims` sigue yendo al servidor.
- **En paralelo:** el hash del prompt y `ai_begin_request` no dependen uno del otro.
- **Región fija.** Por default la función corre en la región más cercana al usuario (Argentina → sa-east-1). Si la base está en otra región, cada RPC cruza el continente, y OpenAI está en EE.UU. Fijar la región de la base con `x-region` ([Supabase: Regional Invocations](https://supabase.com/docs/guides/functions/regional-invocation)) y medir con `x-sb-edge-region`. Si la base está en us-east-1, ese mismo pin deja la función cerca de OpenAI. Ojo: con región fija no hay failover automático.

### E. Adelantarse (para las preguntas más comunes)

- **Sugerencias iniciales.** Las preguntas de los chips ("¿Por qué se movió mi portfolio en los últimos 7 días?") son conocidas y piden siempre las mismas tools. Al abrir Porty se pueden calentar en background los datos que van a necesitar: cotizaciones de la cartera y contexto de noticias de los que más se movieron. Así, si el usuario toca el chip, la ronda de tools sale de caché.
- **Rondas extra.** Medir cuántos turnos pagan una tercera ronda por `answerCheck` (grounding) o por `needs_retry`. Cada una es una ronda completa más (~6-10 s). Si es frecuente, corregirlo en el prompt o en la descripción de la tool, que es más barato que la ronda.

### Lo que ya está bien (no tocar)

- `reasoning_effort: none` y `service_tier: fast` en Luna (~125 tok/s contra ~60).
- El punto de caché explícito en el system prompt (0 % → 99 % cacheado): el prompt de ~13K tokens casi no suma tiempo de entrada.
- Tools en paralelo dentro de una ronda; titulares y contexto en paralelo dentro de `get_news`.

### Descartado

- **Un modelo más chico para decidir las tools.** Luna sin razonamiento ya tiene un TTFT bajo (~0,8 s), y la ronda 1 es corta. Un router agrega una llamada y un punto de error para ganar poco.
- **Subir el razonamiento o cambiar a un modelo más grande.** Más lento: Luna `low` tarda ~2,5 s en el primer token y `high`, ~15-20 s.

---

## 3. Orden sugerido

| # | Cambio | Ganancia estimada | Riesgo de calidad | Esfuerzo |
|---|---|---|---|---|
| 1 | Medición por tramo (§4) | — (permite todo lo demás) | ninguno | bajo |
| 2 | D: esperas en serie (app y proxy), región fija, `getClaims` | 1-3 s por turno | ninguno | bajo |
| 3 | C1 + C2: noticias por ticker + precalentado | 5-11 s en preguntas de noticias | ninguno o mejora | medio |
| 4 | A2: sin `createSurface` del modelo | ~0,4 s | ninguno | bajo |
| 5 | B: streaming + render progresivo | percibido: −5 a −8 s | ninguno (los checks siguen) | medio-alto |
| 6 | A1: widgets que leen la evidencia | 2-4 s en respuestas con widgets de datos | mejora (menos números copiados) | medio, gradual |
| 7 | E: prefetch de los chips y menos rondas extra | variable | ninguno | medio |

Con 2, 3, 4 y 5, una consulta común debería mostrar la respuesta empezando a ~3-4 s y terminarla a ~6-8 s. Una de noticias, sin los 5-11 s extra cuando pega en caché.

---

## 4. Qué medir primero

Hoy `ai_turn_usage` tiene tokens y rondas, pero no tiempos. Hace falta agregar:

- **Proxy, por ronda:** ms de auth, de `ai_begin_request`, hasta el primer byte de OpenAI y hasta el final, y región (`SB_REGION`).
- **App, por turno:** ms antes del primer request, por ronda, por tool (nombre y si pegó en caché) y hasta el render.
- **Por turno:** tokens de salida de la ronda final y si hubo ronda extra (grounding o `needs_retry`).

Con eso se ve el p50/p90 de cada tramo y se confirma (o corrige) la tabla del §1 antes de invertir en B o en A1.

---

## 5. Implementado (2026-10-15)

- **D, app:** `submitMessage` pide a la vez la suscripción, las posiciones cerradas, el perfil, las memorias, las metas y la fuente de noticias.
- **D, proxy:** `ai_record_round` corre después de responder (`deps.background`), también sin streaming. El hash del prompt **no** se paralelizó: es ~1 ms de CPU, y hacerlo en paralelo con `ai_begin_request` crearía filas de turno para prompts rechazados.
- **D, auth:** `authenticate` usa `auth.getClaims(jwt)` (exige `sub` y `role = authenticated`). Para que no consulte al servidor de Auth hay que **activar las JWT Signing Keys asimétricas** en el proyecto (Dashboard → Project Settings → JWT Keys). Con la clave legacy se comporta como antes. Diferencia con `getUser`: un usuario borrado o bloqueado sigue pasando hasta que vence su JWT (1 h por default).
- **D, región:** variable opcional `SUPABASE_FUNCTIONS_REGION` en `assets/env/.env.*` (p. ej. `us-east-1`, la región de la base). Con ella, `ai-chat` y las funciones de datos (`PortyEdgeClient`) mandan `x-region`. Sin ella, todo sigue igual. Confirmar la región de la base en el Dashboard antes de setearla.
- **D, varios:** `goldAllowed` hace las RPC por ticker en paralelo; `get_news` busca los nombres de las empresas en paralelo.
- **C1:** `news-context` sin pregunta busca **cada empresa por separado, en paralelo**, con caché por empresa (`partsOf` / `mergeParts`). Si una falla, las otras responden igual. Con tope de turno o diario, se sirve lo que haya en caché. Ojo, costo: una consulta de cartera con 5 empresas sin caché son 5 búsquedas en vez de 1 (~US$ 0,05 en vez de ~0,01). La caché compartida lo compensa a medida que se repiten empresas.

**Pendiente:** C2, el precalentado. Es una decisión de costo: con N tickers distintos en las carteras Gold, cuesta ~N × US$ 0,012 por corrida. Conviene activarlo detrás de un flag en `app_config` y con un tope de tickers (los más tenidos).

## 6. Implementado (2026-10-15, segunda parte)

- **Despertar el proxy (gratis):** al abrir Porty, la app manda a `ai-chat` un pedido con `x-porty-purpose: warmup`. El proxy valida la sesión y responde 204, sin OpenAI ni base. Arranca la función, carga la clave pública de los JWT y deja abierta la conexión TLS para la primera pregunta.
- **Streaming detrás de un interruptor (`app_config.porty_streaming`, apagado):**
  - Con el interruptor prendido, cada ronda se pide con `stream: true` (`ChatCompletionStream`). El turno, las tools y lo que recibe genui no cambian.
  - Mientras llega la respuesta, la fila de Porty muestra **solo el texto** (`QaAnswerText`), con el mismo estilo. Las cards con datos aparecen con la respuesta completa, después de los controles de siempre (sanitizer, grounding, layout): nunca queda en pantalla un número que después se corrige.
  - El texto que ya se leyó no se vuelve a tipear al final (`QaStreamedTextScope`). Si el control lo reescribió, se tipea el nuevo.
  - Activación: `{"percent": 0-100, "users": [uuid...]}`. Con `users` lo probás con tu cuenta antes de abrirlo a un porcentaje; el reparto por usuario es el mismo que el de `GPT6_ROLLOUT_PERCENT`. La app relee el valor cada 10 min, y con `percent: 0` y `users: []` todo vuelve a ser como antes.
  - Costo: el mismo (mismos tokens).

## Fuentes

- [OpenAI: Latency optimization](https://developers.openai.com/api/docs/guides/latency-optimization): los 7 principios, y "generar menos tokens" como el principal.
- [Artificial Analysis: GPT-6 Luna](https://artificialanalysis.ai/models/gpt-6-luna) y [por proveedor (low)](https://artificialanalysis.ai/models/gpt-6-luna-low/providers): TTFT por esfuerzo de razonamiento y velocidad de salida (datos de terceros).
- [Supabase: Regional Invocations](https://supabase.com/docs/guides/functions/regional-invocation) y [changelog](https://supabase.com/changelog/36850-update-to-edge-functions-regional-invocations).
- [Supabase: JWT Signing Keys / getClaims](https://supabase.com/blog/jwt-signing-keys).
- [A2UI spec](https://a2ui.org/specification/v0.8-a2ui/): protocolo pensado para render progresivo.
