import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_client_provider.dart';
import 'package:portfolio_assistant/features/snaptrade/domain/snaptrade_connection.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/porty_edge_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Esquema con el que el Connection Portal de SnapTrade devuelve al usuario
/// a la app (`SNAPTRADE_APP_REDIRECT`).
const snaptradeCallbackScheme = 'porty-snaptrade';

/// Error tipado de `snaptrade-sync` (`error.type`): `snaptrade_plan_required`,
/// `snaptrade_connection_limit`, `snaptrade_reconnect_required`,
/// `snaptrade_refresh_limit`, `snaptrade_not_configured`,
/// `snaptrade_unavailable`… `network` sin respuesta.
class SnaptradeException implements Exception {
  const SnaptradeException(this.type);

  final String type;

  @override
  String toString() => 'SnaptradeException($type)';
}

/// Abre el Connection Portal de SnapTrade en el navegador del sistema
/// (ASWebAuthenticationSession en iOS, Custom Tabs en Android). `true` si
/// volvió por el deep link; `false` si el usuario lo cerró.
abstract class SnaptradePortalLauncher {
  Future<bool> open(Uri url);
}

class SystemBrowserSnaptradePortalLauncher implements SnaptradePortalLauncher {
  const SystemBrowserSnaptradePortalLauncher();

  @override
  Future<bool> open(Uri url) async {
    try {
      await FlutterWebAuth2.authenticate(
        url: url.toString(),
        callbackUrlScheme: snaptradeCallbackScheme,
        // Sin cookies compartidas con Safari: la sesión del bróker no queda
        // guardada en el navegador del usuario.
        options: const FlutterWebAuth2Options(preferEphemeral: true),
      );
      return true;
    } on PlatformException catch (e) {
      if (e.code == 'CANCELED') return false;
      rethrow;
    }
  }
}

/// La conexión (tabla `snaptrade_connections`, solo lectura para la app) y
/// la edge function `snaptrade-sync`, que es la única que ve el secreto del
/// usuario de SnapTrade.
class SnaptradeRepository {
  SnaptradeRepository({
    required SupabaseClient? Function() client,
    PortyEdgeClient? edge,
  }) : _client = client,
       _edge = edge ?? PortyEdgeClient(dio: _createDio());

  final SupabaseClient? Function() _client;
  final PortyEdgeClient _edge;

  static Dio _createDio() => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      // Las posiciones de hasta 20 cuentas.
      receiveTimeout: const Duration(seconds: 45),
      validateStatus: (status) => status != null && status < 600,
    ),
  );

  Future<SnaptradeConnection> load() async {
    final client = _client();
    if (client == null || client.auth.currentUser == null) {
      return const SnaptradeConnection();
    }
    try {
      final row =
          await client
              .from('snaptrade_connections')
              .select(
                'status, brokerages, last_sync_at, last_result, last_error_type',
              )
              .maybeSingle();
      return SnaptradeConnection.fromRow(row);
    } on PostgrestException {
      throw const SnaptradeException('unavailable');
    }
  }

  /// La URL del Connection Portal (vence a los 5 minutos). [reconnect]: el
  /// id de un bróker caído.
  Future<Uri> portalUrl({required bool darkMode, String? reconnect}) async {
    final data = await _post('snaptrade-sync/connect', {
      'darkMode': darkMode,
      if (reconnect != null) 'reconnect': reconnect,
    });
    final url = Uri.tryParse('${data['portalUrl'] ?? ''}');
    if (url == null || !url.hasScheme) {
      throw const SnaptradeException('snaptrade_unavailable');
    }
    return url;
  }

  /// `throttled`: hubo una hace menos de 5 minutos y devolvió esa. [force]
  /// al volver del portal (lo recién conectado tiene que entrar ya).
  Future<({SnaptradeSyncResult? result, bool throttled})> sync({
    bool force = false,
  }) async {
    final data = await _post('snaptrade-sync/sync', {if (force) 'force': true});
    return (
      result: SnaptradeSyncResult.fromJson(data['result']),
      throttled: data['throttled'] == true,
    );
  }

  /// "Actualizar ahora" (Gold): SnapTrade vuelve a leer los brókers en
  /// segundo plano. Devuelve cuántos.
  Future<int> refresh() async {
    final data = await _post('snaptrade-sync/refresh', const {});
    return (data['queued'] as num?)?.toInt() ?? 0;
  }

  /// Quita un bróker y vuelve a sincronizar.
  Future<void> remove(String brokerageId) async {
    await _post('snaptrade-sync/remove', {'authorizationId': brokerageId});
  }

  Future<void> disconnect({required bool keepAsManual}) async {
    await _post('snaptrade-sync/disconnect', {'keepAsManual': keepAsManual});
  }

  Future<Map<String, Object?>> _post(
    String path,
    Map<String, Object?> body,
  ) async {
    final response = await _edge.post(path, body);
    if (response.statusCode == 0) throw const SnaptradeException('network');
    if (!response.ok) {
      throw SnaptradeException(response.errorType ?? 'snaptrade_unavailable');
    }
    return response.body!;
  }
}

final snaptradeRepositoryProvider = Provider<SnaptradeRepository>(
  (ref) => SnaptradeRepository(
    client: () {
      try {
        return ref.read(supabaseClientProvider);
      } catch (_) {
        return null;
      }
    },
  ),
);

final snaptradePortalLauncherProvider = Provider<SnaptradePortalLauncher>(
  (ref) => const SystemBrowserSnaptradePortalLauncher(),
);
