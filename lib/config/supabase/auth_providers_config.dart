import 'package:flutter/foundation.dart';

/// Qué proveedores de login ofrece la app.
///
/// Sign in with Apple: hoja nativa en iOS (key de Apple, provider Apple en
/// Supabase con el bundle id y la capability en Runner.entitlements, ver
/// docs/porty-rename-checklist.md). Prendido por defecto; para apagarlo de
/// emergencia en un build: `--dart-define=APPLE_SIGN_IN_ENABLED=false`. Solo
/// se muestra en iOS: en Android no es obligatorio y el flujo web confunde más
/// de lo que ayuda.
abstract final class AuthProvidersConfig {
  static const appleSignInEnabled = bool.fromEnvironment(
    'APPLE_SIGN_IN_ENABLED',
    defaultValue: true,
  );

  static bool showsAppleSignIn(TargetPlatform platform) =>
      appleSignInEnabled && platform == TargetPlatform.iOS;
}
