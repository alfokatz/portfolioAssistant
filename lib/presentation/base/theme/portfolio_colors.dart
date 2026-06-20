import 'package:flutter/material.dart';

abstract final class PortfolioColors {
  // ── Fondos ──────────────────────────────────────────────────────────────
  static const background = Color(0xFF0F0F11);      // charcoal neutro
  static const surfaceCard = Color(0xFF161618);      // elevación mínima
  static const surfaceElevated = Color(0xFF1E1E22);  // superficie elevada

  // ── Bordes ──────────────────────────────────────────────────────────────
  static const border = Color(0x14FFFFFF); // 8% white alpha — sin tint de color

  // ── Acento único — indigo desaturado (mantiene nombre por compatibilidad) ─
  static const accentBlue = Color(0xFF5E5CE6);     // Apple-style indigo
  static const accentBlueDim = Color(0xFF4845C7);

  // ── Texto ────────────────────────────────────────────────────────────────
  static const textPrimary = Color(0xFFEDEDF0);    // off-white editorial
  static const textSecondary = Color(0xFF6E6E76);  // gris neutro

  // ── Semántico ────────────────────────────────────────────────────────────
  static const profit = Color(0xFF30D158);  // Apple green
  static const loss = Color(0xFFFF453A);    // Apple red

  // ── Charts ───────────────────────────────────────────────────────────────
  static const chartLine = Color(0xFF5E5CE6);
  static const chartGrid = Color(0x0AFFFFFF);      // 4% white
  static const benchmarkSp500 = Color(0xFF48484F);
}
