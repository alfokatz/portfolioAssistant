import 'package:dart_openai/dart_openai.dart';
import 'package:genui/genui.dart';
import 'package:portfolio_assistant/features/analysis/utils/news_query_detector.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_raw_chat_client.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_error_message.dart';

/// Servicio GenUI del flujo de análisis con búsqueda web en dos fases para noticias.
class AnalysisOpenAiService extends OpenAIGenUiService {
  AnalysisOpenAiService({
    super.apiKey,
    super.model,
    required super.systemPrompt,
    required super.catalog,
    required this.portfolioTickers,
    OpenAIRawChatClient? rawChatClient,
  }) : _rawChatClient =
           rawChatClient ?? OpenAIRawChatClient(apiKey: apiKey, model: model),
       super(a2uiSurfaceId: GenUiSurfaceIds.portfolioAnalysis);

  final List<String> Function() portfolioTickers;
  final OpenAIRawChatClient _rawChatClient;

  @override
  @override
  Future<void> handleSend(ChatMessage message, {String? surfaceId}) async {
    final userText = message.text.trim();
    if (userText.isEmpty && message.parts.isEmpty) return;

    if (userText.isNotEmpty) {
      history.add(
        OpenAIChatCompletionChoiceMessageModel(
          role: OpenAIChatMessageRole.user,
          content: [
            OpenAIChatCompletionChoiceMessageContentItemModel.text(userText),
          ],
        ),
      );
    }

    if (apiKey.isEmpty) {
      throw StateError('OPENAI_API_KEY no configurada');
    }

    for (
      var attempt = 0;
      attempt <= OpenAIGenUiService.maxRateLimitRetries;
      attempt++
    ) {
      try {
        if (userText.isNotEmpty && isNewsQuery(userText)) {
          await _runNewsTwoPhaseFlow(userText);
        } else {
          await streamCompletion();
        }
        return;
      } on RequestFailedException catch (e) {
        final canRetry =
            isOpenAiRateLimitError(e) &&
            attempt < OpenAIGenUiService.maxRateLimitRetries;
        if (!canRetry || isDisposed) rethrow;
        final seconds = openAiSuggestedRetrySeconds(e.message) ?? 5;
        await Future<void>.delayed(
          Duration(milliseconds: ((seconds + 1) * 1000).clamp(2000, 120000)),
        );
      } on StateError catch (e) {
        if (isOpenAiRateLimitError(e.toString()) &&
            attempt < OpenAIGenUiService.maxRateLimitRetries &&
            !isDisposed) {
          final seconds = openAiSuggestedRetrySeconds(e.toString()) ?? 5;
          await Future<void>.delayed(
            Duration(milliseconds: ((seconds + 1) * 1000).clamp(2000, 120000)),
          );
          continue;
        }
        rethrow;
      }
    }
  }

  Future<void> _runNewsTwoPhaseFlow(String userText) async {
    final tickers = portfolioTickers();
    final searchResults = await _rawChatClient.searchNews(
      userQuery: userText,
      tickers: tickers,
    );

    if (isDisposed) return;

    history.add(
      OpenAIChatCompletionChoiceMessageModel(
        role: OpenAIChatMessageRole.system,
        content: [
          OpenAIChatCompletionChoiceMessageContentItemModel.text(
            'WEB_SEARCH_RESULTS (use only this data, never fabricate):\n'
            '$searchResults\n\n'
            'Compose ONLY A2UI JSON using the catalog widgets. '
            'Follow NEWS RULES. Never fabricate headlines or sources.',
          ),
        ],
      ),
    );

    await streamCompletion();
  }
}
