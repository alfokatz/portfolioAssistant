# Kit de las cards del chat (`lib/features/assistant/catalog/kit/`)

Las cards del chat tienen su propio kit porque se renderizan dentro de genui. Regla del kit: **ningún widget del catálogo declara un `TextStyle` suelto ni usa `context.customColors`**; si falta un estilo o color, se agrega al kit.

## Tokens (`qa_tokens.dart`)

- `QaColors.*`: `textPrimary`, `textSecondary`, etc., resueltos por brillo (`QaColors.resolve` lo llama el host; `QaColors.isDark` disponible).
- `QaText`: jerarquía v3 →
  - `cardTitle` 17 w700 (encabezado de card)
  - `sectionTitle` 16 w700 (título de sección dentro de la card)
  - `title` 15 w600 (filas)
  - `body`, `bodyStrong`, `caption`
  - `value`, `valueSm`, `display`, `displaySm` (números, ya tabulares)
  - `label`, `insetLabel` (gris dentro de insets)
  - `eyebrow` (solo vía `QaSectionLabel`, ver abajo)
- `QaSpace`: `cardPadding 18`, `cardRadius 16`, `insetRadius 12`, `chipRadius 8`, `gap 12`, `rowGap 14`, `sectionGap 20`.
- `QaPalette`: `series(i)` / `categorical` (listas separadas para claro y oscuro), `inset`, `track`, `trend(v)`, `trendTint(v)`.
- `QaFormat`: `price`, `money` (compacto desde 100K: "$1.2M"), `signedMoney`, `signedPct`, `pct`, `plural(n, sing, pl)`.

## Estructura de una card

```
QaCardShell                       ← entrada animada + haptics; highlighted = borde aiCardBorder
  QaCardTitle(title, icon)        ← círculo con chip/onChip
  contenido
    QaSection(title, first: true) ← la ÚNICA línea dentro de una card, separa secciones
      filas separadas por QaSpace.rowGap, SIN divisores
    QaInset                       ← bloque teñido; nunca una card dentro de la card
  QaFollowUpBar(items: [...])     ← siempre al final
```

## Primitivas (`qa_primitives.dart`, `qa_identity.dart`)

| Para | Usá |
|---|---|
| Suba / baja | `QaDeltaChip` (la única forma) |
| Etiqueta | `QaTag` |
| Cifra con label / grilla de cifras | `QaStat`, `QaStatGrid` |
| Progreso | `QaProgressBar`, `QaRing`, `QaSegmentedBar`, `QaDonut`, `QaRangeBar` |
| Mini gráfico | `QaSparkline` |
| Ticker con logo | `QaTickerAvatar`, `QaTickerHeader` |
| Tocable sin ripple de Material | `QaTappable` |
| Seguimientos | `QaFollowUp` + `QaFollowUpBar`; para un ticker, `QaTickerFollowUps` |
| Contenido Gold bloqueado | `QaGoldLock` (máximo **uno** por card) |
| Cambio de estado sin salto | `QaStateSwitcher` |
| Cargando | `QaSkeleton`, `QaChartSkeleton` |
| Tiempo relativo | `QaTime.ago` |

## Reglas propias del chat

- `QaSectionLabel` (eyebrow en mayúscula terracota) **solo** como etiqueta de contexto sobre un número, nunca como título de sección. Para secciones: `QaSection` / `QaSectionTitle`.
- Las cards en claro llevan una sombra muy tenue del shell; en oscuro ninguna. No agregar sombras propias.
- Glow de highlight multiplicado por `glowScale`.
- Los números los pone la app con la evidencia del turno cuando se puede (ver skill **porty-assistant**).
- Seguimientos con `QaFollowUpScope`, no con eventos de genui.
- Lenguaje visual compartido con la app: los círculos de ícono, las flechas ↗ de seguimiento y las filas imitan Ajustes y Metas.
