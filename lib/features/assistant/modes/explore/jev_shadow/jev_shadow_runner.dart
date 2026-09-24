import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/jev_shadow/jev_explore_criteria.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/jev_shadow/jev_shadow_config.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/jev_shadow/jev_shadow_repository.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/jev_shadow/typesafe_client.dart';

/// Dispara, en paralelo y sin bloquear, una comparación de Jev/TypeSafe
/// contra la elección real de gpt-4.1-mini para un turno de Explore ya
/// resuelto — experimento de shadow-mode antes de decidir si vale la pena
/// partir el pipeline de Explore en dos etapas (routing separado de
/// generación).
///
/// Contrato no negociable: ninguna falla acá (red, parseo, TypeSafe caído,
/// lo que sea) puede afectar la respuesta ya mostrada al usuario. Por eso
/// esto se llama después de que el turno real ya se resolvió con éxito
/// (ver `AssistantProvider.sendMessage`), y todo el cuerpo corre
/// fire-and-forget con su propio try/catch de último recurso.
abstract final class JevShadowRunner {
  static const _dataWidgets = {
    'QaTickerSnapshot',
    'QaTickerMove',
    'QaMetricStrip',
    'QaEarningsCalendar',
    'QaNewsSummary',
  };

  /// A partir de la lista "id:Tipo" que expone
  /// `OpenAIGenUiService.lastComponentChoices`, determina cuál fue el
  /// widget de datos PRINCIPAL del turno. `QaTipBanner` nunca cuenta como
  /// principal — según `explorePromptRules` siempre acompaña a otro
  /// widget, nunca es la única respuesta. Si no hay ningún widget de
  /// datos, el turno fue puramente `QaAnswerText`.
  static String primaryWidgetFrom(List<String> componentChoices) {
    for (final entry in componentChoices) {
      final type = entry.contains(':') ? entry.split(':').last : entry;
      if (_dataWidgets.contains(type)) return type;
    }
    return 'QaAnswerText';
  }

  static void runForExploreTurn({
    required String userMessage,
    required Map<String, dynamic> snapshot,
    required List<String> componentChoices,
    required Duration currentPipelineLatency,
    required TypeSafeClient client,
    required JevShadowRepository repository,
    String? userId,
  }) {
    if (!JevShadowConfig.isEnabled) return;
    unawaited(
      _run(
        userMessage: userMessage,
        snapshot: snapshot,
        currentWidget: primaryWidgetFrom(componentChoices),
        currentPipelineLatency: currentPipelineLatency,
        client: client,
        repository: repository,
        userId: userId,
      ),
    );
  }

  static Future<void> _run({
    required String userMessage,
    required Map<String, dynamic> snapshot,
    required String currentWidget,
    required Duration currentPipelineLatency,
    required TypeSafeClient client,
    required JevShadowRepository repository,
    String? userId,
  }) async {
    try {
      // El snapshot de `ExploreContextBuilder` no incluye el mensaje
      // textual del usuario (solo datos de mercado ya resueltos) — sin
      // agregarlo, Jev no tiene forma de saber qué ticker/período/
      // comparación pidió el usuario. Ver `jev_explore_criteria.dart`.
      final state = {...snapshot, 'user_message': userMessage};

      final result = await client.chooseWidget(
        state: state,
        criteria: jevExploreWidgetCriteria,
        instructions: jevExploreWidgetQuestionInstructions,
      );

      await result.fold(
        (error) => repository.logFailure(
          userMessage: userMessage,
          snapshot: state,
          currentWidget: currentWidget,
          currentPipelineLatency: currentPipelineLatency,
          errorCode: error.code,
          userId: userId,
        ),
        (answer) => repository.logComparison(
          userMessage: userMessage,
          snapshot: state,
          currentWidget: currentWidget,
          jevWidget: answer.choice,
          jevConfidence: answer.confidence,
          jevProbabilities: answer.probabilities,
          jevLatency: answer.latency,
          currentPipelineLatency: currentPipelineLatency,
          userId: userId,
        ),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[JevShadow] falla inesperada, ignorada: $e');
      }
    }
  }
}
