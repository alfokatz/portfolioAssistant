# Portfolio Q&A — diseño v2

**Fecha:** 2026-06-03 (v1), actualizado 2026-06-09 (v2)  
**Estado:** implementado (v2 GenUI)

## Objetivo

Asistente conversacional con respuestas **concisas** y **widgets simples** cuando los datos del portfolio ayudan a responder. Consejos educativos generales, sin órdenes de trading.

## Módulo

`lib/features/portfolio_qa/`

- `PortfolioContextBuilder` — snapshot JSON
- `PortfolioQaOpenAiService` — OpenAI + GenUI con surface dinámico por turno
- `PortfolioQaCatalog` — catálogo QA con widgets livianos
- `PortfolioQaScreen` — chat híbrido (burbujas usuario + surfaces GenUI)
- Ruta `/portfolio-qa`

## Patrón de respuesta

1. `QaAnswerText` — máx. 2 oraciones, sin markdown
2. **Un** widget de datos (opcional)
3. `QaTipBanner` — nota educativa opcional

## Widgets QA (simples)

| Widget | Uso |
|--------|-----|
| `QaAnswerText` | Respuesta directa en texto |
| `QaMetricStrip` | 2–3 métricas clave (valor, P&L, %) |
| `QaPeriodChange` | Cambio del portfolio en un período (semana, mes, etc.) |
| `QaTickerMove` | Movimiento de precio de un ticker en un período |
| `QaConcentrationBar` | Concentración / riesgo por peso % |
| `QaPnLBreakdown` | Invertido → valor → resultado |
| `QaTopMovers` | Mejor y peor posición |
| `QaPositionList` | Lista compacta de posiciones abiertas |
| `QaClosedPositionList` | Lista compacta de posiciones cerradas |
| `QaComparisonRow` | Comparar dos activos |
| `QaTipBanner` | Tip educativo de una línea |

## Entrada

Card principal en Home: "Preguntame sobre tu portfolio".

## Datos de contexto

El asistente acepta preguntas con posiciones abiertas, solo cerradas, o ambas.

El snapshot incluye:
- `period_returns` (día, semana, mes, trimestre, año) desde historial del portfolio
- `position_periods.{TICKER}.{period}` con `price_start`, `price_end`, `change_pct`
  desde velas Yahoo (`getHistoricalDaily`), separados de `total_pnl_*` (all-time)
- `closed_positions[]` con P&L realizado por operación y totales agregados

Preguntas de **causa** ("¿por qué cayó X?"): solo movimiento numérico +
`QaTipBanner` sobre límites; sin inventar noticias ni eventos.

## Fuera de alcance (Fase 2+)

- Web search / noticias verificadas
- Órdenes de compra/venta
- Widgets complejos del flujo de análisis (sparklines, news feed, etc.)
