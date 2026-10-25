# Fuentes con uso comercial para noticias, resultados y fundamentals (v2)

Reemplaza Finnhub free, Google News RSS y el uso de Yahoo para noticias, que no permiten uso comercial, por estas fuentes:

| Dato | Fuente v2 | Edge function |
|---|---|---|
| Resultados, presentaciones (8-K/6-K/10-Q/10-K/20-F) y fundamentals | SEC EDGAR (`data.sec.gov`, `efts.sec.gov`), gratis | `sec` (`/filings`, `/earnings`, `/fundamentals`) |
| "Qué está pasando y por qué", con citas | Herramienta `web_search` de OpenAI (Responses API, `gpt-5-mini`) restringida a `news_source_allowlist` | `news-context` |
| Titulares (card de noticias, informe semanal, investor-pulse) | GDELT DOC 2.0, filtrado por `news_source_allowlist` | `headlines` |

Todo queda detrás de `app_config.news_provider` (`legacy` | `v2`). El valor arranca en `legacy`: hasta que se cambie, la app y el servidor se comportan como antes.

## Qué cambia con `v2`

- **`get_earnings`:** último comunicado de resultados (texto en inglés, recortado a ~2.500 tokens para que el modelo lo resuma), EPS e ingresos de los últimos 4 trimestres con la variación interanual, y el próximo reporte **estimado**. EDGAR no publica calendario: la fecha se estima con el mismo reporte del año anterior + 364 días, o con el último + 91 días. **No hay consenso de analistas.** Si el usuario lo pide, el modelo usa `get_news` con `question` (búsqueda web con citas).
- **`get_fundamentals`:** datos contables de la SEC (ingresos, resultado, EPS, márgenes, ROE/ROA, deuda, caja, acciones). Lo que depende del precio (P/E, P/S, P/B, valor de mercado, EV/EBITDA, rendimiento del dividendo) se calcula con el precio actual, y **solo si la empresa reporta en USD**. El rango de 52 semanas sale de los cierres diarios. No hay forward P/E, PEG ni beta.
- **`get_news`:**
  - titulares de GDELT;
  - `context`, que es el resumen con citas de la búsqueda web: 1 búsqueda por turno, caché compartida de 45 min (10 min si vino vacía) y tope diario de `plan_limits.news_context_per_day` (Gold 40; Free/Premium 5 para la cortesía semanal y el informe);
  - parámetro opcional `question`, como respaldo a demanda (fecha confirmada, consenso).
- **Fuentes visibles:** debajo de cada respuesta, la app muestra las citas de la búsqueda web y las presentaciones de la SEC (requisito de OpenAI). Es el pie del mensaje (`AnswerSources` → `QaSourceList`), fuera del catálogo y del prompt.
- **Push de earnings:** "reporta mañana" se apaga (una fecha estimada no alcanza para avisar). "Salió el resultado" se dispara cuando aparece un 8-K con ítem 2.02 de una acción en cartera; sin consenso, el texto dice que presentó, no si superó lo esperado. Los emisores extranjeros (6-K) no generan push.
- **Informe semanal:** titulares de GDELT y próximos resultados con "Fecha estimada".
- **investor-pulse:** GDELT en lugar de Google News RSS.
- **Plan en el servidor:** `sec`, `headlines` y `news-context` validan Gold con `gold_data_allowed`. También admiten la cortesía semanal de ese ticker y un informe semanal en curso. El resto recibe 403 `plan_required`.
- **Ajustes:** "Acerca de → Fuentes de datos" (SEC EDGAR, búsqueda web de OpenAI, GDELT).

## Despliegue (en orden; ninguno de estos pasos se ejecutó)

1. `supabase db push`. Aplica tres migraciones nuevas:
   - `20261012000000_commercial_data_sources`;
   - `20261012000100_commercial_data_sources_grants`;
   - `20261012000200_web_search_hit_grant`. **Esta última también corrige un bug que ya existía:** `search_web` respondía siempre `daily_limit`, porque la service role no podía ejecutar `web_search_hit`.
2. Secrets:
   - `supabase secrets set SEC_USER_AGENT="Porty <email de contacto>"`. Es el mismo que usa investor-pulse; si ya está cargado, no hace falta.
   - Opcional: `NEWS_CONTEXT_MODEL`. Por defecto `gpt-5-mini`. **`gpt-4.1-mini` no sirve**, porque no acepta `filters.allowed_domains` (devuelve 400).
3. `supabase functions deploy sec news-context headlines daily-jobs investor-pulse notify-dispatch web-search ai-chat`. `ai-chat` lleva el hash nuevo del system prompt en la allowlist; el anterior se mantiene para las versiones viejas de la app.
4. Publicar la app (o probar con un build de desarrollo).
5. Pasar a v2:
   ```sql
   update public.app_config set value = '{"provider": "v2"}', updated_at = now()
    where key = 'news_provider';
   ```
   La app lo relee cada 10 minutos, y una conversación ya abierta sigue con la fuente con la que empezó.
6. Volver atrás: el mismo `update` con `"legacy"`.

## Monitoreo (la primera semana)

- Logs: `{"fn":"sec"|"news-context"|"headlines", "cache": "hit|miss|stale|error", "ms": …}`. `news-context` también registra `calls` y `cost_usd`, y `empty` cuando no encontró nada (`sin_novedades` | `no_bullets` | `no_citations`).
- Costo de las búsquedas web: columnas `web_search_calls` y `web_search_cost_usd` en `ai_turn_usage`, más los totales nuevos de `ai_usage_monthly_stats` (`web_search_calls_total`, `web_search_cost_total_usd`).
- Medido en local (2026-10-11):
  - búsqueda sin caché: 1-5 búsquedas por consulta, US$0,013-0,058 (típico US$0,025), 3-15 s (típico 6-10 s);
  - SEC sin caché: 0,7-2,5 s;
  - turno completo de noticias: 9-21 s.
- **GDELT:** desde una IP compartida puede quedar limitado. Pide "un pedido cada 5 s" y desde la Mac de desarrollo respondió 429, "query too long" o cortó la conexión. Si `{"fn":"headlines","cache":"error"}` es frecuente, la card de noticias queda sin titulares (el contexto con citas llega igual). En ese caso, hay que evaluar el acceso con el equipo de GDELT o mostrar los titulares desde las citas de la búsqueda web.

## Pendiente antes de lanzar (no técnico)

- Leer los términos de uso de GDELT y la política de *fair access* de la SEC. Hasta ahora se revisaron solo por resultados de búsqueda.
- Consulta legal breve si queda alguna duda.
- Revisar la lista inicial de `news_source_allowlist` (28 medios; se edita sin deploy). Incluye `finance.yahoo.com` como medio; sacarlo si no se quiere.

## Fuera de alcance (siguen con fuentes sin uso comercial)

- Precios y gráficos (Yahoo, con Finnhub de respaldo en `market-watch`), dividendos y composición de ETFs (Yahoo), perfil/sector (Yahoo).
- Logos y nombre de empresa (Finnhub `/stock/profile2`).
- **`search_symbol`** (Finnhub `/search`): el plan no lo menciona. Se podría pasar a `company_tickers.json` de la SEC, aunque no cubre ETFs ni empresas que no presentan ante la SEC.

## Fase 4 (después de una semana en v2 sin problemas)

- Borrar `GoogleNewsRssRepositoryImpl`, `FinnhubCompanyNewsRepositoryImpl`, `FinnhubEarnings*`, `FinnhubCompanyFundamentalsRepositoryImpl`, `EarningsFetcher`/`FundamentalsFetcher` (legacy), el camino legacy de `daily-jobs` e `investor-pulse`, y las descripciones legacy de las tools.
- Sacar `/company-news`, `/calendar/earnings`, `/stock/earnings` y `/stock/metric` de `endpointTtlSeconds` del proxy `finnhub`.
- Recortar las reglas de consenso de Finnhub del prompt (EARNINGS). El tope del test de tamaño quedó en 112.000; regenerar la allowlist.

## Evals

```sh
# supabase start + functions serve con OPENAI_API_KEY y SEC_USER_AGENT
cd supabase/functions && export EVAL_PROXY_JWT=$(deno run -A scripts/eval_user.ts)
cd ../.. && RUN_ASSISTANT_EVALS=1 EVAL_NEWS_V2=1 EVAL_ANON_KEY=$ANON_KEY EVAL_CASE_DELAY_S=6 \
  flutter test test/evals/assistant_tool_evals_test.dart
```

Son 10 casos en español (noticias, "por qué se movió", resultados, consenso, emisor extranjero, fundamentals). Cada uno verifica que se use la tool correcta, que haya citas (al menos 3 en "¿Qué pasó con Nvidia esta semana?"), que no aparezcan cifras sin respaldo en las tools, que no haya consejos de compra o venta y que nunca se diga "superó / no alcanzó" sin consenso. Última corrida: 10/10.
