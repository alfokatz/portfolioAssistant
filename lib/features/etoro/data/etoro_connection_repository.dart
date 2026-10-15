import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_client_provider.dart';
import 'package:portfolio_assistant/features/etoro/data/etoro_sync_client.dart';
import 'package:portfolio_assistant/features/etoro/domain/etoro_connection.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Esquema del deep link con el que la edge function devuelve al usuario a
/// la app al terminar la autorización (`ETORO_APP_REDIRECT`). Distinto del de
/// login de Supabase: así el manejo de deep links de auth no lo intercepta.
const etoroCallbackScheme = 'porty-etoro';

/// Abre la autorización de eToro en el navegador del sistema (no un
/// WebView): ASWebAuthenticationSession en iOS, Custom Tabs en Android.
/// Devuelve el deep link de vuelta, o `null` si el usuario lo cerró.
abstract class EtoroAuthLauncher {
  Future<Uri?> authenticate(Uri url);
}

class SystemBrowserEtoroAuthLauncher implements EtoroAuthLauncher {
  const SystemBrowserEtoroAuthLauncher();

  @override
  Future<Uri?> authenticate(Uri url) async {
    try {
      final result = await FlutterWebAuth2.authenticate(
        url: url.toString(),
        callbackUrlScheme: etoroCallbackScheme,
        // Sin cookies compartidas con Safari: la sesión de eToro no queda
        // guardada en el navegador del usuario.
        options: const FlutterWebAuth2Options(preferEphemeral: true),
      );
      return Uri.parse(result);
    } on PlatformException catch (e) {
      if (e.code == 'CANCELED') return null;
      rethrow;
    }
  }
}

/// La conexión se LEE directo de la tabla (RLS: cada usuario la suya); las
/// acciones pasan por la edge function, que es la única que ve los tokens.
class EtoroConnectionRepository {
  EtoroConnectionRepository({
    required SupabaseClient? Function() client,
    required EtoroSyncClient syncClient,
  }) : _client = client,
       _syncClient = syncClient;

  /// Diferido: sin Supabase inicializado (tests de pantallas) no hay
  /// conexión que leer, y eso no debe romper nada.
  final SupabaseClient? Function() _client;
  final EtoroSyncClient _syncClient;

  Future<EtoroConnection> load() async {
    final client = _client();
    if (client == null || client.auth.currentUser == null) {
      return EtoroConnection.notConnected;
    }
    final row =
        await client
            .from('etoro_connections')
            .select(
              'status, last_sync_at, last_sync_status, last_error_type, last_result',
            )
            .maybeSingle();
    if (row == null) return EtoroConnection.notConnected;
    return EtoroConnection.fromRow(row);
  }

  Future<Uri> startConnect() => _syncClient.startConnect();

  Future<({EtoroImportResult result, bool throttled})> sync() =>
      _syncClient.sync();

  Future<void> disconnect({required bool keepAsManual}) =>
      _syncClient.disconnect(keepAsManual: keepAsManual);
}

final etoroSyncClientProvider = Provider<EtoroSyncClient>(
  (ref) => EtoroSyncClient(),
);

final etoroAuthLauncherProvider = Provider<EtoroAuthLauncher>(
  (ref) => const SystemBrowserEtoroAuthLauncher(),
);

final etoroConnectionRepositoryProvider = Provider<EtoroConnectionRepository>(
  (ref) => EtoroConnectionRepository(
    client: () {
      try {
        return ref.read(supabaseClientProvider);
      } catch (_) {
        return null;
      }
    },
    syncClient: ref.watch(etoroSyncClientProvider),
  ),
);
