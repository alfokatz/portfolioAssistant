import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/config/supabase/supabase_client_provider.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_claim.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/porty_edge_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Por qué falló hablar con el servidor del brief.
sealed class DailyBriefFailure implements Exception {
  const DailyBriefFailure();
}

/// El interruptor (o la pieza) está apagado: 403 `disabled`.
class DailyBriefDisabled extends DailyBriefFailure {
  const DailyBriefDisabled();
}

/// Sin red, sin sesión o sin configurar.
class DailyBriefNetworkFailure extends DailyBriefFailure {
  const DailyBriefNetworkFailure();
}

/// El servidor respondió con un error (5xx, 429, 4xx inesperado).
class DailyBriefServerFailure extends DailyBriefFailure {
  const DailyBriefServerFailure(this.statusCode, [this.type]);
  final int statusCode;
  final String? type;
}

/// `complete_daily_brief` dijo `not_claimed`: otro dispositivo se quedó con
/// el claim (o venció).
class DailyBriefNotClaimed extends DailyBriefFailure {
  const DailyBriefNotClaimed();
}

/// Dónde se reserva, se guarda y se lee el brief de cada día.
abstract class DailyBriefStore {
  /// `daily_brief_status()`. Nunca lanza: sin respuesta, apagado.
  Future<DailyBriefStatus> status();

  /// `claim_daily_brief(p_day)`. Nunca lanza.
  Future<DailyBriefClaim> claim(String day);

  /// `complete_daily_brief`. `false` si el servidor no lo aceptó (payload
  /// inválido o muy grande). Lanza [DailyBriefNotClaimed] o falla de red.
  Future<bool> complete(String day, Map<String, Object?> payload);

  /// `fail_daily_brief`: libera el claim para reintentar. Nunca lanza.
  Future<void> fail(String day);

  /// `daily-brief?scope=…` (edge function, §3.5). Devuelve el body.
  /// Lanza [DailyBriefFailure].
  Future<Map<String, Object?>> bundle(
    String scope, {
    required String day,
    required String lang,
    String? topic,
  });
}

/// RPCs `daily_brief_status`, `claim_daily_brief`, `complete_daily_brief` y
/// `fail_daily_brief`, y la edge function `daily-brief` por [PortyEdgeClient]
/// (Dio; nunca `functions.invoke`).
class DailyBriefRepository implements DailyBriefStore {
  DailyBriefRepository({
    required SupabaseClient client,
    required SupabaseAuthService authService,
    PortyEdgeClient? edge,
  }) : _client = client,
       _authService = authService,
       _edge = edge ?? PortyEdgeClient();

  final SupabaseClient _client;
  final SupabaseAuthService _authService;
  final PortyEdgeClient _edge;

  @override
  Future<DailyBriefStatus> status() async {
    try {
      _authService.requireUserId();
      return DailyBriefStatus.parse(await _client.rpc('daily_brief_status'));
    } catch (_) {
      return DailyBriefStatus.unreachable;
    }
  }

  @override
  Future<DailyBriefClaim> claim(String day) async {
    try {
      _authService.requireUserId();
      final response = await _client.rpc(
        'claim_daily_brief',
        params: {'p_day': day},
      );
      return DailyBriefClaim.parse(response);
    } catch (_) {
      return const BriefClaimUnavailable();
    }
  }

  @override
  Future<bool> complete(String day, Map<String, Object?> payload) async {
    final Object? response;
    try {
      _authService.requireUserId();
      response = await _client.rpc(
        'complete_daily_brief',
        params: {'p_day': day, 'p_payload': payload},
      );
    } catch (_) {
      throw const DailyBriefNetworkFailure();
    }
    if (response is Map) {
      if (response['ok'] == true) return true;
      if (response['reason'] == 'not_claimed') {
        throw const DailyBriefNotClaimed();
      }
    }
    return false;
  }

  @override
  Future<void> fail(String day) async {
    try {
      _authService.requireUserId();
      await _client.rpc('fail_daily_brief', params: {'p_day': day});
    } catch (_) {
      // Si no llega, el claim vence solo a los 2 minutos.
    }
  }

  @override
  Future<Map<String, Object?>> bundle(
    String scope, {
    required String day,
    required String lang,
    String? topic,
  }) async {
    final response = await _edge.get(
      'daily-brief',
      query: {
        'scope': scope,
        'lang': lang,
        'day': day,
        if (topic != null) 'topic': topic,
      },
    );
    if (response.ok) return response.body!;
    if (response.statusCode == 0) throw const DailyBriefNetworkFailure();
    if (response.statusCode == 403 && response.errorType == 'disabled') {
      throw const DailyBriefDisabled();
    }
    throw DailyBriefServerFailure(response.statusCode, response.errorType);
  }
}

final dailyBriefRepositoryProvider = Provider<DailyBriefStore>(
  (ref) => DailyBriefRepository(
    client: ref.watch(supabaseClientProvider),
    authService: ref.watch(supabaseAuthServiceProvider),
  ),
);
