# Spec técnica: widget de Porty en la pantalla de inicio (iOS + Android)

**Fecha:** 2026-11-05 · **Autor:** porty-architect · **Implementa:** `docs/specs/home-widget-product.md` (brief + "Decisiones del usuario" + "Revisión de compliance (2026-11-05)"). No reabre decisiones de producto.

## 1. Objetivo

El usuario ve en la pantalla de inicio el valor de su cartera, la variación del día, una frase descriptiva y 2 preguntas rápidas que abren el chat con la pregunta ya enviada. **Listo** = los 16 criterios del brief (con el 7 ajustado por compliance) pasan en un iPhone y un Android reales, con los tests de §8 en verde y `flutter analyze` limpio.

Decisión central: **el widget es un visor tonto**. Flutter arma todo (números ya formateados, frase, textos en el idioma activo, momento en que pasa a "datos viejos") y lo deja en un JSON en el almacenamiento compartido. El código nativo solo dibuja ese JSON, calcula "hace X" y compara la hora con `stale_at`. Ninguna lógica de negocio en Swift/Kotlin.

## 2. Fuera de alcance

Todo lo de §5 del brief (widget grande, pantalla bloqueada, StandBy como objetivo, App Intents interactivos, frase con IA, preguntas Premium/Gold, push silencioso). Además, en esta spec:
- Nada en Supabase (ni tabla, ni RPC, ni edge function). Ver §3.6.
- Nada de red ni sesión en la extensión de iOS ni en el proveedor de Android.
- Montos en otra moneda que no sea USD (ver §3.2).
- Paquete `app_links` propio y rutas nuevas de go_router (ver §3.4).

## 3. Contrato de datos

### 3.1 Paquetes

| Paquete | Versión | Para qué | Por qué este |
|---|---|---|---|
| `home_widget` | `^0.10.0` | Guardar el snapshot en App Group / SharedPreferences, `updateWidget`, `initiallyLaunchedFromHomeWidget` + `widgetClicked` (links desde el widget), `getInstalledWidgets` (presencia) | Estándar de facto; soporta UIScene desde 0.9.3 (la app usa `FlutterSceneDelegate`), AGP 9 desde 0.9.2, clicks de Android vía WorkManager desde 0.8.1. Resuelve también los links: no hace falta `app_links`. |
| `workmanager` | `^0.10.10` | Refresco en segundo plano: Android periódico (WorkManager), iOS `BGAppRefreshTask` | El único mantenido con callback Dart en ambas plataformas; 0.10.10 corrige el arranque lento del isolate en Android 16. Pide Flutter ≥ 3.38 (tenemos 3.47.5). |
| ~~`app_links`~~ | — | — | Ya entra transitivo por `supabase_flutter` (7.1.1) para `porty://login-callback`. Los toques del widget llegan por el canal de `home_widget`, con esquema propio, así que no hay que tocar `app_links` ni arriesgar los links de auth. |

El avatar es un **asset estático** (PNG exportado una vez desde `PortyAvatar` con cara normal, claro y oscuro), no `renderFlutterWidget` en tiempo de ejecución: no necesita la app abierta, no escribe imágenes en cada refresco y el widget se ve igual desde la galería sin datos.

### 3.2 Snapshot compartido (schema v1)

- **iOS:** `UserDefaults(suiteName: "group.com.portyassistant.app")`, clave `porty_widget_snapshot`.
- **Android:** el `SharedPreferences` de `home_widget` (`HomeWidgetPreferences`), misma clave. Es almacenamiento privado de la app; se excluye del backup (§5.2).
- Valor: **un único string JSON** (una sola escritura atómica; el nativo nunca lee claves sueltas a medio escribir).
- **Nunca** contiene: tokens, user id, email, cantidades, precios por posición ni la lista de tenencias. Con `amounts_hidden: true` no contiene montos ni ticker (no "ocultos": ausentes).

```jsonc
{
  "v": 1,                          // int. El nativo ignora (muestra estado "abrí Porty") cualquier v != 1
  "state": "ready",                // "signed_out" | "no_portfolio" | "ready"
  "lang": "es",                    // "es" | "en" = AppLanguage.code al escribir
  "written_at": 1793980800000,     // int, epoch ms UTC: cuándo se escribió
  "data_as_of": 1793980500000,     // int, epoch ms UTC: cuándo se trajeron los precios (base de "actualizado hace X")
  "stale_at": 1794020400000,       // int, epoch ms UTC: desde ahí se dibuja el estado "datos viejos" (ver regla abajo)
  "period": "today",               // "today" | "last_close"
  "amounts_hidden": false,
  "currency": "USD",               // v1 siempre USD, igual que el número principal de la Home
  "total_text": "$12,345.67",      // ya formateado con AppNumberFormat.currency(); ausente si amounts_hidden
  "change_text": "+$123.45",       // AppNumberFormat.signedMoney; ausente si amounts_hidden
  "change_pct_text": "+1.0%",      // AppNumberFormat.percent; siempre presente en ready
  "direction": "up",               // "up" | "down" | "flat" (|Δ%| < 0,3) → color
  "phrase": "Tu cartera sube hoy; NVDA sumó más.",   // plantilla aprobada por compliance, ya resuelta
  "phrase_stale": "Datos desactualizados. Abrí Porty para actualizarlos.",
  "a11y_value": "Valor de la cartera 12.345,67 dólares, sube 1,0 % hoy",  // armado desde el estado YA ocultado
  "labels": {
    "period_today": "Hoy",
    "period_last_close": "Último cierre",
    "stale_date": "al 3 nov",                 // fecha de data_as_of, formateada en lang
    "updated_now": "Actualizado recién",
    "updated_min": "Actualizado hace {n} min",
    "updated_h": "Actualizado hace {n} h",
    "updated_d": "Actualizado hace {n} d",
    "hidden_amount": "••••",
    "hidden_a11y": "Montos ocultos",
    "message": null                           // texto del estado signed_out / no_portfolio
  },
  "questions": [                              // solo en ready; exactamente estos ids en v1
    {"id": "today", "text": "¿Cómo viene mi cartera hoy?"},
    {"id": "top_mover", "text": "¿Qué fue lo que más se movió?"}
  ]
}
```

Estados:
- `signed_out`: solo `v`, `state`, `lang`, `written_at`, `labels.message` = "Entrá a Porty para ver tu cartera acá." / "Sign in to Porty to see your portfolio here.". Sin números, frase ni preguntas.
- `no_portfolio`: ídem con "Cargá tu cartera y la vas a ver acá." / "Add your portfolio to see it here.".
- **Sin snapshot** (nunca abrió la app, o `v` desconocido): el nativo usa su único texto propio, localizado por el idioma del sistema (`Localizable.strings` es/en en iOS; `values/` y `values-es/` en Android) = mensaje de `signed_out`.

**Regla de `stale_at`** (la calcula Flutter; el nativo solo compara `now >= stale_at`):
- `stale_at = min(data_as_of + 24 h, próxima medianoche local)` si `period == today` (después de medianoche "hoy" sería falso).
- `stale_at = data_as_of + 24 h` si `period == last_close`.
- Estado viejo: números atenuados, etiqueta `labels.stale_date` en lugar de "Hoy"/"Último cierre", `phrase_stale` en lugar de `phrase`, preguntas igual visibles.

**`period` y variación del día** (función pura nueva `PortfolioDayMove.compute`, §4):
- Se calcula sobre el **mismo historial diario** que dibuja el gráfico de la Home (`_buildPortfolioSeries`, extraído a función pura): variación = `PortfolioPeriodUtils.periodPnlFromHistory(últimos 2 puntos)` (la plata nueva no cuenta como ganancia).
- `period = today` si la fecha del último punto es hoy (local); si no, `last_close`. No hay calendario de mercado: cripto 24/7 + acciones queda como el historial lo arme (igual que la Home).
- Mayor aporte: el ticker con mayor `cantidad × (cierre último − cierre anterior)` en la dirección del movimiento; `null` si falta algún dato o hay empate. Solo se usa si `amounts_hidden == false` y `period == today`.
- `total_text` = `summary.totalValue` de la Home.

**Frase** (`WidgetPhrase.resolve`, textos en `es-ES.json`/`en-US.json` con las **plantillas aprobadas por compliance**, sección 1 de la revisión, tal cual):
| Condición | Plantilla |
|---|---|
| `period == last_close` | "último cierre" (sin dirección) |
| `period == today`, \|Δ%\| < 0,3 | "movimiento chico" |
| `today`, sube/baja, con mayor aporte y montos visibles | "sube/baja con {TICKER}" |
| `today`, sube/baja, sin mayor aporte **o** montos ocultos | "sube/baja sin ese dato" |
| siempre en `phrase_stale` | "datos viejos" |

### 3.3 Cuándo se escribe

Lo produce `homeWidgetSyncProvider` (Provider a mano, vivo mientras está montado `AppShell`), con un debounce de 500 ms, y después llama `HomeWidget.updateWidget` (iOS kind `PortyWidget`; Android `PortySmallWidgetProvider` y `PortyMediumWidgetProvider`):

| Disparador | Qué escribe |
|---|---|
| `homeProvider` cambia `summary` o `history` con datos buenos (abrir la app, volver a primer plano, pull to refresh, alta/baja/edición de posiciones, sync de bróker) | `ready` o `no_portfolio`. **No** escribe si la carga falló (se queda el último bueno) ni con `fromCache` (no pisa datos de un refresco en segundo plano más nuevos con el caché de la Home). |
| Cambia "Ocultar montos en el widget" | Reescribe en el acto desde el último estado (sin red). |
| Cambia el idioma de la app | Reescribe en el acto. |
| `onAuthStateChange` = `signedOut` (cerrar sesión y borrar cuenta, que termina en signOut) | Primero borra `widget_owner_uid` (§3.5), después escribe `signed_out`. Borra frase, fecha y números: todo el JSON se reemplaza. |
| Refresco en segundo plano (§3.5) | `ready` con precios nuevos. |

Ajuste: `widget_amounts_hidden` (bool, default `false`) en el `SharedPreferences` privado de la app (`sharedPreferencesProvider`), no en el compartido.

### 3.4 Links del widget

Esquema propio **`porty-widget`** (distinto de `porty://`, que procesa `supabase_flutter` para auth). Todos llevan `homeWidget` (lo exige `home_widget` en iOS para entregarlo por su canal; a verificar con 0.10):

| Toque | URL |
|---|---|
| Fondo del chico / fondo del mediano (ready) | `porty-widget://open?homeWidget&target=chat&size=small\|medium` |
| Pregunta | `porty-widget://open?homeWidget&target=question&q=today\|top_mover&size=medium` |
| Estado `no_portfolio` | `porty-widget://open?homeWidget&target=add_portfolio&size=…` |
| Estado `signed_out` / sin snapshot | `porty-widget://open?homeWidget&target=app&size=…` |

El nativo agrega además `age=<min>` (minutos desde `data_as_of`) para `data_age_min`. Nada de texto libre: `WidgetLaunch.parse(Uri)` acepta solo `target` ∈ {chat, question, add_portfolio, app} y `q` ∈ {today, top_mover}; un `q` desconocido → abre el chat vacío; cualquier otro esquema/host → ignora.

**Sin ruta nueva de go_router.** El deep linking de Flutter está apagado (`FlutterDeepLinkingEnabled=false`, `flutter_deeplinking_enabled=false`) y debe seguir así. `WidgetLaunchListener` (mismo patrón que `PushOpenListener`, montado en `AppShell`) recibe el `Uri` y navega por nombre:
- `question` → `GotoAssistant(initialQuestion: <texto traducido del id en el idioma activo>, origin: AssistantQuestionOrigin.widget(id))`.
- `chat` → `context.goNamed(AssistantRouter.routeName)`.
- `add_portfolio` → `GotoAddPosition()`; `app` → nada (queda donde abra).

**Una sola vez:** el launch inicial se atiende una vez por proceso (flag estático, como push) y `WidgetLaunchDeduper` descarta un `widgetClicked` con la misma URL dentro de 2 s del inicial (iOS puede entregar ambos). El chat ya garantiza un envío por `AssistantQuestionRequest` (`askFromOutside` + `didUpdateWidget` por identidad).

**Cuota:** la pregunta entra por `askFromOutside` → `submitMessage` normal: el servidor (`ai-chat`) descuenta 1 consulta; con la cuota en cero, `_applyServerLimit` abre el paywall de siempre con `PaywallSource.quotaZero`. No hay paywall ni `PaywallSource` nuevos.

**Sin sesión:** el router manda a login y `AppShell` no está montado, así que nadie consume el link. Además el widget en `signed_out` nunca dibuja preguntas, así que no puede emitir `target=question`. Si después del login el launch inicial sigue pendiente, `WidgetLaunchListener` solo actúa si `target ∈ {chat, app}`; una `question` que llega antes del login se descarta (no se manda una pregunta que el usuario tocó en otro estado).

### 3.5 Refresco en segundo plano

**No usa la sesión de Supabase.** Motivo: `supabase_flutter` rota el refresh token; un segundo cliente en otro isolate que refresque mientras el de la UI guarda uno más viejo puede disparar la detección de reutilización y cerrar la sesión del usuario. El refresco no la necesita:
- Tenencias: el caché privado de la Home (`HomePortfolioCache`, `SharedPreferences` privado, por uid) ya guarda los lotes con ticker, cantidad, precio y fecha de compra.
- Uid: `widget_owner_uid` en el `SharedPreferences` **privado** (lo escribe el sync al escribir `ready`; lo borra el signOut). No va al almacenamiento compartido.
- Precios: `YahooQuoteRemoteDataSource` va directo a Yahoo, sin JWT. En el isolate de fondo se construye con `cacheTtl` explícito (si no, lee `dotenv`, que no está cargado).

Callback `widgetBackgroundDispatcher` (`@pragma('vm:entry-point')`, top-level): lee uid → si no hay, termina. Lee caché → si no hay lotes, termina. Trae velas diarias por ticker único (si falla un ticker, usa el `currentPrice` del caché; si fallan todos, no escribe) → `PortfolioCalculator.valuate` + `PortfolioSeriesBuilder` + `PortfolioDayMove` + `WidgetSnapshotBuilder` → **relee el uid y solo escribe si sigue igual** (evita resucitar datos después de un signOut) → `updateWidget`. No escribe el caché de la Home ni loguea eventos (sin sesión).

| | Android | iOS |
|---|---|---|
| Mecanismo | `Workmanager().registerPeriodicTask('porty_widget_refresh', frequency: 30 min, constraints: NetworkType.connected, existingWorkPolicy: keep)` | `registerPeriodicTask` sobre `BGAppRefreshTask` (identificador `com.portyassistant.app.widget_refresh` en `BGTaskSchedulerPermittedIdentifiers`) |
| Frecuencia | Cada 30 min como mucho (Doze la estira) | La decide iOS según el uso; puede ser pocas veces por día o ninguna. Sin garantía. |
| Se registra | Al escribir el primer `ready` si hay algún widget instalado (`getInstalledWidgets`); se cancela en signOut y cuando no queda ningún widget | Ídem |
| Límite de trabajo | ≤ 25 s, timeouts de Dio de 6 s | ≤ 25 s (iOS corta a ~30 s) |

La extensión de iOS no hace red: su timeline tiene entradas cada 15 min durante 6 h más una en `stale_at`, con política `.atEnd`. Eso actualiza "hace X" y el paso a "datos viejos" dentro del presupuesto de WidgetKit sin despertar la app.

### 3.6 Backend

Nada. Única verificación (backend-dev, solo lectura): que `product_events` acepte nombres nuevos sin lista cerrada (`20261026000000_product_events.sql`). Si hay un check de nombres, migración nueva idempotente que sume los 5 eventos de §6.

## 4. Tareas por dueño

Dos dueños nunca comparten un archivo. "Flutter-dev (nativo)" es una **segunda instancia** de porty-flutter-dev con archivos disjuntos de la primera.

### porty-flutter-dev (Dart) — arranca ya

| Archivo | Qué |
|---|---|
| `pubspec.yaml` | `home_widget: ^0.10.0`, `workmanager: ^0.10.10` |
| `lib/main.dart` (tiene cambios del rename sin commitear: editar sin revertirlos) | `HomeWidget.setAppGroupId('group.com.portyassistant.app')`; `Workmanager().initialize(widgetBackgroundDispatcher)` |
| `lib/domain/utils/portfolio_series_builder.dart` (nuevo) + `lib/infraestructure/repositories/portfolio_analytics_repository_impl.dart` | Extraer `_buildPortfolioSeries`/`_seriesStart` a función pura `build(positions, candlesByTicker)`; el repo la usa (sin cambio de resultados) |
| `lib/domain/utils/portfolio_day_move.dart` (nuevo) | `PortfolioDayMove.compute(...)` → `{absolute, percent, period, asOfDay, topContributor}` |
| `lib/features/home_widget/domain/widget_snapshot.dart` | Modelo a mano + `toJson` del schema v1 |
| `lib/features/home_widget/domain/widget_snapshot_builder.dart` | Pura: summary + dayMove + ajuste + idioma + now → `WidgetSnapshot` (calcula `stale_at`, oculta montos y ticker, arma `a11y_value`) |
| `lib/features/home_widget/domain/widget_phrase.dart` | Elige plantilla (tabla §3.2) |
| `lib/features/home_widget/domain/widget_launch.dart` | `WidgetLaunch.parse`, `WidgetQuestionId`, `WidgetLaunchDeduper` |
| `lib/features/home_widget/data/home_widget_store.dart` | Envoltorio inyectable de `home_widget` (save, update, installed, launch stream). Tests con fake. |
| `lib/features/home_widget/data/widget_background_refresh.dart` | Dispatcher + registro/cancelación de la tarea |
| `lib/features/home_widget/providers/home_widget_sync_provider.dart`, `widget_settings_provider.dart` | Disparadores de §3.3; ajuste de montos |
| `lib/features/home_widget/view/widget_launch_listener.dart` | §3.4 + `widget_opened` |
| `lib/features/home_widget/view/widget_amounts_tile.dart` + `lib/presentation/flows/settings/...` (pantalla de Ajustes) | Switch "Ocultar montos en el widget" + texto de compliance (sección 5) + `widget_amounts_toggled` |
| `lib/features/product_events/data/product_events.dart` | Los 5 eventos de §6 (primero, para desbloquear a assistant-dev) |
| `lib/features/product_events/view/app_open_tracker.dart` (nuevo) | `app_opened{source}` |
| `lib/config/navigation/app_shell.dart` | Montar `WidgetLaunchListener`, `AppOpenTracker` y leer `homeWidgetSyncProvider` |
| `lib/features/notifications/view/push_open_listener.dart` | Marcar `source=push` en `appOpenSourceProvider` |
| `assets/translations/es-ES.json`, `en-US.json` | Plantillas aprobadas, labels del snapshot, preguntas, ajuste, gallery name/description (para que nativo copie) |
| `test/...` | §8 |
| `test/fixtures/home_widget/*.json` | Un JSON por estado (ready es/en, oculto, last_close, signed_out, no_portfolio): **lo usa el nativo** como datos de prueba |

Pendiente de OK de producto (pregunta abierta 1): línea "Hoy +$X (+Y %)" en `portfolio_hero_section.dart` desde `PortfolioDayMove`.

### porty-flutter-dev (nativo) — en paralelo, después del paso manual 2

Trabaja contra los fixtures de §3.2 (si todavía no existen, contra el ejemplo de esta spec).

| Archivo | Qué |
|---|---|
| `ios/PortyWidget/PortyWidget.swift`, `PortyWidgetViews.swift`, `SnapshotStore.swift` | `TimelineProvider` (§3.5), vistas `systemSmall`/`systemMedium`, decodificación con fallback a "sin snapshot" |
| `ios/PortyWidget/Assets.xcassets`, `Info.plist`, `PortyWidget.entitlements`, `es.lproj`/`en.lproj/Localizable.strings` | Colores con variante oscura, avatar PNG, fuente Plus Jakarta Sans en `UIAppFonts` de la extensión, nombre/descr. de galería |
| `ios/Runner/Info.plist` | Esquema `porty-widget` en `CFBundleURLTypes`; `BGTaskSchedulerPermittedIdentifiers`; `UIBackgroundModes: fetch` |
| `ios/Runner/AppDelegate.swift` | Registro de la tarea de workmanager para iOS |
| `ios/Runner/Runner.entitlements` | App Group (si Xcode no lo dejó escrito en el paso manual) |
| `android/app/src/main/kotlin/com/portfolioassistant/app/widget/PortySmallWidgetProvider.kt`, `PortyMediumWidgetProvider.kt`, `PortyWidgetRenderer.kt` | `HomeWidgetProvider` + RemoteViews; clicks con `HomeWidgetLaunchIntent.getActivity(..., MainActivity::class.java, uri)` |
| `android/app/src/main/res/layout/porty_widget_small.xml`, `porty_widget_medium.xml`; `res/xml/porty_widget_small_info.xml`, `porty_widget_medium_info.xml` (`updatePeriodMillis=0`, `previewLayout` con datos ficticios, `description`) | Layouts y metadatos |
| `res/values/`, `values-es/`, `values-night/` (`widget_strings.xml`, `widget_colors.xml`), `res/drawable-nodpi/porty_widget_avatar*.png`, `res/font/` | Textos de galería y fallback, colores, avatar |
| `android/app/src/main/AndroidManifest.xml` (cambios del rename sin commitear: no revertir) | Dos `<receiver>`; `dataExtractionRules`/`fullBackupContent` que excluyen `HomeWidgetPreferences` |
| `test/tools/export_widget_avatar_test.dart` | Exporta la cara normal de `PortyAvatar` (claro/oscuro, 1x-3x) a los dos destinos nativos; se corre a mano y se commitean los PNG |

Reglas visuales: paleta y tokens de `DESIGN.md` y `lib/presentation/base/theme/theme_extension.dart` (claro cálido / oscuro, mismo color de variación que `colors.pnlColor`), cifras tabulares (`.monospacedDigit()` / `fontFeatureSettings="tnum"`), sin número gigante, `containerBackground` en iOS 17+ con fallback a iOS 15. iOS: `.privacySensitive()` en valor, variación, % y frase; `widgetURL` en el chico; `Link` por pregunta en el mediano; `isPreview`/`placeholder` con **datos ficticios fijos**; VoiceOver: un solo elemento con `a11y_value` (con montos ocultos dice `labels.hidden_a11y`, nunca lee números). Android: **RemoteViews, no Glance** (sin Compose ni compilador extra en un build con AGP 9 y rename en curso; dos layouts fijos alcanzan; `home_widget` lo soporta de base); `contentDescription` con `a11y_value`; dos providers fijos (2×2 y 4×2) en vez de un layout responsivo, así `size` sale gratis.

### porty-assistant-dev — en paralelo (fase A)

| Archivo | Qué |
|---|---|
| `lib/features/assistant/states/assistant_state.dart` | `AssistantQuestionOrigin` (sealed; `widget(String questionId)`) y campo **opcional** `origin` en `AssistantQuestionRequest` |
| `lib/features/assistant/nav/assistant_nav.dart` | `GotoAssistant({..., origin})` opcional |
| `lib/features/assistant/providers/assistant_provider.dart` | `askFromOutside(..., origin)`; al cerrar ese turno, `widget_question_result{question_id, result}` con `answered` \| `quota` \| `paywall` \| `failed` |
| `test/features/assistant/...` | Un envío por request; evento por rama |

Verificar (sin tocar prompt) que `today`/`top_mover` en fin de semana responden con la fecha real del dato (nota de compliance §2). Si hace falta tocar prompt o reglas: hash del allowlist + deploy de `ai-chat` + evals → OK del usuario.

Dependencia: usa `ProductEvent.widgetQuestionResult` (lo agrega flutter-dev Dart primero, es una línea). Flutter-dev Dart llama `GotoAssistant(origin: ...)` cuando assistant avise; hasta entonces, sin `origin`.

### porty-backend-dev

Solo la verificación de §3.6. Sin tareas si no hay check de nombres.

### Orden y paralelismo

```
Paso manual 1-2 (usuario) ──► flutter-dev nativo
flutter-dev Dart (product_events primero) ──► assistant-dev ──► flutter-dev Dart conecta origin
backend: verificación de 5 min, cuando sea
```
Dart, nativo y assistant corren a la vez: los conjuntos de archivos no se tocan. El único contrato compartido es el JSON de §3.2 y las URLs de §3.4.

### Pasos manuales del usuario

1. **Apple Developer:** crear App Group `group.com.portyassistant.app`; habilitarlo en el App ID `com.portyassistant.app`; crear App ID `com.portyassistant.app.PortyWidget` con App Groups; regenerar perfiles.
2. **Xcode:** File ▸ New ▸ Target ▸ Widget Extension `PortyWidget` (sin Live Activity ni intent de configuración), bundle id `com.portyassistant.app.PortyWidget`, deployment iOS 15.0; capability App Groups en Runner y PortyWidget; Background Modes ▸ Background fetch en Runner; firma con el equipo. Antes de commitear `project.pbxproj`, revisar que siguen los cambios del rename.
3. Probar en dispositivo real lo de §9 (lista).
4. Sumar la frase de privacidad de compliance (sección 5) a la política y revisar las etiquetas de privacidad de las tiendas.
5. Si assistant-dev tiene que tocar el prompt: OK para evals y deploy de `ai-chat`.

## 5. Detalles por plataforma (resumen de decisiones)

5.1 **iOS:** un widget `PortyWidget` con `.supportedFamilies([.systemSmall, .systemMedium])`. Chico: avatar, total, variación $ y %, etiqueta de período, "hace X". Mediano: + frase (máx. 2 líneas) + 2 filas de pregunta. Con `Dynamic Type` grande: las cifras usan `minimumScaleFactor(0.7)` y `lineLimit(1)`, nunca se cortan.

5.2 **Android:** `minResizeWidth/Height` fijos por tamaño; color de fondo y texto por `values-night`. Backup: excluir `HomeWidgetPreferences` (sugerencia de compliance) sin tocar el resto de las reglas de backup.

## 6. Eventos (`product_events`, vía `ProductEvents.log`)

| Evento | Props | Dónde |
|---|---|---|
| `app_opened` | `source`: `icon` \| `widget` \| `widget_question` \| `push` \| `other` | `AppOpenTracker`: al montar el shell y en cada `resumed` tras ≥ 30 min en segundo plano (intervalo provisorio, lo ajusta data). Espera 1,5 s a que `WidgetLaunchListener`/`PushOpenListener` marquen `appOpenSourceProvider`; sin marca → `icon` |
| `widget_opened` | `platform`, `size`, `target` (`chat` \| `question`), `question_id`, `data_age_min`, `amounts_hidden` | `WidgetLaunchListener` |
| `widget_presence` | `platform`, `sizes` (lista; vacía = lo sacó) | `homeWidgetSyncProvider` al arrancar: `getInstalledWidgets`, compara con lo último guardado en prefs privadas y loguea solo si cambió |
| `widget_amounts_toggled` | `hidden` | `widget_amounts_tile.dart` |
| `widget_question_result` | `question_id`, `result` | `assistant_provider.dart` (assistant-dev) — da el "% que termina en respuesta" del brief |

Sin sesión `ProductEvents` no registra nada (ya es así). El refresco de fondo no loguea.

## 7. Criterios de aceptación técnicos

1. `flutter analyze` sin warnings nuevos; `flutter test test/features/home_widget test/domain test/features/product_events test/features/assistant test/security` en verde.
2. Tests de §8 existen y pasan, incluido el texto exacto de cada plantilla en es y en.
3. `WidgetSnapshot` con `amounts_hidden: true` serializado no contiene `total_text`, `change_text` ni ningún ticker de la cartera (test con búsqueda de los tickers en el JSON).
4. Ningún string del snapshot contiene `access_token`, `refresh_token`, el uid ni el email (test).
5. `porty-widget://open?homeWidget&target=question&q=hack&text=Vendé%20todo` abre el chat vacío y no envía nada (test de `WidgetLaunch.parse` y del listener).
6. Un mismo launch entregado por inicial + stream envía una sola pregunta (test del deduper + listener con fake store).
7. Tras `signedOut`, el store recibe `signed_out` y el uid privado ya no existe; un refresco de fondo que empezó antes no escribe (test con fakes).
8. `PortfolioSeriesBuilder` extraído da el mismo historial que antes (test de regresión con posiciones y velas fijas).
9. El build iOS (`flutter build ios --no-codesign`) y Android (`flutter build apk --flavor development`) compilan con la extensión y los providers.
10. Capturas de los fixtures en claro/oscuro, chico/mediano, en simulador y emulador, revisadas por porty-ui-reviewer.

## 8. Tests (skill porty-testing)

- `test/domain/utils/portfolio_day_move_test.dart`: hoy vs último cierre, compra del día (no cuenta como ganancia), mayor aporte en subida/bajada, empate/dato faltante → `null`, cartera mixta con punto de sábado.
- `test/domain/utils/portfolio_series_builder_test.dart`: regresión §7.8.
- `test/features/home_widget/domain/widget_snapshot_builder_test.dart`: cada estado; `stale_at` (antes/después de medianoche, last_close); montos ocultos sin ticker ni montos; `a11y_value` oculto; es y en.
- `test/features/home_widget/domain/widget_phrase_test.dart`: texto exacto de cada plantilla aprobada, es/en; `last_close` y datos viejos nunca dicen "hoy"/"today" con dirección; regex que prohíbe verbos de acción, valoración y causas (lista de compliance) en ambos idiomas.
- `test/features/home_widget/domain/widget_launch_test.dart`: ids válidos, desconocidos, esquema/host ajenos, sin `homeWidget`, deduper.
- `test/features/home_widget/providers/home_widget_sync_provider_test.dart`: disparadores de §3.3 con fake store y fake `ProductEvents` (patrón `first_portfolio_watcher_test.dart`); no escribe con `fromCache` ni con carga fallida; `widget_presence` solo al cambiar.
- `test/features/home_widget/data/widget_background_refresh_test.dart`: lógica del dispatcher separada del plugin (función `refreshOnce(deps)`): sin uid, sin lotes, ticker caído usa caché, todos caídos no escribe, uid cambiado no escribe.
- `test/features/home_widget/view/widget_launch_listener_test.dart` y `widget_amounts_tile_test.dart` (evento + reescritura inmediata).
- `test/features/product_events/app_open_tracker_test.dart`: fuentes e intervalo.
- assistant-dev: request con `origin` → un envío y `widget_question_result` por rama (answered, quota, paywall, failed).
- Nativo: sin tests automáticos en v1; verificación con fixtures en simulador/emulador (§7.10).

## 9. Riesgos, decisiones y lo que no se prueba sin dispositivo

**Decisiones y alternativas descartadas**
- Refresco de fondo **sin sesión** (caché + Yahoo directo) en vez de reusar Supabase en otro isolate (riesgo de cerrar la sesión por rotación del refresh token) o de un endpoint de servidor con token del widget (backend nuevo, revocación, más superficie). Costo: si la cartera cambió en otro dispositivo o por un sync de bróker, el widget usa las tenencias de la última apertura con precios nuevos hasta que se abra la app.
- Frase y formatos en Flutter, no en nativo: una sola implementación testeable, misma salida que la Home.
- RemoteViews en vez de Glance; asset estático en vez de `renderFlutterWidget`; esquema `porty-widget` en vez de reusar `porty://`.

**Preguntas abiertas**
1. **La Home hoy no muestra variación del día** (el hero muestra la del rango elegido). El brief pide "el mismo número que la Home". Recomiendo sumar a la Home la línea "Hoy +$X (+Y %)" con el mismo `PortfolioDayMove` (necesita OK de product-owner/ui). Sin eso, el valor total coincide con la Home y la variación sale del mismo historial del gráfico, pero no está a la vista en la app.
2. Intervalo mínimo de `app_opened` (puse 30 min): lo confirma porty-data-analyst.

**A verificar (no se pudo confirmar antes de escribir)**
- Que `home_widget` 0.10 entregue el link en iOS con UIScene solo con `homeWidget` en la query y con un esquema registrado propio; y que en Android no haya que agregar `intent-filter` (usa intent explícito).
- Que `workmanager` 0.10.x siga soportando `registerPeriodicTask` en iOS (BGAppRefreshTask) y cómo se registra en `AppDelegate` con `FlutterImplicitEngineDelegate`. Si no, iOS queda solo con "al abrir la app" + timeline (lo aceptable del brief: "iOS con presupuesto diario").
- Nombre calificado de los providers Android para `updateWidget` con flavors (`applicationIdSuffix`): el namespace Kotlin es `com.portfolioassistant.app`, el applicationId `com.portyassistant.app(.dev|.staging)`.
- Fuente empaquetada en RemoteViews (`android:fontFamily="@font/…"`): si no funciona en algún API, cae a sans del sistema con cifras tabulares.
- Que `product_events` no tenga lista cerrada de nombres (§3.6).
- Que el isolate de fondo pueda leer `HomePortfolioCache` (SharedPreferences privado) sin inicializar el resto de la app.

**Solo en dispositivo real**
- `.privacySensitive()` con el iPhone bloqueado y en StandBy (compliance lo pide explícito).
- Frecuencia real del refresco de fondo (iOS a criterio del sistema; Android con Doze/ahorro de batería y fabricantes que matan WorkManager).
- Cold start desde el widget con y sin sesión, y que la pregunta salga una sola vez.
- VoiceOver/TalkBack leyendo `a11y_value` y "Montos ocultos".
- Galería de widgets con datos ficticios y textos en el idioma del sistema.
- Que el signOut limpie el widget al instante con la app en segundo plano después.

**Necesita OK del usuario:** pasos manuales 1–2 y 4; deploy de `ai-chat` y evals solo si assistant-dev tiene que tocar el prompt. No hay migración ni deploy de Supabase previstos.

## Decisión del usuario (2026-11-05)

- **Sí** se suma una línea "Hoy" en la Home, con el mismo cálculo de variación del día que usa el widget (tarea de porty-flutter-dev).

## Ampliación v1: noticias y resultados

**Autor:** porty-architect · 2026-11-05 · Implementa `docs/specs/home-widget-product.md` §"Ampliación" (A1–A9), las decisiones del usuario de la ampliación y la "Revisión de compliance: ampliación". Todo lo anterior de esta spec sigue vigente salvo donde esta sección lo dice. Textos: **textos aprobados por compliance (sección ampliación)**, tal cual; no se inventa ninguno.

### Am.1 Objetivo

El widget dice *qué pasó* con lo que tenés: noticias (últimas 48 h) y fechas **estimadas** de resultados (7 días) de tus 5 posiciones de más peso, elegidas sin IA en el teléfono. Mediano: el ítem más importante en lugar de la frase. Grande nuevo (iOS `systemLarge`, Android 4×4): encabezado + frase + hasta 4 ítems + 2 preguntas. Un toque abre la hoja "Novedades de tu cartera" en la app. Free/Premium ven un aviso del plan siguiente. **Listo** = criterios Am.8 en verde.

### Am.2 Fuera de alcance

Cripto; traducir titulares; resumen o imagen del artículo; fechas de resultados "confirmadas" y horario bmo/amc (la fuente v2 no los tiene); Finnhub (ver Am.3); IA de cualquier tipo; refresco de noticias en segundo plano (no hay sesión); cambios al prompt o al catálogo del chat (no hace falta deploy de `ai-chat`).

### Am.3 Fuente de datos (cambio respecto del brief; confirmado por el usuario 2026-11-05)

Compliance bloqueó Finnhub (términos: uso personal, sin redistribución). El widget usa **solo el camino v2**, el mismo que el chat con `app_config.news_provider = v2`:

| Dato | Cliente (ya existe, import de solo lectura) | Edge function | Gating en el servidor (código actual) |
|---|---|---|---|
| Noticias | `GdeltHeadlinesRepositoryImpl.getRecentNews(ticker, from:, to:)` (agrupa hasta 10 tickers en **una** llamada) | `headlines` | `newsAllowed` → `news_data_allowed`: Gold, cortesía, o **Premium con el ticker en `positions`** (migración `20261105100500_held_news.sql`) |
| Resultados (fecha estimada) | `SecEarningsFetcher` (`lib/features/assistant/data/market/sec_market_fetchers.dart`), campo `next_report.date` (siempre `estimated: true`) | `sec` (`endpoint=earnings`) | `gold_data_allowed`: solo Gold (= `PlanFeature.earnings`) |

- Si `news_provider` no es `v2` (vuelta atrás): el widget no trae nada (sin ítems ni avisos; frase como v1). Se lee con `NewsProviderConfig` (`assistant/data/market/news_provider.dart`) sin editarlo.
- Compliance dice que hoy prod responde 403 a Premium: el código de `headlines` ya admite Premium+tenencia, así que lo más probable es que falte `db push` de `20261105100500_held_news.sql` y/o deploy de `headlines`. **Verificación de solo lectura antes de integrar** (devops o el usuario). Sin eso, Premium ve cero ítems (falla cerrado, nunca error).
- Tickers: se mandan **tal como están en `positions`** (el RPC compara sin normalizar: `.BA`, etc.).
- Costo por apertura (con el freno de 30 min de Am.4.4): Free 0 (fase 1) / 1 llamada de conteo (fase 2); Premium 1 `headlines` (+1 conteo de resultados en fase 2); Gold 1 `headlines` + hasta 5 `sec` con caché local de 12 h por ticker (en la práctica ~0). **Finnhub: 0. OpenAI: 0.** Límites del servidor: `headlines` 30/min por usuario, caché de 30 min compartida por clave.

### Am.4 Contrato de datos

#### Am.4.1 Snapshot: sigue `v: 1` con campos opcionales

Extensión y app viajan en el mismo binario, así que no existe "widget nativo viejo + app nueva". El único cruce es el **JSON guardado por la versión anterior** que lee el nativo nuevo antes de la primera apertura: como los campos nuevos son opcionales, el nativo lo dibuja como v1 (sin sección de novedades). Regla: **ausente = no hay** (nunca error); `v` sube a 2 solo ante un cambio que rompa campos existentes. Un nativo v1 que leyera estos campos los ignora (ya se probó: decodificación tolerante).

Campos nuevos, solo en `state: ready` (en `signed_out`/`no_portfolio` no van):

```jsonc
{
  // ...todo lo de §3.2...
  "items_section": true,            // bool. false = no se dibuja la sección (Free sin aviso, solo cripto, v2 apagado). Grande: agranda las preguntas
  "items_checked_at": 1793980800000,// epoch ms: última consulta OK a la fuente. Sin ítems y now > checked_at+48h → label "all_expired"
  "plan_until": 1794500000000,      // epoch ms | null. Vencimiento conocido del plan; now >= plan_until → el nativo oculta items y teaser y muestra "all_expired"
  "items": [                        // 0..4 ya ordenados por A1; el teaser NO va acá
    {
      "id": "9f2c41ab",             // 8 hex, FNV-1a 32 de "news|<TICKER>|<url>" o "earnings|<TICKER>|<yyyy-mm-dd>"; opaco
      "kind": "news",
      "ticker": "NVDA",
      "source": "reuters.com",
      "headline": "Nvidia unveils ...",   // tal cual, idioma original
      "published_at": 1793970000000,      // el nativo arma "hace X" con labels.age_*
      "expires_at": 1794142800000         // published_at + 48 h
    },
    {
      "id": "51c0e7d2",
      "kind": "earnings",
      "ticker": "AAPL",
      "segments": [                       // el nativo usa el último con from <= now; los arma Flutter hasta expires_at
        {"from": 1793980800000, "text": "AAPL · fecha estimada de resultados: mañana"},
        {"from": 1794020400000, "text": "AAPL · fecha estimada de resultados: hoy"}
      ],
      "a11y": "…",                        // texto aprobado para el lector, ya resuelto
      "expires_at": 1794106799000         // fin del día local de la fecha estimada
    }
  ],
  "teaser": {                       // null si no corresponde (Gold, flag apagado, sin datos para contarlo)
    "kind": "news",                 // "news" (Free→Premium) | "earnings" (Premium→Gold)
    "text": "Hay 2 noticias de tu cartera · Premium",  // ya elegido por plataforma (Android con plan; iOS sin plan)
    "count": 2                      // int | null (null en fase 1 Android: texto "sin número")
  },
  "items_labels": {
    "section": "Novedades de tu cartera",
    "empty": "No encontramos novedades de tu cartera en las últimas 48 h",
    "all_expired": "Abrí Porty para ver las novedades de tu cartera",
    "redacted": "Desbloqueá tu iPhone para ver las novedades",
    "age_min": "hace {n} min", "age_h": "hace {n} h", "age_yesterday": "ayer",
    "a11y_news": "Noticia de {ticker}, {source}, hace {age}: {headline}"
  }
}
```

- **"Ocultar montos" no toca los ítems** (decisión del usuario): ticker, titular y fuente se guardan y se muestran igual. La frase sigue sin ticker con montos ocultos (v1). `scrubStoredAmounts()` saca montos y frase y **conserva** `items`, `teaser`, `items_*`.
- iOS: ticker, titular, fuente y texto de resultados con `.privacySensitive()`; redactado muestra `items_labels.redacted` (texto aprobado). Android: sin equivalente; riesgo aceptado por el usuario (Am.9).
- Nunca en el snapshot: `url` del artículo, uid, montos por posición. La URL solo vive en la caché privada (Am.4.3).

#### Am.4.2 Selección A1 (pura): `WidgetItemsSelector.select`

Entrada: `holdings` (ticker, valor de mercado, `isCrypto`), `news: List<CompanyNewsItem>`, `earnings: List<({ticker, DateTime date})>`, `tier`, `teasersEnabled`, `teaserCounts?`, `platform`, `now` (local). Salida: `items` (≤4), `teaser`, `itemsSection`.

1. Universo: no cripto (criterio de cripto que ya usa la app; nada de listas fijas), valor > 0, top 5 por valor; empate → ticker alfabético (determinístico).
2. Resultados (solo si `allows(tier, PlanFeature.earnings)`): fecha local en `[hoy, hoy+6]`; orden fecha asc, después peso desc; máx 2.
3. Noticias (solo si `PlanMatrix.allowsNewsFor(..., held: true)` / `heldNews`): `now-48h <= publishedAt <= now+5min`; se descartan titulares que matchean el **filtro de recomendación de compliance** (lista de regex de la revisión, es/en, case-insensitive); una por ticker (la más reciente); dedupe por titular normalizado (minúsculas, sin puntuación, espacios colapsados), queda el de más peso; orden por peso desc, desempate más reciente.
4. Lista = resultados ++ noticias, truncada a 4; si hay teaser, a 3 (el teaser cuenta en los 4 del grande).
5. Teaser (solo si `teasersEnabled` para la plataforma): Free → `news` si `teaserCounts.news48 > 0` (fase 2) o, en Android fase 1, si hay ≥1 ticker elegible (texto sin número); Premium → `earnings` si `teaserCounts.earnings7 > 0` (solo fase 2: no hay texto aprobado sin número para resultados). Gold → nunca. En iOS solo con conteo (los textos aprobados de iOS llevan número).
6. Mediano (lo resuelve el nativo con el mismo JSON): primer ítem vigente; si no hay, la frase. El teaser entra en el mediano solo si no hay ítems vigentes y `teaser.count` viene de noticias de las últimas 24 h (`teaserCounts.news24 > 0`, Flutter pone `teaser.medium: true`); en fase 1 nunca.
7. `itemsSection` = (tier ve noticias **y** hay ≥1 ticker elegible) **o** hay teaser.

#### Am.4.3 Caché privada y trae-datos

`WidgetItemsRepository` (Dart, `lib/features/home_widget/data/`): con sesión, tier cargado y `news_provider == v2`, trae noticias del top 5 (`from = now-48h`, `to = mañana`, día completo para compartir caché del servidor) y, si Gold, `next_report` por ticker (caché local 12 h por ticker). Fallas: tipadas (`WidgetItemsFailure`), el provider se queda con la caché anterior (nunca error visible).

Caché privada `widget_items_cache_v1` en `sharedPreferencesProvider` (no compartida): `{uid, checked_at, tier, plan_until, items:[{id, kind, ticker, headline, source, url, published_at, date, expires_at}], teaser_counts}`. Se borra en el mismo paso que `widget_owner_uid` (signOut/borrado de cuenta). El refresco de fondo (`refreshOnce`) **no trae noticias**: relee esta caché, filtra vencidos con `now` y rearma el bloque de ítems con el mismo builder; si el uid no coincide, no incluye nada.

Freno: se vuelve a pedir si pasaron ≥ 30 min desde `checked_at`, o cambió el set del top 5, el tier o el idioma (el idioma solo reescribe, no pide).

#### Am.4.4 Links

| Toque | URL |
|---|---|
| Ítem | `porty-widget://open?homeWidget&target=news\|earnings&id=<8 hex>&rank=<1-4>&size=medium\|large&age=<min>` |
| Teaser | `porty-widget://open?homeWidget&target=teaser_news\|teaser_earnings&size=medium\|large&age=<min>` |
| Fondo del grande | igual que el mediano con `size=large` |

`WidgetLaunch.parse` suma esos `target`, `id` (`^[0-9a-f]{8}$`, si no → `app`) y `rank` (1–4, si no → null). Nada de texto. El listener:
- `news`/`earnings`: busca `id` en la caché privada, del uid actual y no vencido → abre `WidgetNewsSheet` con ese ítem arriba. No existe o venció → no hace nada (queda en la Home). No gasta consulta.
- `teaser_*` en **Android**: si el tier ya incluye la capacidad → hoja; si no → `SubscriptionPaywallSheet.show(reason: PaywallReason.plans` (news, el siguiente es Premium) `| PaywallReason.goldRequired` (earnings), `source: PaywallSource.widgetHeldNews | widgetEarnings)`.
- `teaser_*` en **iOS** (confirmado por el usuario: aviso neutro, sin plan ni pago, abre la app): abre la hoja con el estado bloqueado ("Esto viene con Premium/Gold", texto aprobado) y un botón que abre el paywall **dentro de la app** con el mismo `source`. Nunca paywall directo desde el toque.
- Antes del login: se descartan (igual que `question`).

Hoja `WidgetNewsSheet` (bottom sheet desde el listener, sin ruta de go_router): ítems vigentes de la caché, tocado arriba, separados con líneas finas; leyenda aprobada (incluye "Titulares vía GDELT Project"). Acciones: "Leer en {fuente}" → `url_launcher` modo externo con la URL de la caché; "Preguntale a Porty" → `GotoAssistant(initialQuestion: <texto aprobado news_why/earnings_when con el ticker de la caché>, origin: AssistantQuestionOrigin.widget('news_why'|'earnings_when'))`. Gasta 1 consulta por el camino normal (`ai-chat`); cuota en cero → paywall `quotaZero` de siempre. `widget_question_result` ya acepta cualquier `question_id`: **assistant-dev no tiene tareas**.

#### Am.4.5 Interruptores

`ConversionFlags.widgetTeasersAndroid = PortyRolloutFlag('widget_teasers_android')` y `widgetTeasersIos = PortyRolloutFlag('widget_teasers_ios')` en `conversion_flags.dart`, leídos al abrir con el patrón `_flagEnabled` (falla cerrado). Filas en `app_config` por migración nueva idempotente (`on conflict do nothing`), las dos en `{"percent":0,"users":[]}`: salen apagadas y el usuario las prende.

#### Am.4.6 Fase 2 (backend, conteos para avisos) — necesita OK de deploy

Sin esto: iOS sin avisos, Android Free con "Noticias de tu cartera · Premium" (sin número, solo grande), Premium sin aviso de Gold. Con esto, avisos con número y regla de 24 h del mediano.

- `GET headlines?tickers=A,B&from=YYYY-MM-DD&to=YYYY-MM-DD&count_only=1` → permitido a **cualquier plan** si **todos** los tickers están en `positions` del usuario con `quantity > 0`. Respuesta `200 {"tickers_48h": 2, "tickers_24h": 1, "as_of": "2026-11-05T13:00:00Z"}`: cantidad de tickers con ≥1 titular dentro de la ventana, tras el mismo filtro de recomendación (lista de compliance) y la misma caché que el pedido completo. Nunca devuelve titulares ni URLs. 403 `plan_required` si algún ticker no está en cartera.
- `GET sec?endpoint=earnings_count&tickers=A,B` → mismo permiso; `200 {"tickers_7d": 1, "as_of": "…"}` = tickers con `next_report` estimado en `[hoy, hoy+6]` (UTC del servidor; el cliente lo trata como aproximado).
- Ambos cuentan en `rate_limit_hit` de su bucket. El cliente llama solo si el flag de su plataforma está prendido.

#### Am.4.7 Eventos

`ProductEvent` suma `widgetItemsRendered('widget_items_rendered')` y `widgetItemAction('widget_item_action')`. `PaywallSource` suma `widgetHeldNews = 'widget_held_news'`, `widgetEarnings = 'widget_earnings'`. **Ningún evento lleva ticker, titular ni id de ítem** (test).

| Evento | Props | Dónde |
|---|---|---|
| `widget_opened` (amplía) | `size` + `large`; `target` + `news`\|`earnings`\|`teaser_news`\|`teaser_earnings`; `item_rank`, `item_age_h` (de la caché), `tier` | listener |
| `widget_items_rendered` | `size`, `news_count`, `earnings_count`, `teaser` (`none`\|`news`\|`earnings`), `tier`, `amounts_hidden`, `platform` | sync provider al abrir: lee `porty_widget_render_log` (Am.4.8) y loguea uno por tamaño con `at` posterior al último logueado (guardado en prefs privadas). Aproximación de impresiones, no impresiones |
| `widget_item_action` | `action` (`read_source`\|`ask_porty`\|`open_paywall`), `type` (`news`\|`earnings`), `from_widget` | hoja |
| `paywall_viewed` | `source` = `widget_held_news`\|`widget_earnings` | existente |
| `widget_presence` | `sizes` suma `large` | existente |

#### Am.4.8 Lo que escribe el nativo

Clave compartida `porty_widget_render_log` (string JSON, la sobrescribe el nativo en cada dibujo): `{"medium":{"at":ms,"news":1,"earnings":0,"teaser":"none"},"large":{…}}`. Solo conteos, nada de tickers. Es lo único que escribe el nativo. Se borra con el signOut (Dart).

#### Am.4.9 Vencimiento sin red (nativo)

Al dibujar, el nativo filtra `items` con `now < expires_at`, elige el segmento de resultados con `from <= now`, arma "hace X" desde `published_at` (`<60 min` → `age_min`; `<24 h` → `age_h`; si no, `age_yesterday`) y aplica `plan_until` y `items_checked_at`.
- **iOS:** el timeline suma entradas en cada `expires_at`, cada `segments[].from` y `plan_until` (además de las de §3.5), con tope de 40 entradas; `.atEnd`.
- **Android:** tras cada `onUpdate`, el renderer programa con `AlarmManager.set` (inexacto, sin permiso de alarmas exactas) un `ACTION_APPWIDGET_UPDATE` a sus tres providers en el próximo límite (`min(expires_at, segments.from, plan_until, stale_at)` futuro). No depende de WorkManager.

### Am.5 Widget grande y mediano

- **iOS:** `supportedFamilies([.systemSmall, .systemMedium, .systemLarge])` en el mismo `PortyWidget`. Grande según A3 (encabezado del chico, frase 1 línea, sección, preguntas en una fila); cada ítem con `widgetURL`/`Link` a su URL. Previews de galería con ítems ficticios (tickers y titulares inventados, fuente "Fuente Ejemplo").
- **Android:** `PortyLargeWidgetProvider` (4×4, `res/xml/porty_widget_large_info.xml` con `previewLayout` ficticio y `description` aprobada), `porty_widget_large.xml` con 4 filas fijas (`View.GONE` las sobrantes; sin `ListView`/`RemoteViewsService`: más simple y suficiente para 4). Receiver nuevo en el Manifest. `updateWidget` de Dart suma el nombre calificado del provider grande (mismo cuidado de flavors que §9).
- Mediano: primer ítem vigente en lugar de la frase (A3).
- Lector de pantalla: `a11y_news` / `a11y` del ítem; nunca montos con `amounts_hidden`.

### Am.6 Tareas por dueño

Fase 1: **Dart ∥ nativo** (dos instancias de porty-flutter-dev, archivos disjuntos). Fase 2: **backend** después. **assistant-dev: nada.**

**porty-flutter-dev (Dart)** — arranca ya; primero `widget_snapshot.dart` + fixtures nuevos (desbloquean al nativo).

| Archivo | Qué |
|---|---|
| `lib/features/home_widget/domain/widget_snapshot.dart` | Campos Am.4.1 (`WidgetItem`, `WidgetTeaser`, `itemsLabels`), `toJson` |
| `lib/features/home_widget/domain/widget_items_selector.dart` (nuevo) | A1 puro (Am.4.2) + filtro de recomendación + ids FNV |
| `lib/features/home_widget/domain/widget_snapshot_builder.dart`, `widget_texts.dart` | Arma el bloque: segmentos de resultados, `expires_at`, teaser por plataforma, labels |
| `lib/features/home_widget/domain/widget_launch.dart` | Targets, `id`, `rank` |
| `lib/features/home_widget/data/widget_items_repository.dart`, `widget_items_cache.dart` (nuevos) | Am.4.3 (+ cliente de conteos de fase 2 detrás de interfaz, con fake hasta que exista) |
| `lib/features/home_widget/data/home_widget_store.dart` | `scrubStoredAmounts` conserva ítems; provider grande en `updateWidget`; `readRenderLog`; signOut borra log |
| `lib/features/home_widget/data/widget_background_refresh.dart` | Rearma ítems desde la caché privada |
| `lib/features/home_widget/providers/home_widget_sync_provider.dart`, `widget_items_provider.dart` (nuevo) | Disparo con freno, tier, `plan_until` (si `revenueCatServiceProvider` lo da, solo lectura; si no, null), flags, `widget_items_rendered` |
| `lib/features/home_widget/view/widget_launch_listener.dart`, `widget_news_sheet.dart` (nuevo) | Am.4.4 y eventos |
| `lib/features/home_widget/view/widget_amounts_tile.dart` | Texto aprobado nuevo del ajuste |
| `lib/features/subscription/config/conversion_flags.dart`, `paywall_source.dart` | Am.4.5, Am.4.7 |
| `lib/features/product_events/data/product_events.dart` | 2 eventos |
| `assets/translations/es-ES.json`, `en-US.json` | Textos aprobados por compliance (sección ampliación) |
| `test/fixtures/home_widget/ready_items_{es,en}.json`, `ready_items_hidden.json`, `ready_items_expired.json`, `ready_teaser_{android,ios}.json`, `ready_v1_legacy.json` | Datos del nativo |
| `test/features/home_widget/**` | Am.7 |

**porty-flutter-dev (nativo)** — en paralelo, contra el ejemplo de Am.4.1 hasta que estén los fixtures.

| Archivo | Qué |
|---|---|
| `ios/PortyWidget/SnapshotStore.swift` | Decodifica opcionales, filtra vencidos, escribe render log |
| `ios/PortyWidget/PortyWidget.swift` | `systemLarge`, entradas de Am.4.9 |
| `ios/PortyWidget/PortyWidgetViews.swift` | Vista grande, ítem en el mediano, `.privacySensitive()` + `redacted`, previews ficticios |
| `ios/PortyWidget/{es,en}.lproj/Localizable.strings` | Nombre/descripción de galería del grande |
| `android/.../widget/PortyLargeWidgetProvider.kt` (nuevo), `PortyWidgetRenderer.kt`, `PortyMediumWidgetProvider.kt` | Grande, ítem en el mediano, alarma de vencimiento, render log |
| `android/app/src/main/res/layout/porty_widget_large.xml` (nuevo), `porty_widget_medium.xml`, `res/xml/porty_widget_large_info.xml` (nuevo), `values*/widget_strings.xml` | Layouts y galería |
| `android/app/src/main/AndroidManifest.xml` | Receiver del grande (no revertir cambios del rename) |

**porty-backend-dev** — fase 2, después de Dart (o cuando el usuario apruebe los avisos):
- Migración nueva idempotente con las dos filas de `app_config` (Am.4.5).
- `supabase/functions/headlines/handler.ts` + test: `count_only` (Am.4.6). `supabase/functions/sec/handler.ts` + test: `earnings_count`. El filtro de recomendación en `supabase/functions/_shared/` con la misma lista y casos que el test de Dart.
- Verificación de solo lectura: que prod tenga `news_data_allowed` con la rama Premium y `headlines` desplegada con `newsAllowed`.

Dependencias: el nativo solo depende del JSON de Am.4.1; Dart usa fake del cliente de conteos hasta que backend avise; los avisos con número se prenden recién con el deploy aprobado.

### Am.7 Tests

- `widget_items_selector_test.dart`: top 5 por peso y sin cripto; resultados primero, máx 2, misma fecha → más peso; noticias 48 h (borde 47:59/48:01), una por ticker, dedupe normalizado, orden por peso y desempate; filtro de recomendación con los ejemplos de compliance (descarta "3 stocks to buy", "Should you sell NVDA?"; **no** descarta "Analyst upgrades NVDA to Buy"); Free nunca ítems, Premium nunca resultados, Gold nunca teaser; teaser cuenta en los 4; teaser por plataforma y por flag; iOS sin conteo → sin teaser.
- `widget_snapshot_builder_test.dart`: `expires_at` (fin del día local, cambio de horario), segmentos hoy/mañana/fecha, ningún texto de resultados sin "estimad"/"estimated", `amounts_hidden` sin montos pero con ítems, ninguna `url` en el JSON, fixtures regenerados iguales.
- `home_widget_store_test.dart`: `scrubStoredAmounts` conserva ítems.
- `widget_launch_test.dart` / `widget_launch_listener_test.dart`: id inválido o vencido → Home; teaser Android → paywall con `source`; teaser iOS → hoja bloqueada; nada antes del login.
- `widget_news_sheet_test.dart`: orden, leyenda, "Leer en" (fake launcher), "Preguntale a Porty" → `GotoAssistant` con origin; eventos.
- `widget_items_repository_test.dart`: freno de 30 min, caché 12 h de `sec`, falla mantiene caché, `news_provider` ≠ v2 no pide nada, signOut borra.
- `widget_background_refresh_test.dart`: rearma ítems sin red, descarta vencidos, uid distinto → sin ítems.
- Eventos: ninguna prop contiene ticker ni titular (búsqueda en los props con fake `ProductEvents`).
- Backend (fase 2): deno tests de `count_only` y `earnings_count` (permiso por tenencia, nunca titulares en la respuesta, filtro).

### Am.8 Criterios de aceptación técnicos

1. `flutter analyze` sin warnings nuevos; `flutter test test/features/home_widget test/features/product_events test/security` en verde.
2. Criterios de usuario 17–25 y 27–30 del brief, con 26 reemplazado por el de compliance y los 3 nuevos de compliance (filtro, eventos sin ticker, ninguna fecha estimada como confirmada).
3. `ready_v1_legacy.json` (sin campos nuevos) se dibuja como la v1 en los tres tamaños (el grande sin sección).
4. Con `ready_items_expired.json` y el reloj adelantado 49 h (simulador/emulador), los ítems desaparecen sin abrir la app.
5. `flutter build ios --no-codesign` y `flutter build apk --flavor development` compilan.
6. Capturas claro/oscuro de mediano y grande con cada fixture, iOS y Android, revisadas por porty-ui-reviewer; captura de iOS bloqueado con el texto redactado.

### Am.9 Riesgos y decisiones

**Necesita OK del usuario**
- Fase 2: deploy de `headlines` y `sec`, y `db push` de la migración de flags. Y confirmar/desplegar en prod la rama Premium de `news_data_allowed` (hoy Premium recibiría 403 según compliance).
- Prender `widget_teasers_android` / `widget_teasers_ios` (salen en 0 %).

**Confirmado por el usuario (2026-11-05)**
- Fuente v2 (GDELT + SEC, fechas estimadas, sin horario). Descartado: Finnhub comercial con permiso escrito (costo y trámite).
- Aviso en iOS neutro, sin plan ni pago; abre la hoja en la app, el paywall solo adentro.
- Privacidad: `.privacySensitive()` en ticker, titular, fuente y línea de resultados; texto aclaratorio en Ajustes; frase de privacidad actualizada (la publica el usuario). Riesgo residual aceptado: en Android y en StandBy se ven tickers y titulares aun con montos ocultos.

**Decisiones**
- Schema `v: 1` aditivo, no v2 (Am.4.1).
- Selección y textos en Flutter; el nativo solo filtra por tiempo y elige segmentos (una sola implementación testeable).
- Sin aviso de Gold para Premium ni avisos en iOS hasta la fase 2: los textos aprobados llevan número, y contar en el cliente obligaría a bajar contenido pago a quien no lo paga.
- Android grande con 4 filas fijas en vez de `RemoteViewsService` (menos código, sin colección).
- Alarma inexacta en Android para vencimientos: no depende de WorkManager ni pide permiso de alarmas exactas.
- `PaywallReason.plans` para el aviso de noticias (no hay un motivo "Premium noticias"; agregar uno sería tocar la hoja del paywall por un texto).

**Riesgos**
- Calidad de GDELT: el filtro del servidor de `headlines` es el del chat; si llegan titulares irrelevantes, el widget los muestra. Mitigación: la misma clave que el chat; medir `widget_item_action`.
- Fecha estimada errada por días: el texto dice "estimada" y la hoja lo aclara; aun así puede no presentar ese día.
- Teaser de Android sin número (fase 1) afirma que hay noticias sin saberlo: el texto aprobado "Noticias de tu cartera · Premium" es genérico; si compliance/PO lo leen como afirmación, esperar a la fase 2.
- Volumen de `headlines`: 1 llamada por apertura de Premium/Gold, con freno de 30 min y caché del servidor; sin costo de IA.
- App Review puede objetar el aviso de iOS igual (compliance: imprevisible).
