---
name: PortfolioAI
description: Dashboard de portfolio premium silencioso para inversor retail casual
colors:
  background: "#FBFBFA"
  surface-card: "#FFFFFF"
  surface-elevated: "#F4F4F2"
  border: "#14000000"
  accent-blue: "#1F6C9F"
  accent-blue-dim: "#2E5E87"
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

# Design System: PortfolioAI

## Overview

**Creative North Star: "The Quiet Ledger"**

PortfolioAI se ve como un cuaderno financiero bien editado: tipografía precisa, mucho aire, cifras que mandan. No compite por atención con neón ni gamificación; la confianza viene de la legibilidad y del silencio visual. El usuario casual abre la app, entiende su snapshot en segundos y, si lo necesita, llega al asistente IA sin fricción.

La densidad es moderada en mobile: padding horizontal generoso (20px), 28px entre secciones, cards solo cuando el affordance lo exige. Preferir filas editoriales planas (benchmark locked, settings rows) sobre cajas anidadas. Jerarquía tipográfica antes que color decorativo.

Rechaza explícitamente: fintech genérico navy+neón, AI slop (glassmorphism, gradient text, card grids idénticos), clones gamificados tipo Robinhood, scaffolding SaaS (eyebrows uppercase, 01/02/03).

**Key Characteristics:**
- Una sola familia tipográfica (Plus Jakarta Sans) en todo el producto
- Superficies planas con borde sutil, sin sombras en reposo
- Acento azul editorial reservado para foco, links e iconografía IA
- Números financieros con tabular figures y contraste AA+
- Touch targets ≥ 44px en tabs, chips de rango y filas navegables

## Colors

Paleta **Restrained**: neutros cálidos tenues + un acento azul editorial + semánticos profit/loss profundos (no neón).

### Primary
- **Editorial Blue** (#1F6C9F): acciones primarias de foco, cursor de inputs, iconos del asistente IA, chip seleccionado. Raro en superficies grandes.
- **Editorial Blue Dim** (#2E5E87): estados secundarios sobre primaryContainer, links atenuados.

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
**The One Accent Rule.** El azul editorial aparece en foco, selección e iconografía IA — nunca como fondo de pantalla completa ni gradiente decorativo.

**The Ink Button Rule.** El CTA primario de auth usa charcoal (#2F3437) sobre blanco, no azul saturado. El acento azul queda para estados de foco, no para competir con el hero numérico.

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
- **Secondary / Ghost:** no estandarizado aún; preferir `TextButton` con `textSecondary` o filas `InkWell` planas

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
- **Focus:** borde Editorial Blue 1.4–1.5px, cursor azul
- **Error:** borde Deep Loss Red, texto error en bodySmall loss color
- **Hint:** textSecondary al 60% en theme global; auth usa textSecondary pleno

### Navigation
- **App bar:** fondo Warm Canvas, título titleMedium w600 charcoal, iconos 20px, elevation 0
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
- **Don't** usar acento azul como fondo de CTA principal; reservarlo para foco y marca IA.
