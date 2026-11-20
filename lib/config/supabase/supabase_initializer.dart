import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:portfolio_assistant/config/env/app_env.dart';
import 'package:portfolio_assistant/config/supabase/clock_skew_retry_client.dart';
import 'package:portfolio_assistant/config/supabase/secure_auth_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Inicializa el cliente global de Supabase desde [AppEnv] (`--dart-define-from-file`).
class SupabaseInitializer {
  SupabaseInitializer._();

  static Future<void> initialize() async {
    AppEnv.ensureValid();
    final url = AppEnv.supabaseUrl;
    final anonKey = AppEnv.supabaseAnonKey;

    await Supabase.initialize(
      url: url,
      publishableKey: anonKey,
      httpClient: ClockSkewRetryClient(),
      authOptions: FlutterAuthClientOptions(
        // PKCE: el `code` que vuelve por deep link no sirve sin el verifier
        // que quedó en el dispositivo (otra app que registre el mismo
        // esquema no puede canjearlo).
        authFlowType: AuthFlowType.pkce,
        // En web no hay Keychain: queda el storage por defecto del navegador.
        localStorage: kIsWeb
            ? null
            : SecureSessionStorage(
                // La misma key que usa supabase_flutter por defecto, para
                // migrar la sesión guardada sin desloguear a nadie.
                persistSessionKey:
                    'sb-${Uri.parse(url).host.split('.').first}-auth-token',
              ),
        pkceAsyncStorage: kIsWeb ? null : const SecurePkceStorage(),
      ),
    );
  }
}
