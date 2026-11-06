# Fixtures del widget v2

Contrato compartido entre Dart, Swift (`FeedPicker`) y Kotlin (`PortyFeedPicker`).
Spec: `docs/specs/home-widget-v2-tech.md` (§3.2 formato, §3.5 reglas).

Todos los `ready_*.json` son el JSON que escribe `WidgetSnapshot.toJson()`
(clave compartida `porty_widget_snapshot`). Datos ficticios (ACME, GLOBX, NOVA,
ZETA, ORBT). Ninguno lleva montos. Reloj de referencia: `2026-11-06T15:00:00Z`
(ms `1793890800000`), zona horaria de armado UTC-3 (medianoche local =
03:00Z).

| Archivo | Qué es |
|---|---|
| `ready_es.json` | Gold con todo: resultados, 2 noticias, 2 avisos, mover, biggest, gráfico intradía |
| `ready_en.json` | Inglés, día a la baja (`mood: concerned`), aviso de concentración |
| `ready_free_android.json` / `ready_free_ios.json` | Free: avisos + teaser (texto por plataforma) + mover + biggest, sin noticias ni resultados |
| `ready_hidden_es.json` | `positions_hidden: true`: ítems en forma oculta, sin `feed_rev`, preguntas `_hidden` |
| `ready_chart_only_es.json` | Feed vacío, solo gráfico |
| `ready_days_chart_es.json` | Gráfico `days` (sin baseline) |
| `ready_expiring.json` | Una noticia que pasa a prio 3 a medianoche y un resultado que vence a las 17:00Z |
| `legacy_v1_items.json` | JSON de la versión anterior (sin bloque `v2`, con montos y tickers): el nativo nuevo NO debe leerlos |
| `feed_cases.json` | Casos del selector nativo (abajo) |

## `feed_cases.json`

```json
{"version": 1, "cases": [
  {"name": "...", "note": "...", "now": <epoch ms>,
   "cursor": null | {"rev": "<8 hex>", "index": 2, "at": <ms>},
   "snapshot": { ...snapshot completo... },
   "expected": {
     "stale": bool,                 // now >= snapshot.stale_at
     "header_n": int,               // vivos con prio <= 2
     "next_index": int | null,      // (indice actual + 1) % live.count; null si no hay vivos o hay posiciones ocultas
     "small":  {"line": "item", "feed_index": i}
             | {"line": "hidden_count", "n": N}     // N = vivos con prio <= 2 (solo con positions_hidden)
             | {"line": "chart"} | {"line": "no_news"},
     "medium": {"mode": "item", "feed_index": i, "question": "<ref>"|null, "next_button": bool}
             | {"mode": "hidden_count", "n": live.count, "question": "<ref>"|null, "next_button": false}
             | {"mode": "no_news", "question": "<ref>"|null, "next_button": false},
     "large":  {"mode": "rows", "rows": [feed_index...], "questions": ["<ref>"...]}
             | {"mode": "hidden_count", "n": live.count, "questions": [...]}
             | {"mode": "no_news", "questions": [...]}
   }}
]}
```

- `feed_index` = posición del ítem en `snapshot.v2.feed` (así sirve también con
  posiciones ocultas, donde los ítems no traen `id`).
- `live` y el resto de reglas: §3.5 de la spec. Orden estable por `prio` del
  segmento vigente en `now`.
- `question` / `questions` son los `ref` (8 hex) de `item.q ?? questions.fallback`
  y de `questions.large`.
- El cursor solo vale si `cursor.rev == v2.feed_rev`; si no, índice 0. El índice
  se toma módulo `live.count`.
- Los textos y los pesos de las preguntas no se comparan: solo los `ref`.

## Regenerar

`feed_cases.json` lo regenera `WidgetFeedPicker` (Dart):
`UPDATE_WIDGET_FIXTURES=1 flutter test test/features/home_widget/domain/widget_feed_picker_test.dart`
(recalcula `expected` desde `snapshot`/`now`/`cursor`; no toca las entradas).
Native: Kotlin `PortyFeedPickerTest`, Swift `ios/tools/feed_cases_check.swift`.
