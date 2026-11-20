# Notas de investigación: brief diario (spec técnica)

Hallazgos confirmados para `2026-11-20-brief-diario-tech.md`. Formato: hallazgo · fuente.

## Informe semanal (patrón a copiar)

- La generación la hace la app: claim → 1 llamada LLM vía `ai-chat` modo informe (sin cuota) → complete | fail; PK (user_id, week_start) evita doble generación · `supabase/migrations/20261002120000_weekly_reports.sql:1-30`.
- `claim_weekly_report` vigente es la de `20261103120000_weekly_report_courtesy.sql:43` (con `disabled` y cortesía `_weekly_courtesy_limit`, advisory lock por usuario).
- TTL de claim 2 min y 3 intentos: `_report_claim_ttl()` / `_report_max_attempts()` · `20261002120000_weekly_reports.sql:66-78`.
- `ai_report_begin` vigente: `20261106100000_weekly_report_translation.sql` (chequea `_weekly_report_enabled`, model_prices, rate limit, claim, rondas; registra `ai_turn_usage.purpose='weekly_report'`).
- `ai_turn_usage.purpose` check = `('chat','weekly_report')` · `20261002120000_weekly_reports.sql:42-44`.
- `ai-chat` modo informe: header `x-porty-purpose: weekly_report` + `x-porty-report-week`, allowlist `allowed_report_prompts.json`, sin tools/stream/system extra, `maxReportRounds: 8` · `supabase/functions/ai-chat/handler.ts:19-22, 53, 310-314, 455-537`.
- Generador Dart: 1 llamada + 1 reescritura con issues del validador, `json_schema` estricto, modelo `gpt-6-luna`, temp 0.4, 1500 tokens, timeout 40 s, nunca lanza · `lib/features/weekly_report/data/weekly_report_generator.dart:46-150`.
- Test de hash del prompt del informe vive en `test/security/system_prompt_allowlist_test.dart:20,75-90` (importa `weeklyReportSystemPrompt*`). `test/security/` está en CODEOWNERS y no se toca en el mismo cambio que juzga (`CLAUDE.md`, `.github/CODEOWNERS`).
- `gold_data_allowed` da Gold a TODO durante 30 min si hay un informe `generating` · `20261012000000_commercial_data_sources.sql:159-177`.

## Noticias

- `headlines` (GDELT): JWT, ≤10 tickers por consulta, caché compartida por CONJUNTO de tickers (`gdelt:<syms>|from|to`), 30 min / 24 h; `count_only` para cualquier plan si todos están en cartera; gating `newsAllowed` · `supabase/functions/headlines/handler.ts:23-29, 82-121`.
- GDELT: limitador GLOBAL 1 pedido cada 5,5 s (`upstream_rate_gate`), espera máx. 7 s, 250 registros, ≤8 dominios en la consulta (`queryDomains` fijos, casi todos de EE. UU. + infobae), idioma solo english/spanish, búsqueda por nombre de prensa (`pressName` del título SEC) · `supabase/functions/_shared/gdelt.ts:10-40, 98-127`.
- Consecuencia: con 1 req/5,5 s el techo es ~650 consultas GDELT/hora para todo Porty; clave por conjunto ⇒ cada cartera distinta es un miss.
- Nombre de empresa sale de `resolveCik` (SEC): tickers no listados en EE. UU. (.BA, .MC, .T…) no tienen CIK → se busca por ticker, cobertura pobre · `headlines/handler.ts:41-49`.
- `news-context`: Responses API + `web_search`, `filters.allowed_domains` (hasta 100), `search_context_size: medium`, `user_location AR` si es; modelo default `gpt-5-mini`; US$0,01 por búsqueda (comentario 2026-10); caché 45 min por empresa; 1 pedido por turno; tope diario de pedidos y mensual de UNIDADES (`news_context_quota_hit(p_units 1..5)`) · `supabase/functions/news-context/handler.ts:25-58, 300-330, 380-470`.
- Topes mensuales news-context: Free 10 / Premium 80 / Gold 160 unidades; web: 15/60/100 · `20261105100400_monthly_search_caps.sql:20-31`. Diario news-context: Gold 40, Premium 10, Free 5 pedidos · `20261012000000…:191-195`, `20261105100500_held_news.sql:34`.
- `news_data_allowed` = Gold/cortesía o Premium con el ticker en `positions` y `news_provider = v2` · `20261105100500_held_news.sql:9-28`.
- Sin tickers, `newsAllowed`/`clientTextTrusted` solo pasan Gold · `_shared/data_cache.ts:68-120`.
- `news_source_allowlist(domain pk, name, lang check es|en, enabled)`; 28 medios iniciales + 18 · `20261012000000…:108-146`, `20261013000100_news_allowlist_more_outlets.sql`. Solo 3 medios no-EE. UU./no-LatAm/ES de alcance global (BBC, Guardian, Economist); sin Asia, Canadá, Australia, India.

## Push y jobs

- `daily-jobs` corre cada hora, usuarios por hora local (`push_users_at_local_hour`), `jobHours.morningBrief = 8` · `supabase/functions/daily-jobs/jobs.ts:37-52`.
- `morningBriefRows`: concentración ≥25 % / desvío; 1 vez por mes por conjunto de señales · `jobs.ts:275-320`.
- Kind `morning_brief`: pref `morning_brief`, automatic, quiet defer, 6 h, canal portfolio · `notify-dispatch/kinds.ts:150-160`. `dailyAutomaticCap = 3` · `kinds.ts:189`.
- Último `notification_outbox_kind_check` y `push_dispatch_context`: `20261024000000_morning_brief.sql` y `20261024000300_contribution_reminder.sql`.
- `market-watch`: cotizaciones Yahoo en lote, `computeMoves` (umbrales por sensibilidad, cobertura mínima 0,8, benchmark ^GSPC), horario solo NYSE · `market-watch/moves.ts:43-77`, `market_clock.ts`.

## App

- `PortfolioDayMove.compute(history, positions, candles)` = la línea "Hoy"/1D de la Home y el widget · `lib/domain/utils/portfolio_day_move.dart:33-100`, `lib/presentation/flows/home/ui/home_screen.dart:126-131`.
- Chat con contexto: `GotoAssistant(initialQuestion, screen: PortyScreenContext, origin)` · `lib/features/assistant/nav/assistant_nav.dart`; `PortyScreen` enum · `models/porty_screen_context.dart`.
- La guía de `screen_context` va en `pinnedContextFor` (mensaje de contexto, fuera del hash) · `services/assistant_openai_service.dart:152-190`.
- `get_weekly_report` (tool de solo lectura, sin card propia de datos) · `tools/report_tools.dart`.
- `get_news`: Gold todo; Premium solo en cartera; Free bloqueado; 1 news-context por turno · `tools/market_tools.dart:277-460`.
- `PlanFeature` sin capacidad de informe: el semanal lo decide el servidor (`leadingMarketingKeys`) · `lib/domain/subscription/plan_matrix.dart:180-190`; `allowsNewsFor(tier, held:)` · `:205`.
- `ProductEvent.appOpened` ya existe · `lib/features/product_events/data/product_events.dart:72`.
- `WidgetNewsSheet` atado a `WidgetCachedItem`, abre URLs afuera, eventos `widget_item_action` · `lib/features/home_widget/view/widget_news_sheet.dart`.
- pubspec: hay `url_launcher`; NO hay webview ni reproductor de YouTube ni TTS · `pubspec.yaml:71`.

## YouTube Data API (fuente oficial no accesible desde esta sesión: developers.google.com no resuelve)

- Cuota por defecto 10.000 unidades/día, reset a medianoche PT; `playlistItems.list` = 1 unidad; `search.list` = 100 unidades y, según la página actual, además un tope propio de ~100 llamadas/día · búsqueda sobre https://developers.google.com/youtube/v3/determine_quota_cost (verificar en la consola).
- Developer Policies: privacidad propia que mencione que se usan YouTube API Services y enlace a la Política de Privacidad de Google; datos que no son del usuario (títulos, canales) con regla de refresco/borrado de 30 días; revisión de junio 2026 con requisitos de identificación del cliente para el reproductor embebido · https://developers.google.com/youtube/terms/developer-policies , https://developers.google.com/youtube/terms/derived-metrics-policy , https://developers.google.com/youtube/terms/revision-history.

## Segunda tanda (confirmado después)

- YouTube "Distribution and Commercial Use": prohíbe vender/arrendar/sublicenciar los API Services, **incluido el contenido audiovisual**; una copia de terceros dice que no se puede vender el acceso a componentes sin aprobación escrita → **los videos no pueden ir detrás de un plan pago** · https://developers.google.com/youtube/terms/developer-policies , https://youtubehelp.fandom.com/wiki/YouTube_API_Services_-_Developer_Policies (copia, verificar texto vigente).
- Sección III.E.4.i (reproductor embebido, datos enviados; autoplay false limita datos) · https://developers.google.com/youtube/terms/revision-history.
- Error 153 del reproductor embebido: YouTube exige identificación del embebedor por Referer; las WebView de Android suelen no mandarlo (reportes de comunidad, sin doc oficial) · https://simonwillison.net/2025/Dec/1/youtube-embed-153-error/ , https://iframely.com/help/501993-you-tube-error-153-in-android-web-view.md.md.md.md , https://teamdynamix.umich.edu/TDClient/30/Portal/KB/Article/14491/Fixing-YouTube-Player-Error-153-with-Referrer-Policy-Settings.
- OpenAI web search: US$10 por 1.000 llamadas (US$0,01) + tokens de contenido de búsqueda al precio del modelo; reportes de más búsquedas internas que las esperadas · https://developers.openai.com/api/docs/pricing , https://community.openai.com/t/heads-up-web-search-tool-billing-can-be-higher-than-you-expect-here-s-why/1236954.
- `ai-chat` pide gpt-6-luna con `service_tier: fast`: US$0,20 entrada / 0,02 cacheada / 1,00 salida por M · `supabase/migrations/20261014130000_gpt6_luna_fast_prices.sql`, `ai-chat/handler.ts:88-108`.
- GDELT y developers.google.com no son alcanzables desde esta sesión: la cobertura no se pudo medir acá; queda como tarea con script.
- Cron: `cron.schedule` dentro de `do $$ if exists pg_cron`, llamando `public._call_function('<fn>')` (pg_net, timeout 55 s) · `20261113000000_sync_prod_drift.sql:153-160`.
- Watchlist: tabla `watchlist_items(user_id, symbol, notify, ...)` · `20261016000200_watchlist.sql:22-33`.
- Resultados con v2 (SEC): no hay calendario; fecha próxima SIEMPRE estimada; lo confirmado es el 8-K 2.02 presentado (`secEarningsReleases`) · `supabase/functions/sec/handler.ts:1-16`, `_shared/sec_data.ts:186-201`, `daily-jobs/handler.ts:4-8`.
- Yahoo quote (servidor) da `quoteType`, `prevClose`, `changePct`, `marketState`; no parsea nombre ni `regularMarketTime` hoy · `market-watch/quotes.ts:12-22`.
- Señales de concentración/desvío en la app: `PortyInsightsBuilder` · `lib/features/porty_inbox/domain/porty_insights_builder.dart:18`.
- Home inserta `WeeklyReportCard` · `lib/presentation/flows/home/ui/home_screen.dart:236`.
- Push routes de la app: `lib/features/notifications/domain/push_route.dart:17-28`.
- Área `research` del chat: tools de noticias, presupuesto 1060 tokens, `DeferredSpec` de `get_news` · `lib/features/assistant/areas/porty_areas.dart:140-180`.
- Dueños: assistant-dev es dueño del allowlist (`supabase/functions/ai-chat/allowed_*.json`); backend del resto de `supabase/`; flutter de `lib/` salvo assistant/genui_core y de traducciones · `.claude/skills/porty-team/SKILL.md:23-33`.
- Borrado de cuenta: catálogo de tablas en `supabase/tests/account_deletion_db_test.sql:30-36`.
