import 'package:dart_openai/dart_openai.dart';
import 'package:genui/genui.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';
import 'package:portfolio_assistant/features/portfolio_qa/prompts/portfolio_qa_system_prompt.dart';

/// Servicio GenUI del asistente Portfolio Q&A con surface dinámico por turno.
class PortfolioQaOpenAiService extends OpenAIGenUiService {
  PortfolioQaOpenAiService({
    super.apiKey,
    super.model,
    required super.systemPrompt,
    required super.catalog,
  });

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
