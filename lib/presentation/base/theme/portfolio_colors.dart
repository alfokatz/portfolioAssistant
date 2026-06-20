import 'package:flutter/material.dart';

abstract final class PortfolioColors {
  // ── Fondos ──────────────────────────────────────────────────────────────
  static const background      = Color(0xFFFBFBFA);  // warm off-white
  static const surfaceCard     = Color(0xFFFFFFFF);  // pure white
  static const surfaceElevated = Color(0xFFF4F4F2);  // light input bg

  // ── Bordes ──────────────────────────────────────────────────────────────
  static const border = Color(0x14000000); // 8% black alpha

  // ── Acento — azul editorial desaturado ───────────────────────────────────
  static const accentBlue    = Color(0xFF1F6C9F);
  static const accentBlueDim = Color(0xFF2E5E87);

  // ── Texto ────────────────────────────────────────────────────────────────
  static const textPrimary   = Color(0xFF2F3437);  // off-black charcoal
  static const textSecondary = Color(0xFF787774);  // muted warm gray

  // ── Semántico ────────────────────────────────────────────────────────────
  static const profit = Color(0xFF346538);  // editorial deep green
  static const loss   = Color(0xFF9F2F2D);  // editorial deep red

  // ── Charts ───────────────────────────────────────────────────────────────
  static const chartLine      = Color(0xFF2F3437);  // charcoal
  static const chartGrid      = Color(0x08000000);  // 3% black
  static const benchmarkSp500 = Color(0xFFB0ABA8);  // warm gray
}
