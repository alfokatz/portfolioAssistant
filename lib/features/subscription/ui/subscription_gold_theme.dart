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

  /// En oscuro el piedra (#1C1917) se perdía contra el fondo grafito y la
  /// card destacada dejaba de destacarse: sube un escalón, con un dejo
  /// ámbar, por encima de las cards comunes.
  static const surfaceRaised = Color(0xFF362E22);
  static const surfaceRaisedEnd = Color(0xFF2B261D);

  static Color surfaceFor(Brightness brightness) =>
      brightness == Brightness.dark ? surfaceRaised : surfaceDark;

  static LinearGradient cardGradientFor(Brightness brightness) =>
      brightness == Brightness.dark
          ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [surfaceRaised, surfaceRaisedEnd],
          )
          : cardGradient;

  static LinearGradient get cardGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [surfaceDark, surfaceMid.withValues(alpha: 0.95)],
      );
}
