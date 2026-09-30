import 'dart:convert';

import 'package:genui/genui.dart';
import 'package:http/http.dart' as http;
import 'package:portfolio_assistant/features/assistant/catalog/assistant_catalog.dart';
import 'package:portfolio_assistant/features/assistant/tools/portfolio_tools.dart';
import 'package:portfolio_assistant/features/assistant/utils/assistant_answer_review.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';

/// Servicio GenUI de Porty: un catálogo, un set de reglas, una conversación.
class AssistantOpenAiService extends OpenAIGenUiService {
  AssistantOpenAiService._({
    super.apiKey,
    super.model,
    super.httpClient,
    required super.systemPrompt,
    required super.catalog,
  }) : super(
         postProcess: AssistantAnswerReview.postProcess,
         answerCheck: AssistantAnswerReview.check,
       );

  factory AssistantOpenAiService({
    String? apiKey,
    String? model,
    http.Client? httpClient,
  }) {
    final catalog = AssistantCatalog.build();
    return AssistantOpenAiService._(
      apiKey: apiKey,
      model: model,
      httpClient: httpClient,
      systemPrompt: systemPromptFor(catalog),
      catalog: catalog,
    );
  }

  /// `PromptBuilder` ya agrega `catalog.systemPromptFragments` por su
  /// cuenta; pasarlos también como argumento los duplicaba (~8,9K tokens
  /// repetidos en cada request).
  static String systemPromptFor(Catalog catalog) =>
      PromptBuilder.custom(
        catalog: catalog,
        allowedOperations: SurfaceOperations.createAndUpdate(dataModel: false),
        technicalPossibilities: const TechnicalPossibilities(
          codeExecution: false,
          toolCall: false,
          functionCall: false,
        ),
      ).systemPromptJoined();

  /// Un turno de Porty: [question] + resumen de cartera fresco + tools.
  Future<TurnOutcome> ask({
    required String question,
    required Map<String, Object?> portfolioBrief,
    required String surfaceId,
    required List<DataTool> tools,
    TurnAbortCheck? abortCheck,
    TurnActivityCallback? onActivity,
    BeforeToolRound? beforeRound,
  }) {
    return runTurn(
      userText: question,
      surfaceId: surfaceId,
      tools: tools,
      abortCheck: abortCheck,
      onActivity: onActivity,
      beforeRound: beforeRound,
      pinnedContext:
          '${PortfolioBrief.label} — la cartera ACTUAL del usuario (dato de '
          'referencia, se actualiza en cada turno; no es parte de ninguna '
          'pregunta):\n${jsonEncode(portfolioBrief)}',
      context:
          'SURFACE_ID (usar exactamente en createSurface y '
          'updateComponents): $surfaceId\n\n'
          'PREGUNTA DEL USUARIO:',
    );
  }
}
