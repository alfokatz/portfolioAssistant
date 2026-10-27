import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_client_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Cómo terminó un turno para el usuario (columna `ai_turn_usage.outcome`).
enum TurnOutcomeKind {
  /// Se mostró la respuesta del modelo.
  answered('answered'),

  /// Se mostró el texto de respaldo ("No pude procesar tu consulta").
  fallback('fallback'),

  /// Todo lo que pidió el modelo estaba fuera del plan: se abrió el paywall.
  paywall('paywall'),

  /// Sin conexión: el turno se sacó y se mostró el banner de error.
  connectionError('connection_error');

  const TurnOutcomeKind(this.value);

  final String value;
}

/// Un resultado de turno para `ai_report_turn_outcome`.
class TurnOutcomeReport {
  const TurnOutcomeReport({
    required this.turnId,
    required this.outcome,
    this.reason,
    required this.latency,
    required this.answerRejected,
    required this.finalRetried,
  });

  final String turnId;
  final TurnOutcomeKind outcome;

  /// Código corto (`timeout`, `unreadable`…), nunca el texto de una
  /// excepción: puede traer datos de la respuesta.
  final String? reason;
  final Duration latency;
  final bool answerRejected;
  final bool finalRetried;

  Map<String, Object?> toParams() => {
    'p_turn_id': turnId,
    'p_outcome': outcome.value,
    'p_reason': reason,
    'p_latency_ms': latency.inMilliseconds.clamp(0, 600000),
    'p_answer_rejected': answerRejected,
    'p_final_retried': finalRetried,
  };
}

/// RPC `ai_report_turn_outcome` (migración
/// 20261027000000_ai_turn_outcome.sql): guarda cómo terminó el turno en su
/// fila de `ai_turn_usage`. Es diagnóstico: nunca lanza ni demora el chat.
class TurnOutcomeReporter {
  TurnOutcomeReporter({required SupabaseClient client}) : _client = client;

  final SupabaseClient _client;

  Future<void> report(TurnOutcomeReport report) async {
    try {
      await _client.rpc('ai_report_turn_outcome', params: report.toParams());
    } catch (_) {
      // Sin sesión, sin red o migración sin aplicar: se pierde el dato.
    }
  }
}

final turnOutcomeReporterProvider = Provider<TurnOutcomeReporter>(
  (ref) => TurnOutcomeReporter(client: ref.watch(supabaseClientProvider)),
);
