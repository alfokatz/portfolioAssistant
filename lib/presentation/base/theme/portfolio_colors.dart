import 'package:flutter/material.dart';

abstract final class PortfolioColors {
  // Backgrounds — true charcoal, no navy tint
  static const background = Color(0xFF0D0D10);
  static const surfaceCard = Color(0xFF141417);
  static const surfaceElevated = Color(0xFF1D1D22);

  // Borders — neutral alpha-based, no blue tint
  static const border = Color(0x12FFFFFF); // ~7% white

  // Accent — muted indigo instead of electric blue
  static const accentBlue = Color(0xFF6E6EF7);
  static const accentBlueDim = Color(0xFF5656D0);

  // Text
  static const textPrimary = Color(0xFFEEEEF2); // off-white
  static const textSecondary = Color(0xFF737380); // neutral gray, no blue tint

  // Semantic
  static const profit = Color(0xFF3ECF7A);
  static const loss = Color(0xFFEF5757);

  // Charts
  static const chartLine = Color(0xFF6E6EF7);
  static const chartGrid = Color(0x0AFFFFFF); // ~4% white
  static const benchmarkSp500 = Color(0xFF4E4E5A);
}
