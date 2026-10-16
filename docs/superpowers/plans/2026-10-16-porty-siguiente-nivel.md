# Porty, siguiente nivel: importador, moneda, plan de cartera, seguimiento, resultados y Binance

**Fecha:** 2026-10-16 · **Estado:** F1–F6 implementadas y probadas en local; nada desplegado · **Rama:** `claude/porty-next-level` · **Base:** `feature/ui_redesign` · **Runbook nuevo:** `docs/runbooks/binance-sync.md`

## Estado de implementación

| Fase | Estado | Notas |
|---|---|---|
| F1 | ✅ | `statement-import` (CSV sin IA, PDF/otros con IA y cupo), pantalla de importación, entradas en la Home vacía y Ajustes. Dependencia nueva `file_picker` |
| F2 | ✅ | Ajustes → Moneda; línea debajo del total y hoja con el desglose. Preferencia en el teléfono |
| F3 | ✅ | Migración `allocation_plans`, pantalla, aviso en la Home, aviso de los lunes en `daily-jobs`. `PlanFeature.allocationPlan` (Premium) |
| F4 | ✅ | Migración `watchlist_items` (+ `plan_limits.watchlist`), pantalla, entrada en la Home, `watchlist_move` en `market-watch` |
| F5 | ✅ | `push_holding_weights`; `earnings_tomorrow` con peso, EPS esperado y horario, y pedido de resumen a Porty |
| F6 | ✅ | Migración y edge function `binance-sync`, pantalla, marca, auto-sync. **Bloqueante antes de lanzar:** confirmar que Binance responde desde la región del proyecto (runbook §0) |

Validación (2026-10-16): `flutter analyze` sin avisos nuevos; `flutter test` 1264 en verde (el único rojo, `test/widget_test.dart`, ya fallaba antes); Deno: tests puros en verde (los de integración necesitan `supabase start`); tests SQL (`supabase/tests/*.sql`, incluidos los 3 nuevos) en verde contra Postgres 16 con los esquemas de Supabase simulados.

### Cambios respecto del plan, decididos al implementar

- **Notificaciones nuevas** (`allocation_drift`, `watchlist_move`): una migración aparte (`20261016000100_push_new_kinds.sql`) suma los tipos al outbox y al tope diario. `allocation_drift` no tiene preferencia propia: se apaga en la pantalla del plan.
- **Lista de seguimiento:** un aviso por usuario y corrida (el mayor movimiento), para que una lista larga no llene el teléfono.
- **Binance:** el trigger de solo lectura de eToro pasa a cubrir todo lo que no es manual. La posición agregada que mezcla manual y Binance es `PositionSource.mixedBinance` (para la marca y los textos).
- **Hoja de opciones de Ajustes:** ahora scrollea (la lista de monedas no entraba).

## Resumen

Seis mejoras para que Porty sea útil todos los días, no solo cuando el usuario carga algo a mano:

| # | Qué | Para quién | Por qué |
|---|---|---|---|
| F1 | **Importar la cartera desde un CSV o PDF** de cualquier bróker | Todos los planes | Cargar posición por posición es donde se abandona. Cubre IBKR, Schwab, Degiro y los brókers locales sin esperar aprobaciones |
| F2 | **Moneda para ver tu cartera** y cuánto de la ganancia viene del tipo de cambio | Todos | El usuario de Uruguay o Argentina invierte en dólares pero piensa en pesos |
| F3 | **Plan de cartera**: asignación objetivo, desvío y cómo repartir el próximo aporte | Premium | Ya sabemos su perfil y sus metas; falta decirle "te alejaste de tu plan" |
| F4 | **Lista de seguimiento** con avisos cuando algo se mueve fuerte | Premium | Hoy solo se siguen las acciones que ya tiene |
| F5 | **Resumen antes de los resultados** de sus acciones | Gold | La notificación de "mañana presenta" ya existe; le falta el contexto |
| F6 | **Binance** de solo lectura | Premium | Segunda conexión automática, sin aprobación del exchange |

Fuera de alcance: IBKR por OAuth (depende del trámite de `docs/superpowers/research/2026-10-16-ibkr-onboarding.md`; mientras tanto su CSV/Flex entra por F1) y que Porty, el asistente, use los datos nuevos (plan de cartera, lista) como herramientas. Queda como siguiente paso.

## Principios (los de siempre, aplicados acá)

- **Sin consejos.** Porty nunca dice "comprá" o "vendé". El plan de cartera (F3) es del usuario: Porty hace la cuenta de cuánto le falta para volver a **su** objetivo. Los textos dicen "para volver a tu plan", nunca "te conviene".
- **Pocas y buenas notificaciones.** Todo lo nuevo pasa por el outbox, el tope diario, el horario de silencio y las preferencias que ya existen (`notify-dispatch`).
- **Solo lectura con los brókers.** Binance igual que eToro: se rechaza cualquier clave con permisos de operar o retirar, las claves viven en Vault y lo importado no se edita desde la app.
- **El servidor manda.** Topes por plan y permisos se controlan en la base (triggers) o en la edge function, y la app los refleja.

---

## F1. Importar desde CSV o PDF

### Experiencia

1. Entrada desde la Home vacía ("Importar desde un archivo") y desde Ajustes → Cuentas conectadas.
2. El usuario elige un archivo (`.csv`, `.txt` o `.pdf`, hasta 2 MB).
3. Porty lo lee y muestra una **vista previa**: una fila por posición con ticker, cantidad, precio de compra y fecha. Cada fila se puede corregir o descartar. Se marcan:
   - las que no tienen precio o cantidad (hay que completarlas);
   - los tickers que no tienen cotización ("No encontramos este ticker");
   - las que ya están en la cartera ("Ya tenés AAPL: se suma como otra compra").
4. "Importar N posiciones" las agrega como **manuales** (se editan y se cierran como cualquier otra).
5. Free respeta su tope de 10 posiciones: si el archivo trae más, se avisa y se ofrece el plan.

### Servidor: edge function `statement-import`

`POST /functions/v1/statement-import` con el JWT del usuario y `{filename, mime_type, content_base64}`.

1. **CSV con columnas reconocibles → sin IA y sin cobrar.** `parse_csv.ts` detecta el separador (`,` `;` tab), la fila de encabezados y las columnas por sinónimos (en inglés y español: `symbol/ticker/símbolo`, `quantity/qty/shares/cantidad`, `price/avg cost/cost basis/precio`, `date/trade date/fecha`). Entiende números con coma o punto decimal y fechas ISO, `dd/mm/yyyy` y `mm/dd/yyyy` (desambigua mirando todas las filas).
2. **Si no alcanza (PDF o CSV raro) → IA**, cobrando una consulta del cupo mensual con el mismo mecanismo que el chat (`ai_begin_request` / `ai_record_round`, turno `import:<uuid>`). Chat Completions con `response_format: json_schema` y el archivo como `file` (PDF) o texto (CSV). El modelo sale de `STATEMENT_IMPORT_MODEL` (por defecto `gpt-6-luna`).
3. Devuelve `{source: "csv" | "ai", rows: [{ticker, name, quantity, purchase_price, purchase_date, currency}], warnings: [...]}`. **No guarda nada**: la app agrega las posiciones después de que el usuario confirma.
4. Errores tipados: `file_too_large`, `unsupported_type`, `nothing_found`, `quota_exceeded`, `unavailable`.

El archivo no se guarda en ningún lado ni se loguea su contenido.

### App

`lib/features/statement_import/`: cliente de la edge function, `ImportDraftRow` (fila editable con su validación), provider con los estados (elegir → leyendo → vista previa → importando → listo) y dos pantallas (vista previa y resultado). Dependencia nueva: `file_picker`.

---

## F2. Moneda para ver tu cartera

### Experiencia

- Ajustes → Preferencias → **Moneda**: Dólar (por defecto), Peso uruguayo, Peso argentino, Real, Peso mexicano, Peso chileno, Peso colombiano, Sol, Euro, Libra.
- Con una moneda que no es dólar, la Home suma una línea debajo del total: "≈ $U 1.234.567". Al tocarla se abre **"Tu cartera en pesos uruguayos"** con:
  - valor y costo en esa moneda;
  - la ganancia en esa moneda, separada en **por las inversiones** y **por el tipo de cambio**;
  - el tipo de cambio de hoy y una nota de la fuente (para Argentina, el oficial).
- Todo lo demás sigue en dólares: así no cambia ningún número que el usuario ya conoce.

### Cálculo (puro, `FxBreakdown`)

Para cada compra: costo `c` (USD), fecha `d`, valor de hoy `v` (USD); tipo de cambio a la fecha de compra `fx_d` y de hoy `fx_0` (unidades de la moneda por dólar, de Yahoo `UYU=X`, `EUR=X`…).

- Costo en la moneda: `Σ c·fx_d` · Valor: `Σ v·fx_0` · Ganancia: la diferencia.
- Por las inversiones: `Σ (v − c)·fx_0` · Por el tipo de cambio: `Σ c·(fx_0 − fx_d)`. Las dos suman la ganancia total (se testea).

Hoy Porty supone que todo cotiza en dólares (la Home ya lo hace); se mantiene esa suposición y se documenta.

### App

`lib/features/display_currency/`: la preferencia (SharedPreferences, como el tema), el repositorio de tipos de cambio (cotización e histórico por el `QuoteRepository` que ya existe), el cálculo y la hoja.

---

## F3. Plan de cartera (Premium)

### Experiencia

- Entrada: Ajustes → Perfil → **Mi plan de cartera**, y una línea en la Home cuando hay desvío.
- La pantalla lista lo que tiene con su **peso actual** y su **objetivo**. Se puede:
  - empezar con los pesos de hoy y ajustarlos;
  - sumar un ticker que todavía no tiene;
  - ver el desvío de cada uno (barra y "+4,2 pts").
- **Próximo aporte:** "Si sumás $500, para acercarte a tu plan va así: $300 a VOO, $200 a BND". Solo compras: nunca propone vender.
- Aviso semanal (lunes 10:00 local) si algo se desvía más que el umbral (5 puntos por defecto, editable): "Tu cartera se alejó de tu plan. VOO pesa 62% (tu objetivo: 50%)". Se puede apagar en la misma pantalla.

### Cálculo (puro, `AllocationMath`)

- Peso actual = valor del ticker / valor total. Desvío = actual − objetivo.
- Aporte `C` con valores `v_i`, total `T` y objetivos `t_i`: falta `n_i = max(0, t_i·(T+C) − v_i)`; se reparte `C·n_i / Σn`. Como `Σ(t_i·(T+C) − v_i) = C`, siempre `Σn ≥ C` y el reparto es exacto.

### Datos

Migración `allocation_plans` (una fila por usuario: `targets jsonb {símbolo: %}`, `drift_threshold`, `notify`). Un trigger valida que los objetivos sumen 100 (±0,5) y que solo Premium o Gold guarden (`allocation_plan_requires_premium`).

`daily-jobs` suma la hora 10 de los lunes: lee los planes con `allocation_drift_inputs` (cantidades y precios de `market_quotes`, con el de compra de respaldo) y encola `allocation_drift`. Clave de duplicados semanal.

---

## F4. Lista de seguimiento (Premium)

### Experiencia

- En la Home, debajo de las posiciones: **"Lista de seguimiento"** con cuántas sigue. La pantalla muestra cada ticker con precio, variación del día y **desde que lo agregó**.
- Agregar con el buscador de símbolos que ya existe. Por cada uno se puede crear una alerta de precio (la hoja de siempre), preguntarle a Porty o quitarlo.
- Aviso cuando un ticker de la lista se mueve fuerte en el día, con los umbrales de sensibilidad de los movimientos fuertes: "AMZN, de tu lista, baja 6,1% hoy. Desde que la agregaste: −12,0%". Lleva a Porty con "¿Qué está pasando con AMZN?".
- Topes: Free 0 (paywall: precios de lo que no tiene son de Premium), Premium 30, Gold 100 (`plan_limits.watchlist`, trigger `watchlist_limit_reached`).

### Servidor

- Migración `watchlist_items` (símbolo, precio al agregar, `notify`), con RLS y el trigger del tope.
- `market-watch` suma los símbolos de las listas de quien tiene dispositivo y avisos de movimientos prendidos (`watchlist_watch_items`) y encola `watchlist_move` con `push_enqueue` (clave `watchlist_move:SYM:fecha:dirección`; uno por día y dirección). Un ticker que además tiene en cartera no avisa dos veces: lo cubre el de la cartera.
- Preferencia: la misma de movimientos fuertes (`big_moves`). Tipo nuevo en `notification_outbox`, `kinds.ts` y `templates.ts`.

---

## F5. Resumen antes de los resultados (Gold)

Ya existe `earnings_tomorrow` (19:00 local, Gold, calendario de Finnhub). Se mejora:

- El aviso dice **cuánto pesa** cada acción en la cartera, **qué ganancia por acción se espera** y **cuándo** (antes de la apertura / después del cierre). Ej.: "NVDA presenta resultados mañana, después del cierre. Pesa 18% en tu cartera; se espera una ganancia por acción de $0.85."
- Al tocarla, Porty arranca con un pedido de resumen completo: "Armame un resumen antes de los resultados de NVDA: qué se espera, qué conviene mirar y cuánto pesa en mi cartera."
- Pesos: RPC `push_holding_weights` (precio de `market_quotes`, de compra si no hay).

Con `news_provider = v2` (SEC) sigue sin avisar: no hay calendario confirmado.

---

## F6. Binance, solo lectura (Premium)

### Experiencia

- Ajustes → Cuentas conectadas → **Binance**. La pantalla explica cómo crear una clave de API **solo de lectura** (paso a paso) y pide la clave y el secreto.
- Al conectar, Porty **verifica los permisos** de la clave y la rechaza si puede operar, retirar o transferir ("Esta clave puede operar. Creá una solo de lectura").
- Importa los saldos como posiciones `binance` (de solo lectura, con la marca de Binance), se actualiza al abrir la app y se puede desconectar conservando lo importado como manual o borrándolo, igual que eToro.

### Servidor: edge function `binance-sync`

- `POST /connect {api_key, api_secret}` → `GET /sapi/v1/account/apiRestrictions` firmado (HMAC-SHA256). Solo acepta `enableReading` y **ninguno** de: `enableWithdrawals`, `enableInternalTransfer`, `permitsUniversalTransfer`, `enableSpotAndMarginTrading`, `enableMargin`, `enableFutures`, `enableVanillaOptions`, `enablePortfolioMarginTrading`. Guarda las claves en Vault y sincroniza.
- `POST /sync` → `GET /api/v3/account` (saldos libres + bloqueados). Cada activo es un ticker de Yahoo `BTC-USD`; los de Simple Earn (`LDBTC`) suman a `BTC`. Las stablecoins (USDT, USDC, FDUSD…) y lo que vale menos de USD 1 no se importan (se informan en el resultado).
- **Precio de compra:** promedio de las compras en `{ACTIVO}USDT` (`/api/v3/myTrades`) para la cantidad que tiene hoy. Si no hay historial (lo compró en otro par o lo transfirió), el precio de hoy, marcado como estimado en el resultado.
- `POST /disconnect {keep_as_manual}` → borra las claves y convierte o borra las filas.
- Migración: `positions.source` acepta `binance`; el trigger de solo lectura pasa a cubrir todo lo que no es `manual`; tablas `binance_connections` y `binance_keys` (puntero a Vault), y RPCs `binance_apply_sync` / `binance_disconnect` como las de eToro.
- **Riesgo:** Binance bloquea pedidos desde algunas regiones (HTTP 451, entre ellas EE.UU.). Hay que confirmar la región de las edge functions antes de lanzar (runbook).

---

## Fases

| Fase | Contenido |
|---|---|
| F1 | `statement-import` + tests; pantalla de importación; entradas |
| F2 | Preferencia de moneda, tipos de cambio, `FxBreakdown` + tests, línea en la Home y hoja |
| F3 | Migración, `AllocationMath` + tests, pantalla, aviso semanal en `daily-jobs` + tests |
| F4 | Migración, pantalla, `market-watch` + tests, tipo de notificación |
| F5 | `daily-jobs` y plantilla + tests |
| F6 | Migración, `binance-sync` + tests (con `fetch` falso), pantalla, marca, auto-sync |

Cada fase deja `flutter analyze` sin errores nuevos, `flutter test` y los tests puros de Deno en verde. Los tests de Deno que usan Postgres real necesitan `supabase start` (no disponible en este entorno): los SQL nuevos se prueban contra un Postgres local con los esquemas de Supabase simulados.

## Despliegue (pendiente, fuera del repo)

1. `supabase db push` (migraciones nuevas).
2. `supabase functions deploy statement-import binance-sync daily-jobs market-watch notify-dispatch`.
3. Secrets: ninguno nuevo obligatorio (`STATEMENT_IMPORT_MODEL` es opcional).
4. Confirmar que Binance responde desde la región del proyecto (ver F6).
5. Publicar la app (dependencia nueva `file_picker`: revisar permisos de iOS/Android).
