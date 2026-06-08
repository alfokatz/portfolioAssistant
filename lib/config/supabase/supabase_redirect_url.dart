/// Deep links para callbacks de autenticación de Supabase.
///
/// Agregá estas URLs en Supabase Dashboard → Authentication → URL Configuration
/// → Redirect URLs.
abstract final class SupabaseRedirectUrl {
  static const oauthCallback = 'com.example.portfolioassistant://login-callback';
  static const passwordRecoveryCallback =
      'com.example.portfolioassistant://reset-password';
}
