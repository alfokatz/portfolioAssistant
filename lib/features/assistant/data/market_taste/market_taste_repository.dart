import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/config/supabase/supabase_client_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Lo que el servidor dice de las consultas de mercado gratis del mes
/// (RPC `market_taste_status`).
class MarketTasteStatus {
  const MarketTasteStatus({
    required this.enabled,
    this.limit = 0,
    this.used = 0,
    this.remaining = 0,
  });

  /// Interruptor prendido para el usuario y plan con límite mayor a 0.
  final bool enabled;
  final int limit;
  final int used;
  final int remaining;

  static const off = MarketTasteStatus(enabled: false);

  /// `null` si [json] no es la respuesta esperada.
  static MarketTasteStatus? tryParse(Object? json) {
    if (json is! Map) return null;
    int number(String key) => json[key] is num ? (json[key] as num).toInt() : 0;
    return MarketTasteStatus(
      enabled: json['enabled'] == true,
      limit: number('limit'),
      used: number('used'),
      remaining: number('remaining'),
    );
  }
}

enum MarketTasteOutcome {
  /// Se gastó una consulta (o el turno ya la había gastado): hay datos.
  granted,

  /// Ya usó todas las del mes: el turno sigue sin datos de mercado ajeno.
  exhausted,

  /// Interruptor apagado, plan que ya incluye mercado, id inválido o error
  /// de red: todo queda como antes de esta función.
  unavailable,
}

class MarketTasteConsume {
  const MarketTasteConsume(this.outcome, [this.remaining]);

  final MarketTasteOutcome outcome;

  /// Consultas que quedan este mes, si [outcome] es `granted`.
  final int? remaining;

  static const exhausted = MarketTasteConsume(MarketTasteOutcome.exhausted, 0);
  static const unavailable = MarketTasteConsume(MarketTasteOutcome.unavailable);

  /// `null` si [json] no es la respuesta esperada.
  static MarketTasteConsume? tryParse(Object? json) {
    if (json is! Map) return null;
    if (json['ok'] == true) {
      final remaining = json['remaining'];
      return MarketTasteConsume(
        MarketTasteOutcome.granted,
        remaining is num ? remaining.toInt() : null,
      );
    }
    return json['reason'] == 'exhausted' ? exhausted : unavailable;
  }
}

/// Las consultas de mercado gratis del Free (spec 2026-11-03). El conteo
/// vive en el servidor: atómico e idempotente por turno.
abstract class MarketTasteRepository {
  /// `null` si no se pudo saber (sin sesión, sin red): se trata como apagado.
  Future<MarketTasteStatus?> status();

  /// Gasta la consulta del turno [turnId] para [tickers] (los ajenos).
  /// Nunca lanza: un error es [MarketTasteConsume.unavailable].
  Future<MarketTasteConsume> consume(String turnId, List<String> tickers);
}

/// RPCs `market_taste_status` / `consume_market_taste`.
class SupabaseMarketTasteRepository implements MarketTasteRepository {
  SupabaseMarketTasteRepository({
    required SupabaseClient client,
    required SupabaseAuthService authService,
  }) : _client = client,
       _authService = authService;

  final SupabaseClient _client;
  final SupabaseAuthService _authService;

  @override
  Future<MarketTasteStatus?> status() async {
    try {
      _authService.requireUserId();
      return MarketTasteStatus.tryParse(
        await _client.rpc('market_taste_status'),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<MarketTasteConsume> consume(
    String turnId,
    List<String> tickers,
  ) async {
    try {
      _authService.requireUserId();
      final response = await _client.rpc(
        'consume_market_taste',
        params: {'p_turn_id': turnId, 'p_tickers': tickers},
      );
      return MarketTasteConsume.tryParse(response) ??
          MarketTasteConsume.unavailable;
    } catch (_) {
      return MarketTasteConsume.unavailable;
    }
  }
}

final marketTasteRepositoryProvider = Provider<MarketTasteRepository>(
  (ref) => SupabaseMarketTasteRepository(
    client: ref.watch(supabaseClientProvider),
    authService: ref.watch(supabaseAuthServiceProvider),
  ),
);
