/// Configuración del entorno, fijada en tiempo de build con
/// `--dart-define-from-file=env/<entorno>.json` (ver
/// docs/runbooks/build-entornos.md). Es la única fuente: no hay `.env` en
/// los assets.
///
/// Sin defines (tests, `flutter test`) los valores quedan vacíos y cada
/// cliente HTTP trabaja sin backend, igual que antes con el `.env` sin cargar.
abstract final class AppEnv {
  static const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const _appEnv = String.fromEnvironment('APP_ENV');
  static const _revenueCatAppleApiKey = String.fromEnvironment(
    'REVENUECAT_APPLE_API_KEY',
  );
  static const _revenueCatGoogleApiKey = String.fromEnvironment(
    'REVENUECAT_GOOGLE_API_KEY',
  );
  static const _openAiModel = String.fromEnvironment('OPENAI_MODEL');
  static const _yahooCacheTtlMinutes = String.fromEnvironment(
    'YAHOO_CACHE_TTL_MINUTES',
  );
  static const _supabaseFunctionsRegion = String.fromEnvironment(
    'SUPABASE_FUNCTIONS_REGION',
  );

  static const develop = 'develop';
  static const prod = 'prod';

  /// URL del proyecto (branch) de Supabase; vacía sin defines.
  static String get supabaseUrl => _supabaseUrl.trim();

  static String get supabaseAnonKey => _supabaseAnonKey.trim();

  /// Anon key o `null` si no está (los clientes HTTP la mandan solo si hay).
  static String? get supabaseAnonKeyOrNull => _orNull(_supabaseAnonKey);

  /// `develop` o `prod`. Sin `APP_ENV` se asume `develop`: un build mal
  /// armado muestra la pastilla DEV en vez de pasar por prod.
  static String get appEnv {
    final v = _appEnv.trim();
    return v.isEmpty ? develop : v;
  }

  static bool get isProd => appEnv == prod;

  static String? get revenueCatAppleApiKey => _orNull(_revenueCatAppleApiKey);

  static String? get revenueCatGoogleApiKey =>
      _orNull(_revenueCatGoogleApiKey);

  /// Modelo de OpenAI que pide la app; `null` = el default de cada servicio.
  static String? get openAiModel => _orNull(_openAiModel);

  /// TTL de la caché de cotizaciones de Yahoo (default 10 minutos).
  static int get yahooCacheTtlMinutes =>
      int.tryParse(_yahooCacheTtlMinutes.trim()) ?? 10;

  /// Región fija para las edge functions (p. ej. `us-east-1`); `null` = la
  /// que elija Supabase.
  static String? get supabaseFunctionsRegion =>
      _orNull(_supabaseFunctionsRegion);

  /// Falla en el arranque si el build salió sin la config mínima: así nunca
  /// llega a TestFlight o a la tienda una app sin backend.
  static void ensureValid() {
    final missing = [
      if (supabaseUrl.isEmpty) 'SUPABASE_URL',
      if (supabaseAnonKey.isEmpty) 'SUPABASE_ANON_KEY',
    ];
    if (missing.isNotEmpty) {
      throw StateError(
        'Falta ${missing.join(' y ')}: buildeá con '
        '--dart-define-from-file=env/<entorno>.json '
        '(ver docs/runbooks/build-entornos.md).',
      );
    }
    if (appEnv != develop && appEnv != prod) {
      throw StateError(
        'APP_ENV="$appEnv" no es válido: tiene que ser "$develop" o "$prod".',
      );
    }
  }

  static String? _orNull(String raw) {
    final v = raw.trim();
    return v.isEmpty ? null : v;
  }
}
