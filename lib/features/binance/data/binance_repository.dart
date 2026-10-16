import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_client_provider.dart';
import 'package:portfolio_assistant/features/binance/domain/binance_connection.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/porty_edge_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Error tipado de `binance-sync` (`error.type`): `binance_write_permissions`,
/// `binance_no_read`, `binance_invalid_key`, `binance_plan_required`,
/// `binance_region_blocked`, `binance_rate_limited`,
/// `binance_reconnect_required`, `binance_unavailable`… `network` sin
/// respuesta.
class BinanceException implements Exception {
  const BinanceException(this.type);

  final String type;

  @override
  String toString() => 'BinanceException($type)';
}

/// La conexión (tabla `binance_connections`, solo lectura para la app) y la
/// edge function `binance-sync`. La clave de API va una sola vez al
/// servidor, que la guarda cifrada; nunca vuelve.
class BinanceRepository {
  BinanceRepository({
    required SupabaseClient? Function() client,
    PortyEdgeClient? edge,
  }) : _client = client,
       _edge = edge ?? PortyEdgeClient(dio: _createDio());

  final SupabaseClient? Function() _client;
  final PortyEdgeClient _edge;

  static Dio _createDio() => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      // Saldos, precios y operaciones de hasta 15 activos.
      receiveTimeout: const Duration(seconds: 45),
      validateStatus: (status) => status != null && status < 600,
    ),
  );

  Future<BinanceConnection> load() async {
    final client = _client();
    if (client == null || client.auth.currentUser == null) {
      return const BinanceConnection();
    }
    try {
      final row =
          await client
              .from('binance_connections')
              .select(
                'status, api_key_hint, last_sync_at, last_result, last_error_type',
              )
              .maybeSingle();
      return BinanceConnection.fromRow(row);
    } on PostgrestException {
      throw const BinanceException('unavailable');
    }
  }

  /// Verifica la clave (solo lectura), la guarda y hace la primera
  /// importación.
  Future<BinanceSyncResult?> connect({
    required String apiKey,
    required String apiSecret,
  }) async {
    final data = await _post('binance-sync/connect', {
      'api_key': apiKey.trim(),
      'api_secret': apiSecret.trim(),
    });
    return BinanceSyncResult.fromJson(data['result']);
  }

  /// `throttled`: hubo una hace menos de 5 minutos y devolvió esa.
  Future<({BinanceSyncResult? result, bool throttled})> sync() async {
    final data = await _post('binance-sync/sync', const {});
    return (
      result: BinanceSyncResult.fromJson(data['result']),
      throttled: data['throttled'] == true,
    );
  }

  Future<void> disconnect({required bool keepAsManual}) async {
    await _post('binance-sync/disconnect', {'keepAsManual': keepAsManual});
  }

  Future<Map<String, Object?>> _post(
    String path,
    Map<String, Object?> body,
  ) async {
    final response = await _edge.post(path, body);
    if (response.statusCode == 0) throw const BinanceException('network');
    if (!response.ok) {
      throw BinanceException(response.errorType ?? 'binance_unavailable');
    }
    return response.body!;
  }
}

final binanceRepositoryProvider = Provider<BinanceRepository>(
  (ref) => BinanceRepository(
    client: () {
      try {
        return ref.read(supabaseClientProvider);
      } catch (_) {
        return null;
      }
    },
  ),
);
