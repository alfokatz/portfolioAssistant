# Componentes que ya existen (reusar antes de crear)

## Contenido
- Widgets compartidos
- Botones
- Hojas (bottom sheets)
- Filas de ajustes
- Patrones de pantalla

## Widgets compartidos (`lib/presentation/shared/widgets/`)

| Necesitás | Usá |
|---|---|
| Confirmar una acción | `ConfirmSheet.show(context, title:, confirmLabel:, body:, destructive:)` → `Future<bool>` |
| Avisar éxito/error | `ref.read(alertProvider.notifier).showSuccess/showWarning/showError(title:, message:)` → se ve como `PortyToast` |
| Porty hablando en una pantalla de tarea | `PortySays(message:, messageKey:, mood:, footnote:)` |
| Pantalla vacía, error o no encontrado | `PortyStatusMessage` |
| Pregunta lista que abre el chat | `PortyQuestionPill` |
| Card simple con borde | `SurfaceCard` |
| Card de sección de insights | `HomeChartCard` |
| Título de sección + link de acción | `SectionHeader` |
| Control segmentado | `SegmentedChoice<T>` |
| Fila label/valor | `LabeledValueRow` |
| Variación % con fondo | `PnlBadge` |
| Texto que todavía no llegó | `SkeletonText(placeholder:)` |
| Entrada escalonada | `FadeSlideIn` |
| Cambiar secciones sin solapar | `FadeThroughSwitcher` |
| Animar tamaño | `MotionAwareSize` |
| Buscar un ticker | `TickerSearchSheet` |
| Navegación inferior | `AppBottomNavBar` |
| Fondo con halo | `AppBackgroundGradient` (ya lo pinta la ruta) |
| Gráficos | `lib/presentation/shared/charts/` (`PortfolioAreaLineChart`, `BenchmarkDualLineChart`, `DivergingBar`, `ChartWithYAxis`) |
| Avatar de Porty | `PortyAvatar` (elige solo su paleta en oscuro) |

## Botones

- **Primario**: ancho completo, alto 52, `FilledButton` fondo `textPrimary` / texto `surfaceCard`, `radiusLg`, elevation 0, deshabilitado al 40 % de alpha, contenido con `LoadingButtonContent`. Copiar `lib/presentation/flows/position/ui/widgets/position_primary_button.dart` (no hay uno compartido; si hace falta en una tercera pantalla, proponer moverlo a `shared/widgets`).
- **Destructivo** (dentro de `ConfirmSheet`): mismo botón en `loss`.
- **Secundario**: `surfaceCard` + borde 1 px `border`, texto `textPrimary` w600.
- **Ghost**: `TextButton` en `textSecondary` o fila `InkWell` plana.
- Acción terracota solo para acciones "de Porty" puntuales (Editar, Armar una meta, FAB, enviar).

## Hojas (bottom sheets)

Convención: `static Future<T?> show(BuildContext context, ...)` en la clase de la hoja, que llama `showModalBottomSheet(context: context, isScrollControlled: true, useSafeArea: true, builder: ...)`. El tema ya pone radio `radiusXl`, drag handle y fondo. Ejemplos: `ConfirmSheet`, `FxBreakdownSheet`, `SettingsDataSourcesSheet`.

## Filas de ajustes (`lib/presentation/flows/settings/ui/widgets/`)

`SettingsSectionCard(title:, children:)` (título titleMedium w700 `textPrimary`, sin mayúsculas grises), `SettingsNavRow(icon:, label:, value:, subtitle:, onTap:)` (label en una línea; un valor largo va en `subtitle`), `SettingsToggleRow`, `SettingsPickerSheet`. Usar este mismo lenguaje para cualquier lista de opciones (las sugerencias del chat y Metas lo copian).

## Patrones de pantalla (detalle en DESIGN.md)

- **Pantalla de tarea con Porty** (Metas, Agregar posición, Posiciones cerradas): `PortySays` arriba con una frase armada con números reales (nunca escrita por el modelo), después filas directo sobre el fondo agrupadas con títulos de grupo, divisores alineados al texto.
- **Estado vacío**: Porty explica qué hace + "Podés empezar por una de estas" con 3–4 filas que abren el chat o la acción. Nunca una caja vacía con un botón.
- **Cargando**: skeleton con la misma estructura de la pantalla.
- **Filas**: alto mínimo 44–56, círculo de ícono 32–36 con `chip`/`onChip`, título w500–w700, valor/sub en `textSecondary`, flecha o chevron en `textSecondary`. Tap abre, long-press opciones, swipe-izquierda borra con `ConfirmSheet`.
- **Hero numérico**: label secundario → número display tabular → fila PnL → gráfico sin card.
- **Login / transiciones de estado de la app**: `FadeThroughPage`.
- **Gestos horizontales dentro de una pestaña del shell**: las pestañas se pasan deslizando (`lib/config/navigation/shell_branch_pager.dart`). Un gesto horizontal propio (Dismissible, scrub de gráfico, carrusel) le gana al cambio de pestaña en su zona: usarlo solo donde el usuario lo espera (filas que se borran, gráficos) y no cubrir toda la pantalla con uno.
