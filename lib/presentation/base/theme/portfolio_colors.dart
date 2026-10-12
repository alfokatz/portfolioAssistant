import 'package:flutter/material.dart';

abstract final class PortfolioColors {
  // ── Fondos ──────────────────────────────────────────────────────────────
  static const background = Color(0xFFFBFBFA); // warm off-white
  static const surfaceCard = Color(0xFFFFFFFF); // pure white
  static const surfaceElevated = Color(0xFFF4F4F2); // light input bg

  // ── Bordes ──────────────────────────────────────────────────────────────
  static const border = Color(0x14000000); // 8% black alpha

  // ── Acento secundario único de la app — terracota cálido ────────────────
  // `accentBlue`/`accentBlueDim` mantienen su nombre histórico (usado en
  // ~30 archivos) pero ya no son azules: son el mismo acento cálido que
  // `accentWarm`, para que todo foco, selección e ícono secundario de la
  // app comparta un solo color, sin tener que tocar cada call site.
  static const accentBlue = Color(0xFFD98E5D);
  static const accentBlueDim = Color(0xFFA86A46);

  // ── Acento cálido — glow del asistente (Porty) ───────────────────────────
  static const accentWarm = Color(0xFFD98E5D); // terracota editorial

  // ── Borde diferenciado para tarjetas generadas por el asistente ─────────
  static const aiCardBorder = Color(0x59D98E5D); // accentWarm @ 35% alpha

  // ── Texto ────────────────────────────────────────────────────────────────
  static const textPrimary = Color(0xFF2F3437); // off-black charcoal
  static const textSecondary = Color(0xFF787774); // muted warm gray

  // ── Semántico ────────────────────────────────────────────────────────────
  static const profit = Color(0xFF346538); // editorial deep green
  static const loss = Color(0xFF9F2F2D); // editorial deep red

  // ── Charts ───────────────────────────────────────────────────────────────
  static const chartLine = Color(0xFF2F3437); // charcoal
  static const chartGrid = Color(0x08000000); // 3% black
  static const benchmarkSp500 = Color(0xFFB0ABA8); // warm gray
}

/// Paleta del modo oscuro: la misma "Quiet Ledger" que el claro, de noche.
///
/// No es la paleta clara invertida ni un negro genérico. Las reglas:
/// - **Neutros tibios, nunca negro puro.** Grafito con una pizca del tono
///   terracota (OKLCH C ≈ 0.005, H ≈ 70), igual que los neutros cálidos del
///   claro. El negro puro con texto casi blanco da un contraste de ~17:1 que
///   "vibra" (halation) y se siente duro; acá el texto principal queda en
///   ~13,5:1 sobre las cards.
/// - **La profundidad sube con la luz.** background → surfaceCard →
///   surfaceElevated aclaran de a pasos chicos y parejos (L 0.20 → 0.23 →
///   0.27): en oscuro una superficie "más arriba" es más clara, no tiene
///   sombra.
/// - **Texto en marfil, no en blanco frío.** El texto principal es un
///   off-white tibio; el secundario, un gris cálido que cumple AA (≥ 6:1)
///   en todas las superficies.
/// - **Semánticos apagados.** Verde salvia y rojo arcilla, con el mismo
///   carácter editorial que los profundos del claro: nada de verde semáforo
///   ni rojo Material.
/// - **Sin degradés.** En oscuro no hay halo de fondo ni brillo en las
///   cards, y los glows de foco bajan (ver `CustomColors.glowScale`):
///   sobre fondo oscuro cualquier degradé terracota se lee como neón, y un
///   terracota saturado, como flúor.
abstract final class PortfolioColorsDark {
  // ── Fondos (grafito tibio, de abajo hacia arriba) ───────────────────────
  static const background = Color(0xFF171614); // oklch(0.200 0.004 70)
  static const surfaceCard = Color(0xFF1F1D1B); // oklch(0.232 0.005 70)
  static const surfaceElevated = Color(0xFF282523); // oklch(0.268 0.006 70)

  /// Bloques internos de una card: medio escalón por encima de la card
  /// (un bloque más oscuro que la card se leía como un agujero negro).
  static const inset = Color(0xFF23211F); // oklch(0.250 0.0055 70)

  // ── Bordes (marfil translúcido, no blanco puro) ─────────────────────────
  static const border = Color(0x1AFFF6EC); // ~10% marfil
  static const chartGrid = Color(0x0FFFF6EC); // ~6% marfil
  static const track = Color(0x14FFF6EC); // fondo de barras / anillos

  // ── Acento: terracota apagado, tipo arcilla ─────────────────────────────
  // Mismo tono que el del claro, con mucho menos croma: sobre grafito un
  // terracota saturado se ve flúor (el FAB, Porty, las etiquetas). Sigue
  // cumpliendo AA como texto (6,2:1 sobre card).
  static const accent = Color(0xFFC09479); // oklch(0.70 0.065 52) · 6,2:1
  static const accentDim = Color(0xFFA47C66); // oklch(0.62 0.06 50) · 4,5:1
  static const onAccent = Color(0xFF211711); // tinta sobre el acento · 6,5:1
  static const aiCardBorder = Color(0x4DC09479); // accent @ 30%

  // ── Texto ────────────────────────────────────────────────────────────────
  static const textPrimary = Color(0xFFE9E6E1); // marfil · 13,5:1 en card
  static const textSecondary = Color(0xFFA7A29C); // gris tibio · 6,6:1

  // ── Semántico ────────────────────────────────────────────────────────────
  static const profit = Color(0xFF86C493); // salvia · 8,3:1 en card
  static const loss = Color(0xFFE5897F); // arcilla · 6,6:1 en card
  static const profitContainer = Color(0xFF2B3129); // profit @ 12% en card
  static const lossContainer = Color(0xFF372A27); // loss @ 12% en card

  // ── Charts ───────────────────────────────────────────────────────────────
  static const chartLine = textPrimary;
  static const benchmarkSp500 = Color(0xFF807B76); // ≥ 3:1 (no es texto)
}
