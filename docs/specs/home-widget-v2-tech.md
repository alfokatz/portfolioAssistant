# Spec técnica: widget de la pantalla de inicio v2 (rediseño)

**Fecha:** 2026-11-06 · **Autor:** porty-architect · **Rama:** `feature/ui_redesign`
**Implementa:** las 6 decisiones cerradas del usuario (2026-11-06) y las maquetas aprobadas (chico/mediano/grande, claro/oscuro, paleta actual del widget, Plus Jakarta Sans, cara contenta/preocupada). No reabre decisiones de producto.
**Base:** `docs/specs/home-widget-tech.md` (v1 + ampliación). Todo lo de v1 sigue vigente salvo donde esta spec dice otra cosa: visor tonto, refresco de fondo sin sesión, esquema `porty-widget`, fuente v2 de noticias (GDELT + SEC), avisos de plan, render log.

---

## 1. Objetivo

El widget deja de ser un "valor de cartera" y pasa a ser **lo que Porty te marca hoy**: el % del día con la cara de Porty, una línea o una lista de novedades ordenadas por prioridad (resultados, noticias, avisos de la Home, lo que más se movió) y preguntas armadas con datos del usuario que abren el chat con la pregunta ya enviada. En el mediano, un botón pasa a la siguiente novedad sin abrir la app.

**Listo** = los criterios del §8 en verde: tests Dart del selector, del orden con histéresis y de las preguntas; test Kotlin del selector nativo contra los mismos casos; capturas de los fixtures en los tres tamaños, claro y oscuro, en iOS y Android; ningún monto en ningún snapshot; con "Ocultar posiciones", ningún ticker, titular, fuente ni nombre de meta en el almacenamiento compartido.

Decisión central (igual que v1): **Dart arma todo** (orden, prioridad, histéresis, textos ya resueltos en el idioma, preguntas, gráfico ya normalizado). El nativo solo: filtra por hora (`expires_at`, segmentos), reordena de forma estable por la prioridad del segmento vigente, elige qué fila va en cada tamaño con reglas fijas (§3.5) y avanza un índice cuando se toca "siguiente".

## 2. Fuera de alcance

- Montos en $ en cualquier tamaño, estado o accesibilidad (decisión 1). Tampoco el valor total.
- Configurar qué muestra el widget (sin intent de configuración ni `AppIntentConfiguration`).
- Botón "siguiente" en el chico y en el grande, y en iOS < 17 (decisión 5).
- Pantalla bloqueada, StandBy, Live Activities, Watch.
- IA de cualquier tipo en el widget: textos y preguntas salen de plantillas.
- Cambiar cómo puntúa la bandeja de la Home (`PortyInsightsBuilder`): se reusa tal cual.
- Cambiar la selección de noticias y resultados de la ampliación (ventanas de 48 h y 7 días, filtro de recomendación, top 5 por peso): se reusa `WidgetItemsSelector`.
- Backend: nada nuevo (ni tabla, ni RPC, ni edge function). `count_only` y `earnings_count` ya existen (ampliación, fase 2); `product_events` no tiene lista cerrada de nombres.
- Prompt, reglas o catálogo del chat: sin cambios, sin regenerar el hash del allowlist ni desplegar `ai-chat`.
- `AppDelegate.swift` e `ios/Runner/Info.plist`: **no se tocan**. El registro del BGTask del refresco (commit `ae1e60c`) queda como está.
- Callbacks interactivos de `home_widget` que levantan Dart (`HomeWidgetBackgroundIntent`): descartados (§9).

## 3. Contrato de datos

### 3.1 Compatibilidad y versionado

Clave compartida: la misma `porty_widget_snapshot` (App Group en iOS, `HomeWidgetPreferences` en Android), un solo string JSON.

- `v` **sigue en 1** y los campos de v1 que se siguen escribiendo no cambian de forma. Todo lo nuevo va en un bloque opcional **`"v2": {…}`**. Regla: **la presencia de `v2` (objeto) = layout v2**. Dentro del bloque se crece con campos opcionales ("ausente = no hay"). Un cambio que rompa campos del bloque abre un bloque `v3`, nunca reescribe `v2`.
- **App nueva → nativo viejo** (no pasa en la práctica porque extensión y app viajan en el mismo binario, pero no rompe): el nativo v1 decodifica `v == 1` e ignora `v2`. Para que no muestre nada que hoy está prohibido, el bloque v1 se escribe **siempre** con `amounts_hidden: true`, sin `total_text` ni `change_text`, con `phrase` de la plantilla **sin ticker**, sin `questions` y sin los campos de novedades (`items_section`, `items`, `teaser`, `items_*`, `plan_until`). Resultado en un nativo v1: "••••", %, frase sin ticker, sin preguntas ni sección.
- **Nativo nuevo → JSON viejo** (el que dejó la versión anterior, hasta la primera apertura o el primer refresco de fondo): sin `v2` → **modo legado**: cara por `direction`, `labels.period_*`, `change_pct_text`, "tu cartera · hace X" desde `data_as_of`, y en el lugar de las novedades el texto propio del nativo "Abrí Porty para ver las novedades de tu cartera" (strings del sistema, §6.3). **Nunca** lee `total_text`, `change_text`, `items`, `teaser` ni `questions` del JSON viejo (podrían traer tickers de alguien que ahora tiene "Ocultar posiciones"). `signed_out` / `no_portfolio` / sin snapshot: igual que v1.
- `signed_out` y `no_portfolio` no llevan bloque `v2` (igual que hoy).

### 3.2 Snapshot `ready` con bloque `v2`

```jsonc
{
  // --- Bloque v1 (compatibilidad; ver §3.1). Sin montos ni tickers. ---
  "v": 1,
  "state": "ready",
  "lang": "es",
  "written_at": 1794067200000,
  "data_as_of": 1794067080000,
  "stale_at": 1794106800000,
  "period": "today",                       // "today" | "last_close"
  "amounts_hidden": true,                  // SIEMPRE true desde v2
  "currency": "USD",
  "change_pct_text": "+1,2 %",
  "direction": "up",                       // "up" | "down" | "flat" (|Δ%| < 0,3)
  "phrase": "Tu cartera sube hoy.",        // plantilla sin ticker (phrase_up/down/barely_moved/last_close)
  "phrase_stale": "Datos desactualizados. Abrí Porty para actualizarlos.",
  "a11y_value": "Tu cartera sube 1,2 % hoy", // nunca montos
  "labels": { /* las de v1, sin cambios de forma */ },

  // --- Bloque v2 ---
  "v2": {
    "positions_hidden": false,
    "mood": "happy",                       // "happy" (up) | "concerned" (down) | "neutral" (flat). Con datos viejos el nativo usa "neutral"
    "plan_until": 1794500000000,           // epoch ms | null: pasada esa hora el nativo saca los ítems con "paid": true
    "chart": {                             // null = sin gráfico
      "kind": "intraday",                  // "intraday" | "days"
      "points": [0.12, 0.10, 0.25, 0.41, 0.38, 0.77, 1.0],  // 2..48 valores en [0,1], 3 decimales, el último es "ahora"
      "baseline": 0.18                     // [0,1] = cierre anterior (línea punteada) | null en "days"
    },
    "feed_rev": "5be0a1c9",                // 8 hex = FNV-1a 32 de los ids del feed en orden, unidos por ","
    "feed": [                              // 0..8 ítems, YA ORDENADOS por Dart (prioridad + histéresis, §4)
      {
        "id": "51c0e7d2",                  // 8 hex opaco (ids de la ampliación para news/earnings; §4.1 para el resto)
        "kind": "earnings",                // "earnings" | "news" | "insight" | "mover" | "biggest" | "teaser"
        "icon": "calendar",                // "calendar" | "news" | "pie" | "chart"
        "tag": "AAPL",                     // etiqueta de ticker | ausente (metas, plan, teaser, posiciones ocultas)
        "paid": true,                      // news/earnings traídos con el plan pago (se ocultan pasado plan_until)
        "expires_at": 1794193199000,
        "segments": [                      // ≥1. El nativo usa el último con from <= now. "prio" puede cambiar con la hora
          {"from": 1794067200000, "prio": 1, "short": "AAPL · resultados mañana (estimado)",
           "title": "AAPL · fecha estimada de resultados: mañana", "meta": "Resultados · fecha estimada"},
          {"from": 1794106800000, "prio": 1, "short": "AAPL · resultados hoy (estimado)",
           "title": "AAPL · fecha estimada de resultados: hoy", "meta": "Resultados · fecha estimada"}
        ],
        "a11y": "AAPL, fecha estimada de resultados: mañana",
        "open": {"target": "earnings", "id": "51c0e7d2"},
        "q": {"ref": "0c9d2e11", "t": "earnings_last", "src": "novelty",
              "text": "¿Qué presentó AAPL la última vez?"}
      },
      {
        "id": "9f2c41ab",
        "kind": "news", "icon": "news", "tag": "NVDA", "paid": true,
        "published_at": 1794060000000,     // el nativo reemplaza "{age}" en short/title/meta/a11y
        "expires_at": 1794232800000,
        "segments": [
          {"from": 1794067200000, "prio": 1, "short": "NVDA · noticia de hoy",
           "title": "Nvidia unveils new data center chips", "meta": "Noticia · {age}"},
          {"from": 1794106800000, "prio": 3, "short": "NVDA · noticia de ayer",
           "title": "Nvidia unveils new data center chips", "meta": "Noticia · {age}"}
        ],
        "a11y": "Noticia de NVDA, reuters.com, {age}: Nvidia unveils new data center chips",
        "open": {"target": "news", "id": "9f2c41ab"},
        "q": {"ref": "7a1f0b33", "t": "news_what", "src": "novelty", "text": "¿Qué pasó con NVDA?"}
      },
      {
        "id": "e40d7a19",
        "kind": "insight", "icon": "pie",
        "expires_at": 1794153600000,
        "segments": [{"from": 1794067200000, "prio": 2, "short": "Viaje a Japón viene atrasada",
                      "title": "Viaje a Japón viene atrasada", "meta": "Porty te marca"}],
        "a11y": "Porty te marca: Viaje a Japón viene atrasada",
        "open": {"target": "home"},
        "q": {"ref": "c21e9a04", "t": "goal_progress", "src": "novelty", "text": "¿Cómo voy con Viaje a Japón?"}
      },
      {
        "id": "3b77c0de",
        "kind": "mover", "icon": "chart", "tag": "MELI",
        "expires_at": 1794106800000,       // = stale_at
        "segments": [{"from": 1794067200000, "prio": 3, "short": "MELI +4,1 % hoy",
                      "title": "MELI +4,1 % hoy", "meta": "Lo que más se movió hoy"}],
        "a11y": "Lo que más se movió hoy: MELI, sube 4,1 %",
        "open": {"target": "home"},
        "q": {"ref": "88e0f1aa", "t": "mover_today", "src": "novelty", "text": "¿Cómo le fue hoy a MELI en mi cartera?"}
      }
    ],
    "questions": {
      "fallback": {"ref": "b0d4c3e2", "t": "biggest", "src": "biggest",
                   "text": "¿Qué tanto depende mi cartera de NVDA?"},   // mediano cuando el ítem no trae "q" | null
      "large": [                                                        // 0..2, ya elegidas (§4.4)
        {"ref": "0c9d2e11", "t": "earnings_last", "src": "novelty", "text": "¿Qué presentó AAPL la última vez?"},
        {"ref": "c21e9a04", "t": "goal_progress", "src": "goal", "text": "¿Cómo voy con Viaje a Japón?"}
      ]
    },
    "labels": {                            // siempre todas (también con posiciones visibles: el scrub las necesita)
      "your_portfolio": "tu cartera",
      "age_now": "recién", "age_min": "hace {n} min", "age_h": "hace {n} h",
      "age_yesterday": "ayer", "age_d": "hace {n} d",
      "header_one": "Hoy te marco una cosa", "header_other": "Hoy te marco {n} cosas", "header_none": "Tu cartera",
      "list_title": "Lo de hoy",
      "next": "Siguiente", "next_a11y": "Siguiente novedad",
      "hidden_count_one": "1 novedad de tu cartera", "hidden_count_other": "{n} novedades de tu cartera",
      "no_news": "Sin novedades de tu cartera por ahora",
      "redacted": "Desbloqueá tu iPhone para ver las novedades",
      "chart_a11y_intraday": "Gráfico de tu cartera de hoy",
      "chart_a11y_days": "Gráfico de tu cartera de los últimos días"
    }
  }
}
```

Reglas del bloque:

- **Nunca** contiene: montos, valor total, cantidades, precios, URL de artículos, uid, email, tokens.
- **Con `positions_hidden: true`**: los ítems del feed van **solo** con `kind`, `icon`, `paid`, `expires_at` y `segments: [{from, prio}]` (sin `id`, `tag`, `short`, `title`, `meta`, `a11y`, `published_at`, `open`, `q`). `feed_rev` ausente. `questions.fallback` y `questions.large` usan las variantes `_hidden` (sin ticker ni meta, §4.4). `a11y_value` genérico. Nada de ticker, titular, fuente ni nombre de meta en ningún string del JSON (test, §7).
- `chart.points` es la forma normalizada (min..max → 0..1, incluida `baseline`); no se puede reconstruir un monto. Serie plana → todos `0.5`.
- `{age}` lo reemplaza el nativo con `labels.age_*` desde `published_at` (`< 1 min` → `age_now`; `< 60 min` → `age_min`; `< 24 h` → `age_h`; día calendario anterior → `age_yesterday`; si no, `age_d`). El mismo cálculo arma "hace X" del encabezado desde `data_as_of`.

### 3.3 Lo que escribe el nativo (claves compartidas)

| Clave | Quién | Forma | Para qué |
|---|---|---|---|
| `porty_widget_cursor` (nueva) | nativo al tocar "siguiente" | `{"rev":"5be0a1c9","index":2,"at":1794070000000}` | Qué novedad muestra el mediano. Si `rev != feed_rev` del snapshot vigente, el nativo usa `index = 0`. |
| `porty_widget_render_log` (amplía Am.4.8) | nativo en cada dibujo | por tamaño: `{"at":ms,"line":"dated"\|"insight"\|"chart"\|"hidden_count"\|"none","shown_kind":"news","shown_prio":1,"kinds":{"news":1,"earnings":1,"insight":1,"mover":0,"biggest":0,"teaser":0},"live":4,"next_taps":7}` | Eventos (§5). `line` solo en `small`; `shown_*` en `medium`; `kinds` en `medium`/`large`; `next_taps` = contador acumulado del mediano (nunca se resetea en nativo). Los campos de la ampliación (`news`, `earnings`, `teaser`) se siguen escribiendo. **Nunca** ids, tickers ni textos. |

Dart borra las dos en el signOut (junto con lo de v1).

### 3.4 Links del widget (extiende §3.4 y Am.4.4)

| Toque | URL |
|---|---|
| Pregunta | `porty-widget://open?homeWidget&target=question&q=<plantilla>&ref=<8 hex>&src=<fuente>&size=small\|medium\|large&age=<min>` |
| Ítem news / earnings | `…&target=news\|earnings&id=<8 hex>&rank=<1-3>&kind=<kind>&prio=<1-3>&size=…&age=…` (igual que la ampliación + `kind`/`prio`) |
| Ítem insight / mover / biggest, línea oculta, gráfico, lado izquierdo del mediano, encabezado del grande | `…&target=home&kind=<kind>&prio=<1-3>&size=…&age=…` (`kind`/`prio` solo si viene de un ítem) |
| Teaser | igual que la ampliación (`teaser_news` / `teaser_earnings`) |
| Chico | `widgetURL` = el `open` del ítem de su línea; con gráfico o línea oculta, `target=home` |

`WidgetLaunch.parse` (sigue sin aceptar texto libre):
- `target` suma `home`.
- `q` ∈ `WidgetQuestionTemplate.wire` (§4.4); `ref` `^[0-9a-f]{8}$`; `src` ∈ {`novelty`, `goal`, `plan`, `biggest`, `profile`}. Cualquiera inválido → `chat` (chat vacío, no se envía nada). Los ids viejos `today` / `top_mover` ya no existen → `chat`.
- `kind` ∈ los 6 kinds; `prio` 1–3; inválidos → `null` (solo son props de eventos).

Resolución de la pregunta en `WidgetLaunchListener`: busca `ref` en la caché privada `widget_feed_cache_v1` del uid actual (§3.6). Si no está, o su plantilla no coincide con `q` → chat vacío. Si está → texto = `WidgetQuestionText.resolve(template, args, hidden, t)` en el **idioma activo** de la app → `GotoAssistant(initialQuestion: texto, origin: AssistantQuestionOrigin.widget(template.wire))`. Cuota y paywall: el camino normal de `askFromOutside` (sin cambios). Antes del login: la regla de v1 (chat vacío) sigue.

`target=home` → `context.goNamed(HomeRouter.routeName)`.

### 3.5 Qué dibuja cada tamaño (reglas del nativo, idénticas en Swift y Kotlin)

Definiciones (todas con `now` del dibujo):
- `seg(item)` = último segmento con `from <= now` (si ninguno, el primero). `prio(item)` = `seg(item).prio`.
- `live` = ítems del feed con `now < expires_at`, sin los `paid` si `plan_until != null && now >= plan_until`, **ordenados de forma estable por `prio`** (mantiene el orden de Dart dentro de cada prioridad).
- `stale` = `now >= stale_at` (v1): cara `neutral`, `labels.stale_date` en vez de "Hoy", % atenuado. Las novedades siguen (cada una vence sola).

| Tamaño | Arriba | Abajo / derecha |
|---|---|---|
| **Chico** | cara (`mood`) + `labels.period_today`/`period_last_close` + `change_pct_text` grande, color por `direction` | **Una línea con ícono**. Visibles: primer ítem de `live` con `prio <= 2` → ícono + `seg.short`. Si no hay → `chart` (mini gráfico, ícono `chart`). Si no hay gráfico → `no_news`. Con `positions_hidden`: si hay ítems `prio <= 2` → ícono `news` + `hidden_count_*`; si no, gráfico o `no_news`. |
| **Mediano** | Izquierda: cara + % + gráfico del día + "tu cartera · hace X" | Derecha: ítem actual = `live[cursor.index % live.count]` si `cursor.rev == feed_rev`, si no `live[0]` → ícono, `tag` como etiqueta, `seg.meta` ("Noticia · hace 2 h"), `seg.title` a 2 líneas; debajo **una** pregunta = `item.q ?? questions.fallback`; botón "siguiente" solo si `live.count >= 2` (y iOS 17+). Sin `live`: `no_news` + `questions.fallback`. Con `positions_hidden`: `hidden_count_*` (o `no_news`) + `questions.fallback`, sin botón. |
| **Grande** | Encabezado: `header_one/other` con `n` = cantidad de `live` con `prio <= 2` (`header_none` si 0) + "hace X"; % + gráfico ancho | `list_title` + **3 filas**: recorrer `live` en orden tomando ítems, salteando uno si ya hay 2 del mismo `kind`; si quedan menos de 3, completar con los salteados en orden. Cada fila: ícono, `tag`, `seg.title` (1 línea), `seg.meta`. Debajo, `questions.large` (0..2). Con `positions_hidden`: una sola fila `hidden_count_*`/`no_news` y las preguntas `_hidden`. |

**"Siguiente"** (mediano, sin abrir la app): calcula `live` y el índice actual igual que arriba, escribe `{rev: feed_rev, index: (i + 1) % live.count, at: now}` en `porty_widget_cursor`, suma 1 a `next_taps` del render log `medium` y redibuja. Cicla en el orden de prioridad (el de `live`).
- **iOS 17+:** `NextNoveltyIntent: AppIntent` (en el target `PortyWidget`, `@available(iOS 17.0, *)`, `isDiscoverable = false`, `title` localizado) usado con `Button(intent:)`. `perform()` hace lo de arriba; WidgetKit recarga el timeline solo al terminar un intent interactivo. iOS 15–16: la vista no dibuja el botón (`if #available(iOSApplicationExtension 17.0, *)`).
- **Android:** `PendingIntent.getBroadcast` explícito (componente `PortyMediumWidgetProvider`, acción `com.portfolioassistant.app.widget.ACTION_NEXT_NOVELTY`, extra `appWidgetId`, `FLAG_IMMUTABLE`, request code por id). `PortyMediumWidgetProvider.onReceive`: si la acción es esa → `PortyFeedPicker.advance(...)` sobre `HomeWidgetPreferences` y `PortyWidgetRenderer.update` de todos los ids del mediano; cualquier otra acción → `super.onReceive`. No lee extras más allá del id (un broadcast ajeno solo puede avanzar el índice).

Vencimientos sin red: iOS suma al timeline cada `expires_at`, cada `segments[].from`, `stale_at` y `plan_until` (como Am.4.9, tope 40); Android programa la alarma inexacta existente con el próximo de esos límites.

### 3.6 Caché privada y estado (SharedPreferences privado de la app, nunca compartido)

| Clave | Forma | Lo escribe / lee |
|---|---|---|
| `widget_positions_hidden` (nueva) | bool | Ajuste "Ocultar posiciones en el widget". Migración §3.7. |
| `widget_feed_cache_v1` (nueva) | `{"uid","written_at","insights":[{"id","kind","score","tone","ticker"?,"goal_label"?,"numbers":{"pct"?,"weight"?,"pnl"?,"change"?,"current"?,"target"?}}],"goal":{"id","label"}?,"drift_ticker"?,"profile_risk"?,"biggest":{"ticker","weight"}?,"questions":{"<ref>":{"t","args":{"ticker"?,"goal"?,"risk"?},"hidden","seen_at"}}}` | Lo escribe el sync con la app abierta (insights, meta, plan, perfil vienen de providers con sesión). Lo lee el refresco de fondo para rearmar el feed sin sesión, y el listener para resolver `ref`. `questions` acumula las de las últimas 24 h (poda por `seen_at`) para que un toque sobre un dibujo anterior no muera. Insights con más de 24 h no se usan. |
| `widget_feed_state_v1` (nueva) | `{"uid","head_id","head_since"}` | Histéresis (§4.3). Sync y refresco de fondo. |
| `widget_items_cache_v1` (existe) | igual | Sigue siendo la fuente de news/earnings; guarda hasta 7 ítems (antes 4). |

Todas se borran en el mismo paso que `widget_owner_uid` (signOut, borrado de cuenta y `clearHomeWidgetForSignedOutLaunch`). Uid distinto → no se usan.

### 3.7 Migración del ajuste

- Clave nueva `widget_positions_hidden`; la vieja `widget_amounts_hidden` queda como `WidgetPrefsKeys.legacyAmountsHidden`.
- Lectura única para todos (app y refresco de fondo): `WidgetPrefsKeys.readPositionsHidden(prefs) = getBool(positionsHidden) ?? getBool(legacyAmountsHidden) ?? false`.
- **`true` migra a `true`**: quien pidió ocultar montos pidió privacidad; el nuevo ajuste es más estricto y lo puede apagar. `false` → `false`.
- Solo la app escribe la migración (`WidgetPositionsHiddenNotifier` al construirse: si falta la nueva y existe la vieja, escribe la nueva y borra la vieja). El isolate de fondo solo lee con el fallback (sin carreras entre isolates).
- Con el cambio del ajuste: reescritura inmediata desde lo último conocido (v1); si no hay datos de esta sesión, `scrubPositionsFromSnapshotJson` sobre el JSON guardado: pasa los ítems del feed a la forma oculta, saca `feed_rev`, `questions` y `tag`, pone `positions_hidden: true`. Si el JSON es legado (sin `v2`), no hace falta nada (el nativo nuevo ya no muestra tickers del legado).

## 4. Algoritmo (Dart, puro, en `lib/features/home_widget/domain/`)

### 4.1 Candidatos

| kind | De dónde | Prioridad del segmento | Texto (`short` / `title` / `meta`) | Requiere |
|---|---|---|---|---|
| `earnings` | `WidgetItemsSelector` (ventana [hoy, hoy+6], máx 2) | 1 si la fecha estimada está en [hoy, hoy+2]; 3 si después. Un segmento por día en que cambia el texto o la prioridad (mismo esquema que `earningsSegments`) | `short_earnings_*` / `earnings_today\|tomorrow\|date` (existentes) / `meta_earnings` | `PlanFeature.earnings` (ya lo aplica el selector) |
| `news` | `WidgetItemsSelector` (48 h, una por ticker del top 5, filtro de compliance) | 1 mientras `published_at` sea de hoy (local); 3 desde la medianoche siguiente | `short_news_today` → `short_news_yesterday` / titular original / `meta_news` | `heldNews` (ya lo aplica el selector) |
| `insight` | `portyInsightsProvider` (los mismos ≤3 de la Home, mismo orden por `score`, sin los "ya lo vi") | 2 | `title` y `short` = el título de la Home (`porty_inbox_<kind>_title`, mismos argumentos y formato de %); con posiciones ocultas, sin texto | ninguno (la Home ya decide) |
| `teaser` | `SelectedTeaser` de la ampliación (Free→noticias, Premium→resultados; texto ya por plataforma: iOS neutro sin plan) | 3 | texto aprobado del teaser / `meta_teaser` | flags `widget_teasers_*` + conteos (como hoy) |
| `mover` | `WidgetPortfolioFacts`: la tenencia con mayor \|% del último día\| (último cierre vs anterior de las velas diarias ya cargadas); empate → más peso | 3 | `mover_today` / `mover_last` (según `period`) / `meta_mover_today` / `meta_mover_last` | ninguno (precio de lo que tiene; sirve en Free) |
| `biggest` | `WidgetPortfolioFacts`: la de más valor, solo con ≥ 2 posiciones; se omite si ya hay un insight `concentration` o si es el mismo ticker que `mover` | 3 | `biggest` / `meta_biggest` | ninguno |

- Íconos: `earnings` → `calendar`; `news` y `teaser` → `news`; `insight` y `biggest` → `pie`; `mover` → `chart`.
- `expires_at`: news y earnings como la ampliación; insight = `written_at + 24 h`; mover = `stale_at`; biggest = `stale_at`; teaser = `stale_at`.
- Ids: news/earnings = los de la ampliación (`newsId`/`earningsId`, son los que busca la hoja); los demás = `WidgetItemsSelector.itemId('<kind>|<subject>')` (`subject` = id del insight de la Home, ticker o `teaser_<kind>`). Con posiciones ocultas no se escriben (§3.2).
- `paid: true` en news y earnings.

### 4.2 Orden base

1. Por prioridad del segmento vigente al escribir (1 → 2 → 3).
2. Dentro de 1: earnings (fecha asc, peso desc) y después news (peso desc, más reciente).
3. Dentro de 2: `score` de la Home desc (ya viene así).
4. Dentro de 3: news de ayer (peso desc) → earnings lejanos (fecha asc) → teaser → mover → biggest.
5. Tope del feed: 8.

Así Home y widget dicen lo mismo: el primer "descubrimiento" del widget es siempre el primer aviso de la Home.

### 4.3 Histéresis (`WidgetFeedOrder.apply`)

`minHold = 3 h` (constante; la ajusta data con `widget_items_rendered`).

```
entrada: ordenado (4.2), estado {head_id, head_since} del uid, now
h = ítem de ordenado con id == head_id (si no está o venció → sin retención)
si h existe
   y now - head_since < minHold
   y no hay ningún candidato con prio < prio(h):
       mover h al frente (queda primero de su prioridad, que es la más alta presente)
nuevo head = ordenado[0]
si nuevo head.id != head_id → estado = {head_id: nuevo, head_since: now}; si no, se conserva head_since
feed_rev = FNV-1a("id1,id2,…")
```

- Solo entra algo "de mayor prioridad" si su prioridad es estrictamente menor (1 < 2 < 3). Una noticia nueva más pesada no desplaza a otra noticia mostrada hace 1 h.
- El chico muestra el primer `live` con `prio <= 2`, que es el head cuando el head es 1 o 2. El mediano arranca en el head (índice 0) y el toque del usuario no altera el estado de histéresis: el cursor es solo del nativo y se resetea solo cuando cambia `feed_rev`.
- Mientras Dart reescribe el mismo feed (mismos ids y orden, caso típico del refresco cada 30 min), `feed_rev` no cambia y el cursor del usuario se mantiene.
- Con posiciones ocultas el estado no se toca (no hay ids en el JSON).

### 4.4 Preguntas (`WidgetQuestionsBuilder`, sin IA)

Plantillas (`WidgetQuestionTemplate`, lista cerrada; `wire` viaja en la URL y en `question_id` de los eventos):

| wire | Fuente | Plantilla es | Variante `_hidden` es | Requiere (`SubscriptionPolicy.allows`) |
|---|---|---|---|---|
| `news_what` | novedad news | ¿Qué pasó con {ticker}? (clave existente `question_news_why`) | — | `heldNews` |
| `earnings_last` | novedad earnings | ¿Qué presentó {ticker} la última vez? | — | `earnings` |
| `mover_today` | novedad mover (`today`) | ¿Cómo le fue hoy a {ticker} en mi cartera? | — | `ownPortfolio` |
| `mover_last` | novedad mover (`last_close`) | ¿Cómo le fue a {ticker} en la última rueda? | — | `ownPortfolio` |
| `goal_progress` | meta / insight de meta | ¿Cómo voy con {goal}? | ¿Cómo voy con mis metas? | `goals` |
| `plan_far` | plan / insight drift | ¿Por qué {ticker} está lejos de mi objetivo? | ¿Qué parte de mi cartera está más lejos de mi plan? | `allocationPlan` |
| `biggest` | posición más grande / insight concentration / ítem biggest | ¿Qué tanto depende mi cartera de {ticker}? | ¿Qué tanto depende mi cartera de mi posición más grande? | `ownPortfolio` |
| `alert_week` | insight alertNear | ¿Cómo viene {ticker} esta semana? | — | `ownPortfolio` |
| `since_bought` | insight deepLoss | ¿Qué pasó con {ticker} desde que la compré? | — | `ownPortfolio` |
| `topic_since` | insight topicMoved | ¿Qué pasó con {ticker} desde que te pregunté? | — | `marketData` |
| `profile` | perfil | ¿Cómo se compara mi cartera con mi perfil {risk}? | ¿Cómo se compara mi cartera con mi perfil de inversor? | `ownPortfolio` |

Reglas:
1. **Siempre personalizadas**: cada texto nombra un ticker, una meta o un dato del usuario ("mis metas", "mi posición más grande", "mi perfil"). Nunca se arma una pregunta sin su dato; si no hay dato, esa fuente no existe. **No hay pregunta genérica de respaldo**: sin fuentes → sin pregunta (el layout se acomoda).
2. **Plan por capacidad**: una plantilla cuya capacidad no tiene el plan no se usa (evita mandar al usuario a una respuesta bloqueada).
3. **Pregunta del ítem** (`item.q`): según el kind (tabla). Insight → la de su kind (drift → `plan_far`, metas → `goal_progress`, concentration → `biggest`, alertNear → `alert_week`, deepLoss → `since_bought`, topicMoved → `topic_since`). Teaser → sin pregunta.
4. **Generales** (en este orden, sin repetir sujeto): meta (la del primer insight de meta; si no, la activa con `targetDate` más cercana) → plan (`allocationDriftProvider`, solo si hay desvío) → más grande (≥ 2 posiciones) → perfil (`investorProfileProvider`, si existe; `{risk}` = `profile_risk_<wire>`).
5. `questions.fallback` = primera general cuyo sujeto no sea el del head. `questions.large` = [`head.q` si existe] + generales con sujeto distinto, hasta 2.
6. **Posiciones ocultas**: sin `item.q`; generales en su variante `_hidden` (solo las que la tienen, y solo si existe el dato: meta activa, desvío, ≥ 2 posiciones, perfil), sin repetir plantilla.
7. `ref` = `itemId('q|<wire>|<args ordenados>|<hidden>')`. Se guarda en `widget_feed_cache_v1.questions` con `args` crudos (`ticker`, `goal` = label, `risk` = wire) para resolver al tocar.
8. Redacción: preguntas para entender, sin verbos de acción sobre el usuario (comprar, vender, rebalancear, aportar, "deberías"). Test con la regex de compliance de v1 extendida (§7).

### 4.5 Gráfico (`WidgetChartBuilder`)

- Entradas: posiciones (cantidad), velas intradía por ticker (`getIntradayCandles`, 5 min, rango 1d; ya existe en `QuoteRepository` y en `YahooQuoteRemoteDataSource`), cierre anterior por ticker (de las velas diarias ya cargadas), `direction`.
- Se piden intradía solo los **10 tickers de más valor**, en paralelo, 6 s de timeout cada uno; el resto y los que fallan quedan fijos en su precio actual.
- Grilla = timestamps del ticker de más valor con ≥ 6 puntos; los demás se rellenan hacia adelante (antes de su primer punto, cierre anterior). `valor(t) = Σ cantidad × precio(t)`; `baseline = Σ cantidad × cierre anterior`.
- **Guarda de coherencia**: si `direction` es `up`/`down` y el signo de `último − baseline` lo contradice → no se usa el intradía.
- Respaldo `days`: últimos 8 puntos del historial diario (el de la Home), `baseline: null`, si hay ≥ 3.
- Si no hay nada → `chart: null`.
- Normaliza a [0,1] y reduce a ≤ 48 puntos (equiespaciados, se conserva el último).

### 4.6 Dónde corre

- **App abierta** (`HomeWidgetSyncController`): `onHome` captura además velas intradía e insumos de preguntas; nuevos disparadores con el mismo debounce y la misma cola: cambio de `portyInsightsProvider`, `goalsProvider`, `allocationDriftProvider`, `investorProfileProvider`, ajuste de posiciones, idioma, plan. Escribe `widget_feed_cache_v1` y `widget_feed_state_v1`. Lee `porty_widget_render_log` al abrir para eventos.
- **Refresco de fondo** (`refreshOnce`): precios + intradía de Yahoo directo (sin sesión, como v1), news/earnings de `widget_items_cache_v1`, insights/meta/plan/perfil de `widget_feed_cache_v1` (≤ 24 h), mover y biggest recalculados con los precios nuevos, misma histéresis, mismo builder. Relee el uid antes de escribir (v1).

## 5. Eventos (`product_events` vía `ProductEvents.log`)

Ningún evento lleva ticker, titular, fuente, nombre de meta, texto de pregunta ni id de ítem (test con fake `ProductEvents`).

| Evento | Props | Dónde | Cambio |
|---|---|---|---|
| `widget_opened` | + `target` `home`; `question_id` = wire de la plantilla; + `question_source` (`novelty`\|`goal`\|`plan`\|`biggest`\|`profile`); + `item_kind`, `item_prio`; `positions_hidden` **reemplaza** `amounts_hidden` | listener | amplía |
| `widget_items_rendered` | + `line_kind` (chico), `shown_kind`, `shown_prio` (mediano), `insight_count`, `mover_count`, `biggest_count`, `live_count`; `positions_hidden` reemplaza `amounts_hidden` | sync al abrir, desde el render log | amplía |
| `widget_feed_advanced` | `platform`, `size` (`medium`), `taps` (delta de `next_taps` desde lo último registrado en prefs privadas) | sync al abrir | **nuevo** |
| `widget_positions_toggled` | `hidden` | tile de Ajustes | **nuevo** (`widget_amounts_toggled` queda en el enum, sin uso) |
| `widget_question_result` | sin cambios (`question_id` = wire) | assistant (ya existe) | — |

Pedirle a `porty-data-analyst` que confirme `minHold` (3 h) y si alcanza `widget_feed_advanced` agregado (no hay forma de loguear el toque en el momento: no abre la app).

## 6. Tareas por dueño

Dos dueños nunca comparten archivo. Tres instancias de `porty-flutter-dev` con conjuntos disjuntos; con el presupuesto de 2 agentes a la vez: **Dart ∥ nativo iOS**, después **nativo Android** (o una sola instancia nativa que haga iOS y después Android). **porty-assistant-dev: nada** (`AssistantQuestionOrigin.widget(String)` ya acepta cualquier id). **porty-backend-dev: nada.**

### 6.1 porty-flutter-dev (Dart) — arranca ya; primero `widget_snapshot.dart` + fixtures (desbloquean al nativo)

| Archivo | Qué |
|---|---|
| `lib/features/home_widget/domain/widget_snapshot.dart` | Bloque v1 según §3.1 (sin montos, `amounts_hidden: true`, sin `questions` ni campos de novedades); clases a mano `WidgetV2Block`, `WidgetFeedItem`, `WidgetFeedSegment`, `WidgetChart`, `WidgetQuestionRef` con `toJson`; forma oculta de los ítems |
| `lib/features/home_widget/domain/widget_feed_builder.dart` (nuevo) | §4.1–4.2: candidatos, segmentos con prioridad, ids, orden base |
| `lib/features/home_widget/domain/widget_feed_order.dart` (nuevo) | §4.3 histéresis + `feed_rev` |
| `lib/features/home_widget/domain/widget_feed_picker.dart` (nuevo) | Implementación de referencia en Dart de §3.5 (live, chico, mediano, grande, siguiente). Solo para tests y para generar `feed_cases.json`; la app no la usa para dibujar |
| `lib/features/home_widget/domain/widget_questions.dart` (nuevo) | `WidgetQuestionTemplate`, `WidgetQuestionsBuilder` (§4.4), `WidgetQuestionText.resolve(template, args, hidden, t)` (lo usan builder y listener) |
| `lib/features/home_widget/domain/widget_chart_builder.dart` (nuevo) | §4.5 |
| `lib/features/home_widget/domain/widget_portfolio_facts.dart` (nuevo) | mover y biggest (puro) |
| `lib/features/home_widget/domain/widget_insight_copy.dart` (nuevo) | Títulos de insights con `WidgetTexts` y las **mismas claves** `porty_inbox_*_title` de la Home (sin `.tr()`, corre en el isolate de fondo) |
| `lib/features/home_widget/domain/widget_snapshot_builder.dart` | `ready()` sin `totalValue` ni montos; `mood`; arma el bloque `v2` (feed, chart, preguntas, labels); reemplaza `withItems` |
| `lib/features/home_widget/domain/widget_texts.dart` | Carga también el prefijo `porty_inbox_` (método aparte) |
| `lib/features/home_widget/domain/widget_items_selector.dart` | Parámetro `cap` (v2 pide 7; default 4 para no romper tests) |
| `lib/features/home_widget/domain/widget_launch.dart` | §3.4: `home`, `q`/`ref`/`src`, `kind`/`prio`; saca `WidgetQuestionId` |
| `lib/features/home_widget/domain/widget_phrase.dart` | Sin cambios de plantillas; el builder siempre pasa `topTicker: null` |
| `lib/features/home_widget/data/widget_feed_cache.dart` (nuevo) | `widget_feed_cache_v1` y `widget_feed_state_v1` (§3.6), `clear()` |
| `lib/features/home_widget/data/widget_items_cache.dart` | Guarda hasta 7 ítems |
| `lib/features/home_widget/data/home_widget_store.dart` | `readCursor`, `clearCursor`; render log ampliado; `scrubPositionsFromSnapshotJson` reemplaza `scrubAmountsFromSnapshotJson` |
| `lib/features/home_widget/data/widget_background_refresh.dart` | Intradía, feed desde cachés, histéresis, `readPositionsHidden`; signOut borra cachés nuevas y cursor. **No tocar** `widgetRefreshTaskId` ni el registro (AppDelegate depende de ese id) |
| `lib/features/home_widget/providers/widget_settings_provider.dart` | `WidgetPrefsKeys.positionsHidden`, `legacyAmountsHidden`, `readPositionsHidden`; `WidgetPositionsHiddenNotifier` + `widgetPositionsHiddenProvider` con migración §3.7 |
| `lib/features/home_widget/providers/home_widget_sync_provider.dart` | §4.6: nuevos insumos y disparadores, `loadIntraday`, eventos nuevos, borra lo nuevo en signOut |
| `lib/features/home_widget/providers/widget_prompt_provider.dart` | Vista previa de la oferta sin total: % + "tu cartera" |
| `lib/features/home_widget/view/widget_amounts_tile.dart` → **renombrar** `widget_positions_tile.dart` (`WidgetPositionsTile`) + `lib/presentation/flows/settings/ui/settings_screen.dart` (import y uso) | Ajuste nuevo con texto de privacidad nuevo; `widget_positions_toggled` |
| `lib/features/home_widget/view/widget_launch_listener.dart` | Resolución de `ref`, `target=home`, props nuevas |
| `lib/features/home_widget/view/widget_add_sheet.dart` | Solo si la vista previa usa `total` (adaptar a §3.2) |
| `lib/features/product_events/data/product_events.dart` | `widgetFeedAdvanced`, `widgetPositionsToggled` (+ doc de props ampliadas) |
| `assets/translations/es-ES.json`, `en-US.json` | §6.4 (agregar nuevas, sacar `hide_amounts`, `privacy_note`, `question_today`, `question_top_mover`) |
| `test/tools/export_widget_avatar_test.dart` | Exporta 3 caras: `idle` (neutral, existente), `answered` (happy), `concerned`, claro/oscuro, a `PortyAvatar{,Happy,Concerned}.imageset` y `porty_widget_avatar{,_happy,_concerned}.png`. Se corre a mano y se commitean los PNG |
| `test/fixtures/home_widget/v2/*.json` | `ready_{es,en}.json` (Gold con todo), `ready_free_android.json`, `ready_free_ios.json` (insight + teaser neutro + mover), `ready_hidden_es.json`, `ready_chart_only_es.json` (feed vacío), `ready_days_chart_es.json`, `ready_expiring.json` (news que pasa a prio 3 y earnings que vence), `legacy_v1_items.json` (JSON de la versión anterior con montos y tickers) y **`feed_cases.json`**: casos `{snapshot, now, cursor, expected:{small, medium, large, header_n, next_index}}` generados con `WidgetFeedPicker` |
| `test/features/home_widget/**` | §7.1 |

### 6.2 porty-flutter-dev (nativo iOS) — en paralelo, contra el ejemplo de §3.2 hasta que estén los fixtures

| Archivo | Qué |
|---|---|
| `ios/PortyWidget/PortyWidgetFeed.swift` (nuevo) | Decodificación del bloque `v2` y `FeedPicker` puro (§3.5): **solo `import Foundation`** para poder compilarlo fuera del target |
| `ios/PortyWidget/NextNoveltyIntent.swift` (nuevo) | `AppIntent` iOS 17+ (§3.5) + escritura de cursor y `next_taps` |
| `ios/PortyWidget/SnapshotStore.swift` | Lee `v2` y cursor; render log ampliado; modo legado §3.1 |
| `ios/PortyWidget/PortyWidget.swift` | Límites del timeline desde el feed (§3.5); render log por tamaño (suma `small`) |
| `ios/PortyWidget/PortyWidgetViews.swift` | Layouts chico/mediano/grande de las maquetas, cara por `mood`, gráfico con `Path`, `.privacySensitive()` en `tag`, títulos, meta y preguntas (con `labels.redacted`), `Button(intent:)` bajo `#available`, `Link` por pregunta/ítem, previews con datos ficticios **sin montos** |
| `ios/PortyWidget/PortyWidgetItems.swift` | Reemplazar o borrar (lo cubre `PortyWidgetFeed.swift`) |
| `ios/PortyWidget/Assets.xcassets` | `PortyAvatarHappy.imageset`, `PortyAvatarConcerned.imageset` (los PNG los exporta el tool de Dart) |
| `ios/PortyWidget/{es,en}.lproj/Localizable.strings` | Título del intent, textos del modo legado, galería nueva sin montos, muestras ficticias |
| `ios/tools/feed_cases_check.swift` (nuevo, fuera del target) | Corre `FeedPicker` contra `test/fixtures/home_widget/v2/feed_cases.json` (§7.2) |

No tocar `ios/Runner/AppDelegate.swift`, `ios/Runner/Info.plist` ni `project.pbxproj` (los grupos del proyecto son sincronizados con la carpeta: los `.swift` nuevos de `ios/PortyWidget/` entran solos al target).

### 6.3 porty-flutter-dev (nativo Android) — después del iOS o en paralelo si hay presupuesto

| Archivo | Qué |
|---|---|
| `android/app/src/main/kotlin/com/portfolioassistant/app/widget/PortyFeedPicker.kt` (nuevo) | §3.5 puro (solo `org.json`, sin `android.*`), incluye `advance` |
| `…/widget/PortyChartBitmap.kt` (nuevo) | Dibuja el gráfico en un `Bitmap` chico (Canvas) para `setImageViewBitmap`, colores de `widget_colors.xml` |
| `…/widget/PortyWidgetRenderer.kt` | Layout v2, modo legado, alarma con los límites del feed, render log ampliado (suma `small`) |
| `…/widget/PortyMediumWidgetProvider.kt` | `onReceive` de `ACTION_NEXT_NOVELTY` |
| `…/widget/PortySmallWidgetProvider.kt`, `PortyLargeWidgetProvider.kt` | Solo si cambia la firma del renderer |
| `android/app/src/main/res/layout/porty_widget_{small,medium,large}.xml` y `*_preview.xml` | Maquetas; grande con 3 filas fijas (`GONE` las sobrantes) y 2 preguntas; previews ficticias sin montos |
| `android/app/src/main/res/drawable/ic_widget_{calendar,news,pie,chart,next}.xml` (nuevos) | Íconos vectoriales |
| `android/app/src/main/res/drawable{,-night}-nodpi/porty_widget_avatar_{happy,concerned}.png` | Del tool de Dart |
| `android/app/src/main/res/values{,-es}/widget_strings.xml` | Modo legado, galería sin montos, `contentDescription` del botón |
| `android/app/src/main/res/xml/porty_widget_*_info.xml` | Descripción de galería nueva |
| `android/app/build.gradle.kts` | Solo `testImplementation("junit:junit:4.13.2")` y `testImplementation("org.json:json:20240303")` (en tests JVM `org.json` de Android es un stub). No tocar nada más (rename en curso) |
| `android/app/src/test/kotlin/com/portfolioassistant/app/widget/PortyFeedPickerTest.kt` (nuevo) | §7.2 |

`AndroidManifest.xml`: sin cambios (el broadcast es explícito al receiver ya declarado).

### 6.4 Textos nuevos (`home_widget_*`, es / en) — los agrega flutter-dev Dart; compliance los revisa antes del merge

| Clave | es | en |
|---|---|---|
| `hide_positions` | Ocultar posiciones en el widget | Hide positions in the widget |
| `positions_privacy_note` | El widget nunca muestra montos. Con esto activado tampoco muestra tickers, titulares, fuentes ni nombres de metas: solo el % del día y cuántas novedades hay. Guarda un resumen de tu cartera en este teléfono y se borra al cerrar sesión. | The widget never shows amounts. With this on, it also hides tickers, headlines, sources and goal names: only today's % and how many updates there are. It keeps a summary of your portfolio on this phone, deleted when you sign out. |
| `your_portfolio` | tu cartera | your portfolio |
| `age_now` / `age_d` | recién / hace {n} d | just now / {n} d ago |
| `header_none` | Tu cartera | Your portfolio |
| `list_title` | Lo de hoy | Today |
| `next` / `next_a11y` | Siguiente / Siguiente novedad | Next / Next update |
| `hidden_count_one` / `_other` | 1 novedad de tu cartera / {n} novedades de tu cartera | 1 update on your portfolio / {n} updates on your portfolio |
| `no_news` | Sin novedades de tu cartera por ahora | No updates on your portfolio for now |
| `meta_news` | Noticia · {age} | News · {age} |
| `meta_earnings` | Resultados · fecha estimada | Earnings · estimated date |
| `meta_insight` | Porty te marca | Porty noticed |
| `meta_mover_today` / `meta_mover_last` | Lo que más se movió hoy / Lo que más se movió al último cierre | Today's biggest move / Biggest move at last close |
| `meta_biggest` | Tu posición más grande | Your largest position |
| `meta_teaser` | Novedades | Updates |
| `short_news_today` / `short_news_yesterday` | {ticker} · noticia de hoy / {ticker} · noticia de ayer | {ticker} · news today / {ticker} · news yesterday |
| `short_earnings_today` / `_tomorrow` / `_date` | {ticker} · resultados hoy (estimado) / {ticker} · resultados mañana (estimado) / {ticker} · resultados el {weekday} (estimado) | {ticker} · earnings today (estimated) / {ticker} · earnings tomorrow (estimated) / {ticker} · earnings on {weekday} (estimated) |
| `mover_today` / `mover_last` | {ticker} {pct} hoy / {ticker} {pct} al último cierre | {ticker} {pct} today / {ticker} {pct} at last close |
| `biggest` | {ticker} es tu posición más grande: {weight} | {ticker} is your largest position: {weight} |
| `a11y_v2_today` / `a11y_v2_last_close` | Tu cartera {direction} {pct} hoy / Tu cartera {direction} {pct} al último cierre | Your portfolio is {direction} {pct} today / Your portfolio is {direction} {pct} at last close |
| `a11y_insight` | Porty te marca: {title} | Porty noticed: {title} |
| `a11y_mover` | Lo que más se movió {period}: {ticker}, {direction} {pct} | Biggest move {period}: {ticker}, {direction} {pct} |
| `a11y_hidden_item` | Novedad de tu cartera | Update on your portfolio |
| `chart_a11y_intraday` / `chart_a11y_days` | Gráfico de tu cartera de hoy / Gráfico de tu cartera de los últimos días | Chart of your portfolio today / Chart of your portfolio over the last days |
| `q_earnings_last` | ¿Qué presentó {ticker} la última vez? | What did {ticker} report last time? |
| `q_mover_today` / `q_mover_last` | ¿Cómo le fue hoy a {ticker} en mi cartera? / ¿Cómo le fue a {ticker} en la última rueda? | How did {ticker} do in my portfolio today? / How did {ticker} do in the last session? |
| `q_goal_progress` / `_hidden` | ¿Cómo voy con {goal}? / ¿Cómo voy con mis metas? | How am I doing with {goal}? / How am I doing with my goals? |
| `q_plan_far` / `_hidden` | ¿Por qué {ticker} está lejos de mi objetivo? / ¿Qué parte de mi cartera está más lejos de mi plan? | Why is {ticker} far from my target? / Which part of my portfolio is furthest from my plan? |
| `q_biggest` / `_hidden` | ¿Qué tanto depende mi cartera de {ticker}? / ¿Qué tanto depende mi cartera de mi posición más grande? | How much does my portfolio depend on {ticker}? / How much does my portfolio depend on my largest position? |
| `q_alert_week` | ¿Cómo viene {ticker} esta semana? | How is {ticker} doing this week? |
| `q_since_bought` | ¿Qué pasó con {ticker} desde que la compré? | What happened with {ticker} since I bought it? |
| `q_topic_since` | ¿Qué pasó con {ticker} desde que te pregunté? | What happened with {ticker} since I asked you? |
| `q_profile` / `_hidden` | ¿Cómo se compara mi cartera con mi perfil {risk}? / ¿Cómo se compara mi cartera con mi perfil de inversor? | How does my portfolio compare with my {risk} profile? / How does my portfolio compare with my investor profile? |
| `profile_risk_conservative` / `_moderate` / `_aggressive` | conservador / moderado / agresivo | conservative / moderate / aggressive |
| `gallery_description`, `gallery_description_large` (cambian) | Mirá cómo viene tu cartera hoy y lo que Porty te marca, sin abrir la app. | See how your portfolio is doing today and what Porty noticed, without opening the app. |

Se reusan sin cambio: `question_news_why` (= `q_news_what`), `earnings_*`, `teaser_*`, `items_redacted` (= `labels.redacted`), `age_min/h/yesterday`, `phrase_*`, `porty_inbox_title_one/many` (encabezado del grande) y `porty_inbox_*_title` (insights). El nativo copia a sus strings solo lo de galería, modo legado y el título del intent.

### 6.5 Orden

```
flutter-dev Dart: widget_snapshot.dart + fixtures v2 (incl. feed_cases.json) ──► nativo integra contra fixtures reales
flutter-dev nativo iOS  ─┐ (arrancan contra el ejemplo de §3.2)
flutter-dev nativo Android ─┘
compliance revisa §6.4 + §6.6 en paralelo; Dart no mergea textos sin ese OK
```

### 6.6 Qué revisa porty-compliance

1. Todos los textos de §6.4 en es y en, en especial: las 11 plantillas de preguntas (¿alguna se lee como pedido de recomendación o de "suitability"? `q_profile` y `q_plan_far` son las dudosas), `mover_*` (sin causa), `short_earnings_*` ("estimado" en el formato corto), `meta_insight`.
2. Insights de la Home fuera de la app: "{ticker} acumula −25 % desde que la compraste" y "{goal} viene atrasada" ahora se ven en la pantalla de inicio (con `.privacySensitive()` en iOS; Android sin equivalente).
3. Cara preocupada en días de baja: ¿es juicio sobre el resultado?
4. Texto del ajuste "Ocultar posiciones" y la frase de la política de privacidad (el widget guarda además avisos y nombres de metas en el almacenamiento compartido cuando no están ocultas).
5. Migración `true → true` del ajuste viejo.
6. Teaser de iOS: se reusa el texto ya aprobado ("Hay {n} noticias de tu cartera en Porty"), sin plan ni pago.

## 7. Tests

### 7.1 Dart (`flutter test test/features/home_widget`)

- `domain/widget_feed_builder_test.dart`: prioridad de cada kind y sus segmentos (news de hoy → 1 y pasa a 3 a la medianoche local; earnings a 2 días → 1, a 3 → 3; cambio de horario); orden base §4.2; tope 8; biggest omitido con concentration o mismo ticker que mover; Free = insights + teaser + mover + biggest, nunca news/earnings; Gold nunca teaser; ids de news/earnings iguales a los de la ampliación; con `positions_hidden` los ítems solo tienen `kind/icon/paid/expires_at/segments{from,prio}`.
- `domain/widget_feed_order_test.dart`: retiene el head < 3 h; lo suelta a las 3 h; un ítem de prioridad más alta lo desplaza aunque no pasaron 3 h; uno de igual prioridad y más peso no; head vencido o desaparecido → nuevo head con `head_since = now`; `feed_rev` estable con el mismo feed y distinto si cambia el orden.
- `domain/widget_feed_picker_test.dart`: cada regla de §3.5 (chico con prio ≤ 2 / gráfico / `no_news`; mediano con cursor de otro `rev` → 0; grande con máximo 2 por kind y relleno; `header_n`; `advance` cíclico; `plan_until`; reorden estable cuando un segmento cambia de prioridad). Además, **regenera `feed_cases.json`** y falla si difiere del commiteado (patrón de los fixtures v1).
- `domain/widget_questions_test.dart`: texto exacto de cada plantilla y variante es/en; cada pregunta contiene su ticker, su meta o "mi(s)" + dato; ninguna generada sin dato; capacidad por plan (Free sin `earnings_last`/`news_what`/`goal_progress`; Premium sin `earnings_last`); sin sujetos repetidos; `fallback` distinto del head; `large` ≤ 2; ocultas sin ticker ni meta; regex de verbos de acción y recomendación (lista de compliance v1 + "rebalance", "aport", "deberías", "should I") en es y en no matchea ninguna plantilla; `ref` determinístico.
- `domain/widget_chart_builder_test.dart`: forma y normalización; top 10 por valor; ticker caído queda fijo; guarda de coherencia (sube con intradía que termina abajo → `days`); `days` con < 3 puntos → `null`; ≤ 48 puntos con el último conservado; serie plana → 0.5.
- `domain/widget_snapshot_builder_test.dart`: bloque v1 sin `total_text`, `change_text`, `questions`, `items*`, `teaser`, con `amounts_hidden: true` y frase sin ticker; **ningún número con símbolo de moneda en ningún string del JSON** (regex `[$€]|US\$|USD\s?\d`); con posiciones ocultas, ningún ticker de la cartera, titular, fuente ni label de meta en el JSON (búsqueda literal); `mood` por dirección; fixtures v2 regenerados iguales.
- `domain/widget_launch_test.dart`: `home`; pregunta con `q`/`ref`/`src` válidos; `q=today` → chat; `ref` no hex → chat; `text=` ignorado; `kind`/`prio` inválidos → null.
- `data/widget_background_refresh_test.dart`: feed desde cachés sin red de noticias; insights de > 24 h no entran; uid distinto → sin feed; usa `readPositionsHidden` con la clave vieja; histéresis persistida entre dos refrescos.
- `data/home_widget_store_test.dart`: `scrubPositionsFromSnapshotJson` deja el bloque sin tickers ni preguntas.
- `providers/widget_settings_provider_test.dart`: migración `true→true`, `false→false`, sin claves → `false`, la vieja se borra, idempotente.
- `providers/home_widget_sync_provider_test.dart`: disparadores nuevos (insights, metas, desvío, perfil) reescriben; signOut borra `widget_feed_cache_v1`, `widget_feed_state_v1`, cursor y render log; `widget_feed_advanced` con el delta de `next_taps`; props sin ticker ni texto.
- `view/widget_launch_listener_test.dart`: `ref` encontrado → `GotoAssistant` con el texto en el idioma activo y `origin.widget(<wire>)`; `ref` de otro uid o inexistente → chat vacío sin envío; `home` → Home; antes del login → chat vacío.
- `view/widget_positions_tile_test.dart`: evento y reescritura inmediata.

### 7.2 Nativo

- **Kotlin** (`cd android && ./gradlew :app:testDevelopmentDebugUnitTest --tests '*PortyFeedPickerTest*'`): `PortyFeedPicker` contra cada caso de `test/fixtures/home_widget/v2/feed_cases.json` (ruta relativa al módulo: `../../test/fixtures/...`), más: JSON legado → modo legado sin tickers; `v2` ausente o roto → no lanza.
- **Swift** (en una Mac, sin target de tests): `xcrun swiftc ios/PortyWidget/PortyWidgetFeed.swift ios/tools/feed_cases_check.swift -o /tmp/feedcheck && /tmp/feedcheck test/fixtures/home_widget/v2/feed_cases.json` termina en 0. Si el usuario crea un target XCTest más adelante, el mismo chequeo pasa ahí.
- Manual con fixtures (simulador/emulador): capturas §8.6.

## 8. Criterios de aceptación

1. `flutter analyze` sin warnings nuevos; `flutter test test/features/home_widget test/features/product_events test/security` en verde.
2. Ningún snapshot generado (fixtures y tests de builder) contiene montos ni valor total; el bloque v1 lleva `amounts_hidden: true` y no lleva `total_text`/`change_text` (test).
3. Con `positions_hidden: true`, el JSON no contiene ningún ticker de la cartera, titular, fuente ni nombre de meta (test de búsqueda literal sobre `ready_hidden_es.json` y sobre el builder con datos variados).
4. La pref vieja `widget_amounts_hidden = true` se lee como "Ocultar posiciones" activado, también en el refresco de fondo antes de abrir la app (test).
5. `WidgetFeedPicker` (Dart), `PortyFeedPicker` (Kotlin) y `FeedPicker` (Swift) dan el mismo resultado en todos los casos de `feed_cases.json` (comandos de §7.2).
6. Capturas claro y oscuro de chico, mediano y grande, iOS y Android, con `ready_es`, `ready_free_{ios,android}`, `ready_hidden_es`, `ready_chart_only_es` y `legacy_v1_items`, revisadas por porty-ui-reviewer contra las maquetas. En ninguna aparece un monto; en `legacy_v1_items` no aparece ningún ticker.
7. Histéresis: con el reloj fijo, un refresco a los 30 min con una noticia nueva de igual prioridad no cambia el head; uno con un resultado en ≤ 2 días (prio 1) sobre un insight (prio 2) sí (test).
8. "Siguiente" en el mediano avanza sin abrir la app: iOS 17+ (dispositivo o simulador) y Android; cicla y vuelve al primero; en iOS 15/16 el botón no aparece y el widget dibuja igual; con 0–1 novedades no aparece.
9. Tocar una pregunta abre el chat con esa pregunta enviada una vez, en el idioma activo; una URL con `q` o `ref` inválidos, o con `text=…`, abre el chat vacío sin enviar nada (test).
10. Free con cartera de ≥ 2 posiciones y precios: el grande nunca queda sin filas (test del builder + captura `ready_free_*`); en iOS el aviso no nombra plan ni pago.
11. Las preguntas del snapshot siempre nombran un ticker, una meta o un dato del usuario, y respetan el plan (test §7.1).
12. `flutter build ios --no-codesign` y `flutter build apk --flavor development` compilan; `AppDelegate.swift` y `ios/Runner/Info.plist` sin cambios en el diff; el refresco de fondo sigue registrándose (el id `com.portyassistant.app.widget_refresh` no cambió).
13. Eventos: ninguna prop de `widget_*` contiene ticker, titular, texto de pregunta ni id de ítem (test con fake `ProductEvents`).
14. Textos de §6.4 con OK de porty-compliance antes del merge.

## 9. Riesgos y decisiones

**Decisiones (mías) y alternativas descartadas**
- **`v` sigue en 1 + bloque `v2`** en vez de subir `v` a 2: un nativo v1 seguiría dibujando algo coherente (sin montos) en lugar de "abrí Porty", y el nativo nuevo distingue legado por la ausencia del bloque. Descartado escribir dos snapshots en dos claves (doble escritura, sin atomicidad).
- **Orden e histéresis en Dart; el nativo solo filtra por hora y reordena estable por prioridad del segmento.** Las promociones/descensos por hora (news de hoy → ayer, resultados que se acercan) van como segmentos con `prio`, así el nativo no necesita reloj de negocio. Descartado: histéresis en nativo (dos implementaciones con estado).
- **Cursor del mediano solo nativo, reseteado por `feed_rev`**: el toque del usuario no pelea con la histéresis y un feed igual conserva su posición. Descartado: que Dart lea el cursor para su histéresis (acopla chico y mediano).
- **Botón con AppIntent / broadcast nativos**, no `home_widget` interactivo: ese camino levanta el motor de Dart en segundo plano por cada toque (lento, consume y en iOS corre en la extensión); avanzar un índice no necesita Dart.
- **Preguntas por `ref` a una caché privada**, no texto ni ticker en la URL: la URL no lleva datos del usuario (con posiciones ocultas tampoco), el parse sigue sin texto libre y los nombres de metas (texto del usuario) nunca salen del almacenamiento privado.
- **Sin pregunta genérica de respaldo**: si no hay dato, no hay pregunta (decisión 6). Con posiciones ocultas y sin metas/plan/perfil y una sola posición puede no haber ninguna.
- **Encabezado del grande cuenta lo del widget** (prio ≤ 2: resultados cercanos, noticias de hoy, avisos), no solo los avisos de la Home; puede decir un número distinto que la Home. Si el PO prefiere el mismo número, es cambiar el filtro a `kind == insight` (una línea en cada nativo).
- **Gráfico intradía con 10 tickers como mucho**: es una forma, no un valor; costo acotado (≤ 10 llamadas directas a Yahoo por publicación, en paralelo). Con la guarda de coherencia el gráfico nunca contradice el color del %.
- **Avatar con 3 PNG estáticos** (neutral, contento, preocupado) exportados del `PortyAvatarPainter`, igual que v1.

**Riesgos**
- `import AppIntents` en una extensión con iOS 15 de mínimo: debería enlazarse débil por la disponibilidad, pero hay que probar en simulador iOS 15/16 que la extensión carga. Si falla: marcar `AppIntents.framework` como *Optional* en el target `PortyWidget` (paso manual del usuario en Xcode).
- Presupuesto de WidgetKit: cada toque de "siguiente" recarga el timeline; entiendo que las recargas disparadas por un intent interactivo no consumen el presupuesto diario (WWDC23), pero no lo confirmé en la documentación actual. Verificar en dispositivo tocando "siguiente" muchas veces seguidas.
- Yahoo intradía puede no traer datos para algunos tickers (`.BA`, cripto de Binance): quedan fijos; en el peor caso, gráfico `days`.
- Insights en el refresco de fondo pueden tener hasta 24 h (los % de concentración o pérdida se corren algo con precios nuevos). Se corrigen al abrir la app.
- Android sin `.privacySensitive()`: con posiciones visibles, la pantalla de inicio muestra tickers, titulares y nombres de metas (riesgo ya aceptado en la ampliación; ahora suma metas y avisos). Mitigación: "Ocultar posiciones".
- Bitmaps en RemoteViews: límite de memoria por widget; el gráfico es chico (≤ 600×160 px) y se reusa el mismo id.
- La fuente custom en RemoteViews (riesgo de v1) sigue.

**Necesita OK del usuario**
- Nada en Supabase (sin migraciones, sin deploys) ni en `ai-chat` (sin cambio de prompt ni evals).
- Pasos manuales: correr el exportador del avatar (`RUN_WIDGET_AVATAR=1 flutter test test/tools/export_widget_avatar_test.dart`) y commitear los PNG; probar en dispositivo real (`.privacySensitive()`, "siguiente" en iOS 17+, iOS 15/16 sin botón); si hace falta, marcar `AppIntents.framework` como Optional.
- Actualizar la frase de privacidad de la política y revisar las etiquetas de privacidad de las tiendas según lo que diga compliance (§6.6.4).

**Preguntas abiertas** (no bloquean; tienen decisión por defecto)
1. `minHold` = 3 h: confirmar con data después de una semana de `widget_items_rendered`.
2. Número del encabezado del grande (widget vs Home): por defecto, el del widget.
