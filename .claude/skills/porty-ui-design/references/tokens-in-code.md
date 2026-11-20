# Tokens en código

## Contenido
- Colores (`CustomColors`)
- Tipografía
- Dimensiones (`AppDimens`)
- Tema global (lo que ya viene gratis)
- Formato de números, monedas y fechas
- Imágenes

## Colores: `context.customColors`

`lib/presentation/base/theme/theme_extension.dart`:

```dart
final c = context.customColors;
Container(
  decoration: BoxDecoration(
    color: c.surfaceCard,
    borderRadius: BorderRadius.circular(AppDimens.radiusLg),
    border: Border.all(color: c.border),
  ),
);
```

| Token | Uso |
|---|---|
| `background` | canvas (normalmente no hace falta: el Scaffold es transparente y se ve `AppBackgroundGradient`) |
| `surfaceCard` | cards, hojas, inputs de auth, composer |
| `surfaceElevated` | inputs globales, riel de segmentados, burbuja del usuario |
| `inset` | bloque dentro de una card (en vez de una card anidada) |
| `border` | bordes de card y divisores |
| `textPrimary` | texto principal, línea del gráfico, fondo del CTA primario |
| `textSecondary` | labels, hints, subtítulos, chevrons |
| `accentBlue` / `accentWarm` | terracota: foco, selección, acciones, Porty (el nombre "Blue" es histórico) |
| `accentDim` | links y acciones de texto secundarias |
| `onAccent` | texto/ícono sobre un relleno terracota |
| `profit` / `loss` (+ `profitContainer` / `lossContainer`) | PnL; `pnlColor(v)` elige por signo |
| `chip` / `onChip` | círculo de ícono de una fila y su ícono (en oscuro es gris, no terracota) |
| `track` | fondo de barras de progreso y anillos |
| `chartLine`, `chartGrid`, `benchmarkSp500` | gráficos |
| `haloStrength` (0.32 / 0) | intensidad del halo; 0 en oscuro |
| `glowScale` (1 / 0.35) | multiplicar el alpha de cualquier glow: `alpha: 0.16 * c.glowScale` |

- **Trampa**: `color_extesion.dart` tiene otra clase `CustomColors` legacy. No importarla.
- Material (`ColorScheme`) ya está mapeado a la misma paleta en `color_schema.dart`, así que un `FilledButton` o `Switch` sin estilo propio respeta la marca.
- Chequeo rápido: `grep -n "Color(0x\|Colors\.\(white\|black\)" <archivo>` en lo que tocaste debería dar vacío (excepción documentada: botón de Apple).

## Tipografía

- Familia empaquetada `appFontFamily = 'Plus Jakarta Sans'` (`text_theme.dart`, helper `jakarta(...)`). No usar `GoogleFonts.plusJakartaSans`: con google_fonts el w700 no se ve.
- Escala: usar `Theme.of(context).textTheme.<rol>` y ajustar con `copyWith`:
  - Display 44/700 (total del portfolio; ya trae tabular figures)
  - Headline 15–20/600 (títulos de sección)
  - Title 14–16/500–600 (títulos de card, filas)
  - Body 14–16/400, line-height 1.5
  - Label 10–13/500 (badges, chips, metadata)
- Números fuera de display:
  ```dart
  style: tt.titleMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])
  ```

## Dimensiones: `AppDimens` (`app_dimens.dart`)

| Constante | Valor | Uso |
|---|---|---|
| `pageHorizontal` | 20 | margen lateral de página |
| `sectionGap` | 28 | entre secciones |
| `cardPadding` / `cardPaddingLg` | 18 / 20 | padding de card |
| `radiusSm` | 6 | badges, chips |
| `radiusMd` | 10 | inputs |
| `radiusLg` | 14 | cards, botones de 52 px |
| `radiusXl` | 18 | bottom sheets |
| `radiusPill` | 26 | solo el composer del chat |
| `touchTarget` | 44 | mínimo táctil |
| `iconSm/Md/Lg` | 16/20/24 | íconos |
| `sp2 … sp64` | | espaciado |

No usar el bloque "Legacy — no usar en código nuevo" (`minRadius`, `smallMargin`…).

## Tema global (ya viene, no repetir)

`theme_data.dart`: Scaffold y AppBar transparentes, `CardTheme` con elevation 0 + radiusLg + borde, bottom sheets con radiusXl y drag handle, inputs rellenos, divider 0.5 px, transiciones opacas. Una pantalla nueva **no** pinta su propio fondo salvo que sea onboarding/auth.

## Formato

- `AppNumberFormat` (`lib/presentation/shared/formatting/app_number_format.dart`): `money(v)` "$2,058.00", `signedMoney(v)` "+$8.25", `percent(v, decimals: 1, signed: true)` "+0.4%", `shares(q)`.
- Moneda de visualización: feature `lib/features/display_currency/` (`DisplayCurrency.money()`, `displayCurrencyProvider`). Toda valuación es en USD; la conversión es solo de visualización.
- Montos que el usuario escribe: `parseUserNumber` (`lib/shared/utils/user_number.dart`) acepta "1.234,5" y "1,234.5".
- Fechas: `DateFormat` de intl con el locale del contexto (`context.locale.toString()`); relativas en el chat con `QaTime.ago`.
- Nunca mezclar formatos en la misma pantalla ("-1.6%" al lado de "56.997,28 $" fue un bug real).

## Imágenes

`AppImages` (`app_images.dart`): constructores estáticos sobre `SvgPicture.asset` (`googleIcon`, `etoroMark`, `binanceMark`, `successIcon(color:)`…). Asset nuevo: SVG en `assets/images/` + constructor en `AppImages`. Porty: siempre `PortyAvatar`, nunca un asset suelto.
