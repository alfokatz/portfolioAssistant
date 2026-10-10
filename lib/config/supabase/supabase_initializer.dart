import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:portfolio_assistant/config/supabase/clock_skew_retry_client.dart';
import 'package:portfolio_assistant/config/supabase/secure_auth_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Inicializa el cliente global de Supabase desde variables `.env`.
class SupabaseInitializer {
  SupabaseInitializer._();

  static Future<void> initialize() async {
    final url = dotenv.env['SUPABASE_URL']?.trim();
    final anonKey = dotenv.env['SUPABASE_ANON_KEY']?.trim();

    if (url == null || url.isEmpty) {
      throw StateError('Falta SUPABASE_URL en el archivo .env del flavor activo.');
    }
    if (anonKey == null || anonKey.isEmpty) {
      throw StateError(
        'Falta SUPABASE_ANON_KEY en el archivo .env del flavor activo.',
      );
    }

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
