import 'package:dart_openai/dart_openai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_error_message.dart';
import 'package:portfolio_assistant/features/genui_core/utils/openai_request_throttle.dart';
import 'package:portfolio_assistant/features/portfolio_qa/prompts/portfolio_qa_system_prompt.dart';

/// Chat OpenAI con contexto de portfolio (sin GenUI).
class PortfolioQaService {
  PortfolioQaService({String? apiKey, String? model})
      : apiKey = apiKey ?? dotenv.env['OPENAI_API_KEY'] ?? '',
        model = model ?? dotenv.env['OPENAI_MODEL'] ?? OpenAIGenUiService.defaultModel {
    OpenAI.apiKey = this.apiKey;
    _resetHistory();
  }

  static const maxTurnPairs = 5;

  final String apiKey;
  final String model;
  final List<OpenAIChatCompletionChoiceMessageModel> _history = [];
  bool isDisposed = false;

  void _resetHistory() {
    _history
      ..clear()
      ..add(
        OpenAIChatCompletionChoiceMessageModel(
          role: OpenAIChatMessageRole.system,
          content: [
            OpenAIChatCompletionChoiceMessageContentItemModel.text(
              portfolioQaSystemPrompt,
            ),
          ],
        ),
      );
  }

  void resetConversation() => _resetHistory();

  Future<String> sendMessage({
    required String userQuestion,
    required String portfolioSnapshotJson,
    void Function(String chunk)? onChunk,
  }) async {
    if (userQuestion.trim().isEmpty) return '';
    if (apiKey.isEmpty) {
      throw StateError('OPENAI_API_KEY no configurada');
    }

    final body = portfolioQaUserMessageBody(
      portfolioSnapshotJson: portfolioSnapshotJson,
      question: userQuestion.trim(),
    );

    _history.add(
      OpenAIChatCompletionChoiceMessageModel(
        role: OpenAIChatMessageRole.user,
        content: [
          OpenAIChatCompletionChoiceMessageContentItemModel.text(body),
        ],
      ),
    );
    _trimHistory();

    for (var attempt = 0; attempt <= OpenAIGenUiService.maxRateLimitRetries; attempt++) {
      try {
        return await _streamReply(onChunk: onChunk);
      } on RequestFailedException catch (e) {
        final canRetry =
            isOpenAiRateLimitError(e) && attempt < OpenAIGenUiService.maxRateLimitRetries;
        if (!canRetry || isDisposed) rethrow;
        final seconds = openAiSuggestedRetrySeconds(e.message) ?? 5;
        await Future<void>.delayed(
          Duration(milliseconds: ((seconds + 1) * 1000).clamp(2000, 120000)),
        );
      }
    }

    throw StateError('No se pudo completar la solicitud');
  }

  Future<String> _streamReply({void Function(String chunk)? onChunk}) async {
    await OpenAiRequestThrottle.waitIfNeeded();
    OpenAiRequestThrottle.markRequestStarted();

    final buffer = StringBuffer();
    final stream = OpenAI.instance.chat.createStream(
      model: model,
      messages: _history,
      temperature: 0.5,
    );

    await for (final chunk in stream) {
      if (isDisposed) break;
      final delta = chunk.choices.firstOrNull?.delta.content;
      if (delta == null || delta.isEmpty) continue;
      final chunkText = delta.firstOrNull?.text;
      if (chunkText == null || chunkText.isEmpty) continue;
      buffer.write(chunkText);
      onChunk?.call(chunkText);
    }

    if (isDisposed) return buffer.toString();

    final reply = buffer.toString().trim();
    if (reply.isNotEmpty) {
      _history.add(
        OpenAIChatCompletionChoiceMessageModel(
          role: OpenAIChatMessageRole.assistant,
          content: [
            OpenAIChatCompletionChoiceMessageContentItemModel.text(reply),
          ],
        ),
      );
      _trimHistory();
    }

    return reply;
  }

  void _trimHistory() {
    if (_history.length <= 1) return;
    const maxMessages = 1 + maxTurnPairs * 2;
    if (_history.length <= maxMessages) return;
    final system = _history.first;
    final tail = _history.sublist(_history.length - (maxMessages - 1));
    _history
      ..clear()
      ..add(system)
      ..addAll(tail);
  }

  void dispose() {
    isDisposed = true;
    _history.clear();
  }
}
