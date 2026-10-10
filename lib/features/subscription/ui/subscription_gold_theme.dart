import 'package:flutter/material.dart';

/// Colores semánticos del tier Gold — compartidos entre paywall y settings.
abstract final class SubscriptionGoldTheme {
  static const accent = Color(0xFFF59E0B);
  static const accentLight = Color(0xFFFBBF24);
  static const ink = Color(0xFF1C1917);
  static const surfaceDark = Color(0xFF1C1917);
  static const surfaceMid = Color(0xFF292524);

  static const badgeGradient = LinearGradient(
    colors: [accent, accentLight],
  );

  static LinearGradient get cardGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [surfaceDark, surfaceMid.withValues(alpha: 0.95)],
      );
}
