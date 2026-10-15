import 'package:flutter/foundation.dart';

/// Qué proveedores de login ofrece la app.
///
/// Sign in with Apple queda apagado hasta que estén configurados el Service
/// ID / key en Apple Developer, el provider Apple en Supabase y la capability
/// en Xcode (ver docs/porty-rename-checklist.md). Se prende en el build con
/// `--dart-define=APPLE_SIGN_IN_ENABLED=true`. Solo se muestra en iOS: en
/// Android no es obligatorio y el flujo web confunde más de lo que ayuda.
abstract final class AuthProvidersConfig {
  static const appleSignInEnabled = bool.fromEnvironment(
    'APPLE_SIGN_IN_ENABLED',
  );

  static bool showsAppleSignIn(TargetPlatform platform) =>
      appleSignInEnabled && platform == TargetPlatform.iOS;
}
