/// Deep links para callbacks de autenticación de Supabase.
///
/// Agregá estas URLs en Supabase Dashboard → Authentication → URL Configuration
/// → Redirect URLs (y en `additional_redirect_urls` de `supabase/config.toml`).
///
/// Dos esquemas, a propósito:
/// - [oauthScheme] lo captura `flutter_web_auth_2` (ASWebAuthenticationSession
///   en iOS, Auth Tab / `CallbackActivity` en Android). No se registra en
///   `Info.plist` ni en el intent-filter de `MainActivity`: así ningún otro
///   handler de deep links (el de supabase_flutter incluido) consume el code.
/// - [appScheme] es el de los links que llegan por email (confirmar cuenta,
///   restablecer contraseña). Lo abre el sistema y lo procesa supabase_flutter
///   (`app_links`), que intercambia el code PKCE y emite el evento de auth.
abstract final class SupabaseRedirectUrl {
  static const oauthScheme = 'porty-oauth';
  static const appScheme = 'porty';

  /// Vuelta del login con Google (y Apple vía web).
  static const oauthCallback = '$oauthScheme://callback';

  /// Link de "confirmá tu email" al registrarse.
  static const emailConfirmationCallback = '$appScheme://login-callback';

  /// Link de "restablecé tu contraseña".
  static const passwordRecoveryCallback = '$appScheme://reset-password';
}
