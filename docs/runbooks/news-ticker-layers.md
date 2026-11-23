# Noticias por ticker en capas

Búsqueda POR TICKER, compartida entre usuarios. Migración `20261126100000_news_ticker_layers.sql`.

| Capa | Qué | Cuándo | Costo |
|---|---|---|---|
| 1 | Símbolo local -> subyacente (`AAPL.BA`, `SHEL.L`...): tabla `ticker_news_map` (excepciones) o quitar el sufijo si el base existe en `sec_ticker_cik` | siempre | 0 |
| 2 | GDELT por nombre de empresa, caché `gdelt:t:<SYM>:<día>` (por subyacente) | siempre | 0 |
| 3 | SEC EDGAR: 8-K/10-Q/10-K/6-K de las últimas 72 h, `SEC_USER_AGENT`, 1 h de caché | siempre (solo emisores de EE. UU.) | 0 |
| 4 | OpenAI `web_search` (low, allowlist) | solo en un pedido de `daily-brief` Premium/Gold de pago, y solo si: sin noticias 48 h en 1-3 y fuentes respondieron, |movimiento del día| >= 2,5 %, sin resultado de hoy ni falla reciente, tope mensual no alcanzado | tope `ticker_search_monthly_usd` (20) |

`news-warm` precarga solo 1-3, solo de usuarios con `app_opened` en 7 días (`daily_brief_warm_symbols_active`). Nunca la 4.

## Config (`app_config.daily_brief_costs`)
`ticker_search_monthly_usd` (20; 0 apaga la capa 4), `ticker_search_min_move_pct` (2.5), `ticker_search_reserve_usd` (0.05, se reserva antes y se ajusta al costo real), `ticker_search_max_per_request` (3).

## Contrato nuevo (`daily-brief`, scope brief/feed, Premium/Gold)
- Búsqueda asincrónica (segundo plano, 10-40 s: no entra en un pedido de feed). El pedido responde ya con `searching: {tickers, retry_after_s: 10}` y, si `mine` está vacío, `mine_status: "searching"`. La app muestra a Porty pensando y repite el mismo pedido cada `retry_after_s` (máx. 4 veces). Apps viejas leen `searching` como sin estado.
- Notas de la SEC en `mine`: `source: "SEC"`, `domain: "sec.gov"`, `source_kind: "filing"`, `filing_form: "8-K"`, `url` al documento, sin `image_url`, `title` ya en el idioma pedido.

## Operación
- Gasto del mes: `select * from news_ticker_search_spend;` (mes UTC). Logs: `fn: "ticker-search"` con `cost_usd`.
- Apagar ya: `update app_config set value = value || '{"ticker_search_monthly_usd": 0}' where key='daily_brief_costs';`
