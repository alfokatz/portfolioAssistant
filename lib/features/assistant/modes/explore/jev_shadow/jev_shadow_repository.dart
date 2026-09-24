import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_client_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Persistencia de las comparaciones de shadow-mode (Jev vs. pipeline
/// actual) para poder armar el reporte después de 1-2 semanas de uso — ver
/// `supabase/jev_shadow_logs.sql` para el schema (no aplicado
/// automáticamente, hay que correrlo a mano en el proyecto de Supabase).
/// Nunca lanza: cualquier falla de escritura se loguea y se ignora, igual
/// que el resto del pipeline de shadow-mode — ver `JevShadowRunner`.
abstract class JevShadowRepository {
  Future<void> logComparison({
    required String userMessage,
    required Map<String, dynamic> snapshot,
    required String currentWidget,
    required String jevWidget,
    required double jevConfidence,
    required Map<String, double> jevProbabilities,
    required Duration jevLatency,
    required Duration currentPipelineLatency,
    String? userId,
  });

  Future<void> logFailure({
    required String userMessage,
    required Map<String, dynamic> snapshot,
    required String currentWidget,
    required Duration currentPipelineLatency,
    required String errorCode,
    String? userId,
  });
}

class JevShadowSupabaseRepository implements JevShadowRepository {
  JevShadowSupabaseRepository(this._client);

  final SupabaseClient _client;

  static const _table = 'jev_shadow_logs';

  @override
  Future<void> logComparison({
    required String userMessage,
    required Map<String, dynamic> snapshot,
    required String currentWidget,
    required String jevWidget,
    required double jevConfidence,
    required Map<String, double> jevProbabilities,
    required Duration jevLatency,
    required Duration currentPipelineLatency,
    String? userId,
  }) {
    final hypotheticalTotalMs =
        jevLatency.inMilliseconds + currentPipelineLatency.inMilliseconds;
    return _insert({
      'source': 'live_shadow',
      'user_id': userId,
      'user_message': userMessage,
      'snapshot': snapshot,
      'current_widget': currentWidget,
      'jev_widget': jevWidget,
      'jev_confidence': jevConfidence,
      'jev_probabilities': jevProbabilities,
      'match': currentWidget == jevWidget,
      'jev_latency_ms': jevLatency.inMilliseconds,
      'current_pipeline_latency_ms': currentPipelineLatency.inMilliseconds,
      'hypothetical_total_ms': hypotheticalTotalMs,
    });
  }

  @override
  Future<void> logFailure({
    required String userMessage,
    required Map<String, dynamic> snapshot,
    required String currentWidget,
    required Duration currentPipelineLatency,
    required String errorCode,
    String? userId,
  }) {
    return _insert({
      'source': 'live_shadow',
      'user_id': userId,
      'user_message': userMessage,
      'snapshot': snapshot,
      'current_widget': currentWidget,
      'current_pipeline_latency_ms': currentPipelineLatency.inMilliseconds,
      'jev_error': errorCode,
    });
  }

  Future<void> _insert(Map<String, dynamic> row) async {
    try {
      await _client.from(_table).insert(row);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[JevShadow] no se pudo escribir el log en Supabase: $e');
      }
    }
  }
}

final jevShadowRepositoryProvider = Provider<JevShadowRepository>(
  (ref) => JevShadowSupabaseRepository(ref.watch(supabaseClientProvider)),
);
