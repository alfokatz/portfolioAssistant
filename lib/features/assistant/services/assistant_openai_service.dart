import 'package:genui/genui.dart';
import 'package:portfolio_assistant/features/assistant/catalog/assistant_catalog.dart';
import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';
import 'package:portfolio_assistant/features/assistant/prompts/portfolio_qa_system_prompt.dart';

/// Servicio GenUI del asistente unificado con surface dinámico por turno.
class AssistantOpenAiService extends OpenAIGenUiService {
  AssistantOpenAiService({
    super.apiKey,
    super.model,
    required super.systemPrompt,
    required super.catalog,
  });

  factory AssistantOpenAiService.forMode({
    required AssistantMode mode,
    String? apiKey,
    String? model,
  }) {
    final catalog = AssistantCatalog.buildFor(mode);
    final prompt =
        PromptBuilder.custom(
          catalog: catalog,
          allowedOperations: SurfaceOperations.createAndUpdate(
            dataModel: false,
          ),
          systemPromptFragments: catalog.systemPromptFragments,
          technicalPossibilities: const TechnicalPossibilities(
            codeExecution: false,
            toolCall: false,
            functionCall: false,
          ),
        ).systemPromptJoined();

    return AssistantOpenAiService(
      apiKey: apiKey,
      model: model,
      systemPrompt: prompt,
      catalog: catalog,
    );
  }

  static const maxTurnPairs = 5;

  Future<void> sendWithSnapshot({
    required String userQuestion,
    required String portfolioSnapshotJson,
    required String surfaceId,
  }) async {
    final body = portfolioQaUserMessageBody(
      portfolioSnapshotJson: portfolioSnapshotJson,
      question: userQuestion,
      surfaceId: surfaceId,
    );

    await handleSend(ChatMessage.user(body), surfaceId: surfaceId);
    _trimHistory();
  }

  void _trimHistory() {
    if (history.length <= 1) return;
    const maxMessages = 1 + maxTurnPairs * 2;
    if (history.length <= maxMessages) return;
    final system = history.first;
    final tail = history.sublist(history.length - (maxMessages - 1));
    history
      ..clear()
      ..add(system)
      ..addAll(tail);
  }
}
