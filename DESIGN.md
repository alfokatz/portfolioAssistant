---
name: Porty
description: Dashboard de portfolio premium silencioso para inversor retail casual
colors:
  background: "#FBFBFA"
  surface-card: "#FFFFFF"
  surface-elevated: "#F4F4F2"
  border: "#14000000"
  accent-blue: "#D98E5D"
  accent-blue-dim: "#A86A46"
  text-primary: "#2F3437"
  text-secondary: "#787774"
  profit: "#346538"
  loss: "#9F2F2D"
  profit-container: "#EDF3EC"
  loss-container: "#FDEBEC"
  chart-line: "#2F3437"
  chart-grid: "#08000000"
  benchmark-gray: "#B0ABA8"
typography:
  display:
    fontFamily: "Plus Jakarta Sans, system-ui, sans-serif"
    fontSize: "44px"
    fontWeight: 700
    lineHeight: 1.0
    letterSpacing: "-0.04em"
    fontFeature: "tnum"
  headline:
    fontFamily: "Plus Jakarta Sans, system-ui, sans-serif"
    fontSize: "20px"
    fontWeight: 600
    lineHeight: 1.2
    letterSpacing: "-0.015em"
  title:
    fontFamily: "Plus Jakarta Sans, system-ui, sans-serif"
    fontSize: "16px"
    fontWeight: 500
    lineHeight: 1.3
    letterSpacing: "-0.006em"
  body:
    fontFamily: "Plus Jakarta Sans, system-ui, sans-serif"
    fontSize: "16px"
    fontWeight: 400
    lineHeight: 1.55
  label:
    fontFamily: "Plus Jakarta Sans, system-ui, sans-serif"
    fontSize: "13px"
    fontWeight: 500
    lineHeight: 1.3
    letterSpacing: "0.008em"
rounded:
  sm: "6px"
  md: "10px"
  lg: "14px"
  xl: "18px"
  pill: "26px"
spacing:
  page-horizontal: "20px"
  section-gap: "28px"
  card-padding: "18px"
  touch-target: "44px"
components:
  button-primary:
    backgroundColor: "{colors.text-primary}"
    textColor: "{colors.surface-card}"
    typography: "{typography.title}"
    rounded: "{rounded.lg}"
    padding: "16px 24px"
    height: "52px"
  button-primary-disabled:
    backgroundColor: "{colors.text-primary}"
    textColor: "{colors.surface-card}"
    rounded: "{rounded.lg}"
    height: "52px"
  input-field:
    backgroundColor: "{colors.surface-card}"
    textColor: "{colors.text-primary}"
    typography: "{typography.body}"
    rounded: "{rounded.lg}"
    padding: "16px"
  input-field-chat:
    backgroundColor: "{colors.surface-card}"
    textColor: "{colors.text-primary}"
    typography: "{typography.body}"
    rounded: "{rounded.pill}"
    padding: "0 20px"
    height: "52px"
  button-send-chat:
    backgroundColor: "{colors.accent-blue}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.pill}"
    size: "52px"
  card-surface:
    backgroundColor: "{colors.surface-card}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.lg}"
    padding: "{spacing.card-padding}"
  pnl-badge-positive:
    backgroundColor: "{colors.profit-container}"
    textColor: "{colors.profit}"
    typography: "{typography.label}"
    rounded: "{rounded.sm}"
    padding: "4px 8px"
  pnl-badge-negative:
    backgroundColor: "{colors.loss-container}"
    textColor: "{colors.loss}"
    typography: "{typography.label}"
    rounded: "{rounded.sm}"
    padding: "4px 8px"
---

# Design System: Porty

## Overview

**Creative North Star: "The Quiet Ledger"**

Porty se ve como un cuaderno financiero bien editado: tipografía precisa, mucho aire, cifras que mandan. No compite por atención con neón ni gamificación; la confianza viene de la legibilidad y del silencio visual. El usuario casual abre la app, entiende su snapshot en segundos y, si lo necesita, llega al asistente IA sin fricción.

La densidad es moderada en mobile: padding horizontal generoso (20px), 28px entre secciones, cards solo cuando el affordance lo exige. Preferir filas editoriales planas (benchmark locked, settings rows) sobre cajas anidadas. Jerarquía tipográfica antes que color decorativo.

Rechaza explícitamente: fintech genérico navy+neón, AI slop (glassmorphism, gradient text, card grids idénticos), clones gamificados tipo Robinhood, scaffolding SaaS (eyebrows uppercase, 01/02/03).

**Key Characteristics:**
- Una sola familia tipográfica (Plus Jakarta Sans) en todo el producto
- Superficies planas con borde sutil, sin sombras en reposo
- Un único acento secundario cálido (terracota) para foco, links, iconografía IA y marca de Porty
- Fondo de app con un halo cálido difuminado (ver `AppBackgroundGradient`), pintado una sola vez detrás de todas las pantallas
- Números financieros con tabular figures y contraste AA+
- Touch targets ≥ 44px en tabs, chips de rango y filas navegables

## Colors

Paleta **Restrained**: neutros cálidos tenues + un acento secundario terracota (identidad de Porty) + semánticos profit/loss profundos (no neón).

**Nota de migración:** el acento secundario era azul editorial (#1F6C9F); se reemplazó por el mismo terracota cálido que ya se usaba como glow de Porty, para unificar todo el "color secundario" de la app en un solo tono. Los tokens `accent-blue`/`accent-blue-dim` (y `PortfolioColors.accentBlue`/`accentBlueDim` en código) mantienen el nombre histórico pero ya apuntan al terracota — no crear un accent azul nuevo.

### Primary
- **Warm Accent** (#D98E5D, token `accent-blue`): acciones primarias de foco, cursor de inputs, iconos del asistente IA, chip seleccionado, FAB. Raro en superficies grandes.
- **Warm Accent Dim** (#A86A46, token `accent-blue-dim`): estados secundarios sobre primaryContainer, links atenuados.

### Neutral
- **Warm Canvas** (#FBFBFA): scaffold background, app bar, fondo de scroll.
- **Pure Surface** (#FFFFFF): cards, inputs auth, bottom sheets, dialogs.
- **Elevated Mist** (#F4F4F2): fill de inputs globales, icon boxes sutiles, fondos de badges secundarios.
- **Charcoal Ink** (#2F3437): texto principal, línea de chart, botón primario auth (invertido: texto sobre blanco).
- **Muted Warm Gray** (#787774): labels, hints, subtítulos, chevrons, benchmark.
- **Whisper Border** (#14000000 / 8% black): bordes de cards, dividers, grid de charts.

### Tertiary (semantic)
- **Deep Profit Green** (#346538): PnL positivo, tertiary en ColorScheme.
- **Deep Loss Red** (#9F2F2D): PnL negativo, errores de validación.
- **Profit Container** (#EDF3EC): fondo de PnlBadge positivo.
- **Loss Container** (#FDEBEC): fondo de PnlBadge negativo.
- **Benchmark Gray** (#B0ABA8): línea S&P 500 en charts comparativos.

### Named Rules
**The One Accent Rule.** El terracota aparece en foco, selección e iconografía IA — nunca como fondo de pantalla completa saturado (el halo de `AppBackgroundGradient` es la única excepción intencional: un lavado ambiental muy tenue, no un fondo saturado).

**The Ink Button Rule.** El CTA primario de auth usa charcoal (#2F3437) sobre blanco, no el acento saturado. El acento queda para estados de foco, no para competir con el hero numérico.

### Dark mode — "The Quiet Ledger, de noche"

El oscuro no es el claro invertido ni un negro genérico: es la misma paleta Restrained, con los mismos roles, vista de noche. Fuente única: `PortfolioColorsDark` (`portfolio_colors.dart`), que alimenta `CustomColors.dark` y el `ColorScheme` oscuro. Ningún widget declara hex propios para oscuro.

| Token | Valor | OKLCH | Uso |
|---|---|---|---|
| background | #171614 | 0.200 0.004 70 | Canvas |
| surface-card | #1F1D1B | 0.232 0.005 70 | Cards, sheets, composer |
| surface-elevated | #282523 | 0.268 0.006 70 | Inputs, riel del segmentado, burbuja del usuario |
| inset | #23211F | 0.250 0.0055 70 | Bloques dentro de una card |
| border | marfil 10% | — | Bordes y divisores |
| text-primary | #E9E6E1 | 0.925 0.007 80 | 13,5:1 sobre card |
| text-secondary | #A7A29C | 0.715 0.010 75 | 6,6:1 sobre card |
| accent | #CE8456 | 0.68 0.11 52 | El terracota de Porty con un punto menos de luz, 5,7:1 sobre card |
| on-accent | #211711 | — | Tinta sobre el acento (FAB, send, CTA) |
| profit | #86C493 | 0.765 0.095 150 | Salvia, 8,3:1 |
| loss | #E5897F | 0.725 0.115 27 | Arcilla, 6,6:1 |

**The Warm Graphite Rule.** Los neutros oscuros llevan una pizca del tono terracota (C ≈ 0.005), igual que los cálidos del claro. Prohibido el negro puro (#000/#0F0F0F) y el gris neutro de plantilla (#1A1A1A/#242424): con texto casi blanco dan ~17:1, que vibra y se siente duro y genérico.

**Lighter Is Higher.** En oscuro la profundidad se comunica aclarando la superficie, en pasos chicos y parejos (L 0.20 → 0.23 → 0.27). Las sombras no se ven sobre grafito: el indicador del segmentado, la card destacada de Gold y los insets suben de luz o llevan borde, no sombra.

**Ivory, Not White.** Texto en marfil tibio, nunca #FFF ni blanco frío azulado. El secundario cumple AA en todas las superficies; los hints suben a 85% de opacidad (no 60%) para no caer debajo de 4,5:1.

**Muted Semantics.** Verde salvia y rojo arcilla, desaturados, con el mismo carácter editorial que los profundos del claro. Nada de verde semáforo (#5CB85C) ni rojo Material (#E57373).

**No Gradients At Night.** En oscuro no hay degradés: el halo de `AppBackgroundGradient` usa `haloStrength` 0, la card del total va lisa y el relleno del gráfico apenas se insinúa. Los glows de foco se multiplican por `glowScale` (0.35). Sobre grafito cualquier lavado terracota se lee como neón o mancha marrón.

**Porty's Terracotta, Dimmed.** En oscuro el terracota es el mismo que el del claro (mismo tono y croma: es el color de Porty) con un punto menos de luz (L 0.71 → 0.68): acento, FAB y Porty (`PortyAvatarPalette.brandDark`, que el avatar elige solo). Tal cual, sobre grafito brilla; con poco croma (arcilla) se ve lavado y deja de ser Porty.

**Quiet Chips.** En oscuro los círculos de ícono de las filas (Ajustes, Metas, títulos de las cards del chat) y las etiquetas neutras ("Recién empezás", el riesgo del plan) no van en terracota: ícono gris tibio sobre un escalón de grafito (tokens `chip` / `onChip`; en claro siguen en terracota sobre su tinte). El acento queda para acciones: FAB, enviar, "Editar", "Armar una meta", switches. Diez círculos terracota por pantalla sobre el grafito se leen flúor aunque el color sea el correcto.

**Ink On Accent.** Sobre un relleno terracota va la tinta `onAccent` (oscura), nunca el texto principal (marfil, ~1,9:1) ni blanco (~2,4:1).

## Typography

**Display / Body / Label Font:** Plus Jakarta Sans (bundled, weights 400–700) con fallback system-ui.

**Character:** Geométrica humanista, limpia y premium. Letter-spacing negativo en display/headlines; tabular figures (`FontFeature.tabularFigures()`) en todo valor monetario y porcentaje.

### Hierarchy
- **Display** (700, 44px / 34px hero, line-height 1.0–1.05, letter-spacing −0.04em a −0.025em): valor total del portfolio. Tabular figures obligatorio.
- **Headline** (600, 15–20px, line-height 1.2–1.3): títulos de sección ("Posiciones", settings group headers).
- **Title** (500–600, 14–16px): títulos de card, tabs activos, filas de lista.
- **Body** (400, 14–16px, line-height 1.5–1.55): copy, subtítulos de cards IA, formularios.
- **Label** (500, 10–13px, letter-spacing 0.1–0.4): badges PnL, time range chips, metadata de chart.

### Named Rules
**The Tabular Money Rule.** Toda cifra financiera (portfolio total, PnL absoluto, porcentajes, precios) usa tabular figures. Prohibido mezclar fuentes del sistema solo en números.

**The Single Family Rule.** Plus Jakarta Sans en toda la app. Sin display/body pairing; variación por peso y escala fija en px/rem, no clamp fluido.

## Elevation

Sistema **plano por defecto**. `elevation: 0` en cards, app bar, dialogs y botones. La profundidad se comunica con:
- Contraste tonal entre `background` → `surface-card` → `surface-elevated`
- Bordes de 0.5–1px en `border` (#14000000)
- Dividers a 0.5px entre filas editoriales

No hay vocabulario de box-shadow en reposo. Bottom sheets usan drag handle + radius xl (18px) sin sombra material.

### Named Rules
**The Flat-By-Default Rule.** Sombras están prohibidas en cards y listas. Si algo necesita jerarquía, sube un nivel de superficie o agrega borde — nunca drop shadow decorativo.

## Components

Componentes refinados y consistentes; estados hover/focus/disabled/loading en controles interactivos.

### Buttons
- **Shape:** esquinas suaves (14px / `radiusLg`)
- **Primary (auth):** fondo Charcoal Ink (#2F3437), texto Pure Surface, altura 52px, ancho completo, sin elevación
- **Disabled:** mismo fondo al 35% opacidad, spinner 20px blanco en loading
- **Secondary (OAuth):** fondo Pure Surface, borde 1px Whisper Border, texto Charcoal Ink w600, misma altura y radius que el resto de los botones de auth (48px / 14px). Sin relleno gris. Código: `SocialSignInButton`.
- **Sign in with Apple:** estilo oficial de Apple (negro con texto/logo blanco en light, blanco con negro en dark), mismo alto y radius que el de Google, arriba de Google y solo en iOS. Es la única excepción a los tokens: Apple no permite teñirlo. Código: `AppleSignInButton`.
- **Ghost:** preferir `TextButton` con `textSecondary` o filas `InkWell` planas

### Login (Porty)
- **Fondo:** el mismo halo de `AppBackgroundGradient` que el resto de la app (lo pinta la ruta). Sin superficie propia.
- **Identidad:** `PortyAvatar` (el mismo del header del chat) a 60px + wordmark "Porty" (24px w700 Charcoal Ink) + línea "Tu asistente de portfolio" en textSecondary. Es la versión grande del header del chat.
- **Saludo:** una frase de Porty con la forma de su respuesta en el chat: texto suelto, 20px w500, sin burbuja ni borde lateral. Se tipea una vez por sesión de la app (~0,7 s); al cambiar de pestaña cambia con fade through.
- **Teclado abierto:** avatar a 32px, wordmark a 17px w600, línea y saludo colapsan (220ms ease-out-cubic) para que campos y CTA entren sin scroll en un iPhone SE.
- **Errores:** texto loss debajo del campo o del CTA + haptic de error leve. Nunca diálogos ni snackbars.
- **Entrada a la app:** fade through opaco (`FadeThroughPage`): el fondo tapa la pantalla saliente antes de que aparezca la nueva.

### Chips / Segmented controls
- **TimeRangeSelector:** fila de labels, sin caja contenedora; activo = `textPrimary` w700, inactivo = `textSecondary` w500; altura táctil 44px
- **Auth tabs:** underline 2px animado (220ms ease-out-cubic), activo w700, inactivo textSecondary al 65% w500

### Cards / Containers
- **Corner Style:** 14px (`radiusLg`)
- **Background:** Pure Surface (#FFFFFF) sobre Warm Canvas
- **Shadow Strategy:** ninguna (ver Elevation)
- **Border:** 1px Whisper Border
- **Internal Padding:** 18px estándar (`cardPadding`); cards IA usan 14px vertical para ligereza
- **Excepción editorial:** benchmark locked y settings rows sin card box — label + fila + divider

### Inputs / Fields
- **Style:** fondo Pure Surface, borde Whisper Border, radius 14px, padding 16px
- **Focus:** borde Warm Accent 1.4–1.5px, cursor terracota
- **Error:** borde Deep Loss Red, texto error en bodySmall loss color
- **Hint:** textSecondary al 60% en theme global; auth usa textSecondary pleno

### Chat Composer (Porty)
Variante propia del input del chat (`input-field-chat` + `button-send-chat`), separada del `inputDecorationTheme` global: los inputs de formularios y auth no cambian. Código: `AssistantComposerField` + `_SendButton` en `assistant_screen.dart`.
- **Shape:** píldora, radius `pill` (26px = mitad del alto de 52px); al crecer a multilínea (máx. 4) queda estadio. Send button circular del mismo diámetro (52px).
- **Background:** Pure Surface opaco (dark: surface-card #1F1D1B). Sin blur ni transparencia — la sensación de "flotante" sale del contraste con Warm Canvas + halo de `AppBackgroundGradient` y del aire alrededor, no de elevación.
- **Aire:** 24px lateral (más que los 20px de página), 12px arriba, 20px abajo por encima del safe area.
- **Reposo:** borde 1px Whisper Border, sin sombra.
- **Focus:** borde Warm Accent 1.5px + glow terracota tenue (alpha 0.16, blur 10px), animado 180ms. Es feedback de interacción, no elevación: única sombra permitida en inputs y solo mientras hay foco.

### Sugerencias iniciales del chat (Porty)
El chat vacío ofrece preguntas para empezar. Código: `AssistantStarterSuggestions` (`assistant_starter_suggestions.dart`).
- **Forma:** un solo grupo como los de Ajustes: card Pure Surface, borde 1px Whisper Border, radius 14px, filas separadas por divisores alineados al texto. No una pila de cajas grises iguales (se leían deshabilitadas y repetían el mismo bloque cuatro veces).
- **Fila:** círculo de 32px con el ícono del tipo de pregunta (cartera, concepto, mercado, inversión) en los tokens `chip` / `onChip`; texto bodyMedium w500 Charcoal Ink (hasta 2 líneas); flecha ↗ en textSecondary a la derecha, la misma de los chips de seguimiento de las cards: tocar envía la pregunta. Alto mínimo 56px.
- **Encabezado:** "Podés empezar por acá" en labelLarge textSecondary, sin dos puntos, alineado como el título de un grupo de Ajustes.
- **Deshabilitado** (turno en curso, auto-typing): filas al 50% de opacidad, animado 180ms.
- **Acento:** el destello terracota no se repite por fila; el terracota queda para enviar y para Porty.
- **Contenido:** cuatro preguntas que cubren lo que promete el saludo (cartera, conceptos, mercado, metas), elegidas por plan (`AssistantProvider.starterChipKeysFor`). Ninguna lleva a un paywall: gastar una consulta para ver "esto es Premium" es la peor primera impresión. Preferir preguntas sobre la cartera del usuario ("¿Estoy bien diversificado?") antes que genéricas ("¿Qué es diversificar?") o sobre un ticker al azar, y nada que suene a dato para operar ("Tengo $500 para invertir en tech"). Sin jerga (P&L) en las sugerencias.

### Metas (Porty)
La pestaña Metas tiene la forma de las pantallas donde Porty acompaña (Posiciones cerradas, Agregar posición), no una pila de cards. Código: `GoalsScreen` + `GoalsVerdict` (`features/goals/view/`).
- **Arriba, Porty:** `PortySays` con una frase sobre TODAS las metas juntas, armada con los números de `GoalProgress` (nunca la escribe el modelo). Lo que más pide atención va primero: una vencida, después la atrasada que más aporte necesita, después "vas en camino" con el aporte del mes entre todas. Cara: preocupado si algo viene atrasado o vencido, contento si van en camino, tranquilo si todas recién se guardaron. Con más de una meta, una nota: "Entre todas llevás X de Y".
- **Las metas:** filas directo sobre el fondo, sin card ("Earn every card"), agrupadas en "En curso" y "Logradas" y separadas por divisores alineados al texto, como las ventas de Posiciones cerradas. Alineadas al margen de la página. Fila:
  - **Anillo de 52px** (trazo 4px, color del veredicto, fondo `textSecondary` al 16%, un avance mínimo se ve como un punto) alrededor de un disco `chip` con el ícono de lo que es la meta (`GoalIcon`, familia *rounded*: avión para un viaje, auto, compu, celular, casa, escudo para emergencia, chanchito para "juntar"…; sin pista, el del tipo). El mismo ícono va en las cards del chat.
  - **Renglón 1:** nombre (16px w700) y, a la derecha, el porcentaje (16px w700 tabular; verde si está cumplida).
  - **Renglón 2:** lo juntado en w700 + "de Y" en secundario, y a la derecha el aporte por mes.
  - **Renglón 3, a todo el ancho:** punto de 6px y veredicto en su color + "faltan 16 meses" / "faltan 8 años" (meses hasta los dos años, después años redondeados).
  - Tocar abre el detalle, mantener apretada sus opciones, deslizar a la izquierda la borra con confirmación.
- **Armar otra:** la última fila del grupo, con el + en terracota (en oscuro, círculo en grafito y solo el ícono en terracota) y la flecha ↗ de las sugerencias del chat: abre el chat con la pregunta.
- **Sin metas:** Porty explica qué hace ("Contame qué querés lograr y te armo un plan…") y debajo, "Podés empezar por una de estas": cuatro ideas (fondo de emergencia, viaje, comprarse algo, jubilación) como filas que abren el chat con esa pregunta. Nunca una caja vacía con un botón.
- **Cargando:** skeleton con la misma estructura (Porty + filas), no un loader en el medio.
- **Títulos de grupo:** labelLarge `textSecondary` en minúscula inicial, nunca mayúsculas espaciadas.

### Confirmaciones (`ConfirmSheet`)
Nunca un `AlertDialog` de Material. Una hoja desde abajo, como "Desconectar eToro": Porty arriba (preocupado si la acción destruye algo), título y explicación centrados, botón lleno de 52 px / radius 14 que dice exactamente lo que pasa ("Borrar meta", "Eliminar AAPL", nunca "Aceptar") en Deep Loss Red si destruye y en Charcoal Ink si no, y "Cancelar" debajo en texto secundario. Código: `ConfirmSheet.show` (`presentation/shared/widgets/confirm_sheet.dart`).

### Navigation
- **App bar:** transparente (revela `AppBackgroundGradient` detrás), título titleMedium w600 charcoal, iconos 20px, elevation 0
- **Bottom nav bar:** pill flotante translúcida sobre el fondo, ítem activo en Charcoal Ink; FAB en Warm Accent
- **Pestañas por gesto:** Inicio, Porty, Metas y Ajustes se pasan deslizando el dedo, como en Instagram (`ShellBranchPager`). Cambia de pestaña al pasar la mitad, sin rebote en los bordes; tocar la barra salta directo con la entrada corta (cae y se asienta), deslizar no la repite. Lo de adentro que también se arrastra en horizontal (gráficos con scrub, filas que se borran deslizando, chips con scroll) gana el gesto. Cambiar de pestaña cierra el teclado.
- **Settings rows:** icon box 36px en Elevated Mist, label bodyLarge w500, value bodyMedium secondary, chevron 14px
- **Bottom sheet:** radius xl superior, drag handle border color, fondo surface-card

### PnL Badge (signature)
- **Positivo:** fondo Profit Container, texto Deep Profit Green, radius 4px, padding 4×8px, labelMedium w600 tabular
- **Negativo:** fondo Loss Container, texto Deep Loss Red, misma geometría

### Portfolio Hero (signature)
- Label labelLarge secondary → Display 44px bold tabular → fila PnL (titleMedium semántico + PnlBadge) → chart area line sin card wrapper pesado

## Do's and Don'ts

### Do:
- **Do** usar Plus Jakarta Sans empaquetada localmente (`assets/fonts/`) con `allowRuntimeFetching = false`.
- **Do** mantener contraste AA+ en body text (#787774 sobre #FBFBFA cumple para large text; subir a #2F3437 para copy crítico).
- **Do** respetar touch targets de 44px en tabs, time range y filas settings.
- **Do** preferir filas editoriales planas cuando el contenido es navegación o upsell (benchmark locked).
- **Do** animar transiciones de estado en 150–250ms (ease-out-cubic) con respeto a reduced motion.

### Don't:
- **Don't** usar fintech genérico: navy + verde neón, cards apiladas, hero metrics (número grande + label chico + stats), gradientes decorativos.
- **Don't** caer en AI slop: glassmorphism por defecto, bordes laterales de acento, gradient text, card grids idénticos.
- **Don't** imitar clones gamificados tipo Robinhood/eToro: UI agresiva, colores saturados, sensación de casino/trading.
- **Don't** usar scaffolding SaaS: eyebrows uppercase en cada sección, numeración 01/02/03 como decoración.
- **Don't** anidar cards dentro de cards. Un borde, una superficie.
- **Don't** poner sombras en reposo. Superficies planas siempre.
- **Don't** usar el acento terracota como fondo de CTA principal saturado; reservarlo para foco, marca IA y el halo ambiental sutil de `AppBackgroundGradient`.
