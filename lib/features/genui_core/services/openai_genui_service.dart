import 'package:dart_openai/dart_openai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:genui/genui.dart';
import 'package:portfolio_assistant/features/genui_core/genui_surface_ids.dart';
import 'package:portfolio_assistant/features/genui_core/utils/a2ui_controller_dispatch.dart';
import 'package:portfolio_assistant/features/genui_core/utils/a2ui_response_normalizer.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_error_message.dart';
import 'package:portfolio_assistant/features/genui_core/utils/llm_json_sanitizer.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_surface_readiness.dart';
import 'package:portfolio_assistant/features/genui_core/utils/openai_request_throttle.dart';

export 'package:portfolio_assistant/features/genui_core/genui_surface_ids.dart';
export 'package:portfolio_assistant/features/genui_core/models/gen_ui_flow_type.dart';

/// Servicio GenUI con streaming OpenAI y transporte A2UI.
///
/// Por defecto usa [defaultModel] (`gpt-4.1-mini`) por buen balance
/// precio/calidad en JSON A2UI.
/// Override opcional: `OPENAI_MODEL` en `.env`.
class OpenAIGenUiService {
  static const defaultModel = 'gpt-4.1-mini';
  static const maxRateLimitRetries = 3;

  OpenAIGenUiService({
    String? apiKey,
    String? model,
    required this.systemPrompt,
    required Catalog catalog,
    this.a2uiSurfaceId,
    this.a2uiCatalogId,
  })  : apiKey = apiKey ?? dotenv.env['OPENAI_API_KEY'] ?? '',
        model = model ?? dotenv.env['OPENAI_MODEL'] ?? defaultModel {
    OpenAI.apiKey = this.apiKey;
    controller = SurfaceController(catalogs: [catalog]);
    transport = A2uiTransportAdapter(onSend: handleSend);
    conversation = Conversation(
      controller: controller,
      transport: transport,
    );
    history.add(
      OpenAIChatCompletionChoiceMessageModel(
        role: OpenAIChatMessageRole.system,
        content: [
          OpenAIChatCompletionChoiceMessageContentItemModel.text(systemPrompt),
        ],
      ),
    );
  }

  final String apiKey;
  final String model;
  final String systemPrompt;
  final String? a2uiSurfaceId;
  final String? a2uiCatalogId;
  late final SurfaceController controller;
  late final A2uiTransportAdapter transport;
  late final Conversation conversation;
  final List<OpenAIChatCompletionChoiceMessageModel> history = [];
  String? _runtimeSurfaceId;
  bool isDisposed = false;

  String? get _effectiveSurfaceId => _runtimeSurfaceId ?? a2uiSurfaceId;

  @Deprecated('Use GenUiSurfaceIds.portfolioAnalysis')
  static const analysisSurfaceId = GenUiSurfaceIds.portfolioAnalysis;

  static const investmentSurfaceId = GenUiSurfaceIds.investmentDecision;

  Future<void> handleSend(
    ChatMessage message, {
    String? surfaceId,
  }) async {
    _runtimeSurfaceId = surfaceId;
    try {
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

      for (var attempt = 0; attempt <= maxRateLimitRetries; attempt++) {
        try {
          await streamCompletion();
          return;
        } on RequestFailedException catch (e) {
          final canRetry =
              isOpenAiRateLimitError(e) && attempt < maxRateLimitRetries;
          if (!canRetry || isDisposed) rethrow;
          final seconds = openAiSuggestedRetrySeconds(e.message) ?? 5;
          await Future<void>.delayed(
            Duration(milliseconds: ((seconds + 1) * 1000).clamp(2000, 120000)),
          );
        }
      }
    } finally {
      _runtimeSurfaceId = null;
    }
  }

  Future<void> streamCompletion() async {
    await OpenAiRequestThrottle.waitIfNeeded();
    OpenAiRequestThrottle.markRequestStarted();

    final modelBuffer = StringBuffer();
    final stream = OpenAI.instance.chat.createStream(
      model: model,
      messages: history,
      temperature: 0.35,
    );

    await for (final chunk in stream) {
      if (isDisposed) break;
      final delta = chunk.choices.firstOrNull?.delta.content;
      if (delta == null || delta.isEmpty) continue;
      final chunkText = delta.firstOrNull?.text;
      if (chunkText == null || chunkText.isEmpty) continue;
      modelBuffer.write(chunkText);
    }

    if (isDisposed) return;

    final raw = modelBuffer.toString();
    final surfaceId = _effectiveSurfaceId;
    final catalogId = a2uiCatalogId ?? A2uiResponseNormalizer.defaultCatalogId;

    var cleaned = surfaceId != null
        ? LlmJsonSanitizer.sanitizeOrFallback(
            raw,
            surfaceId: surfaceId,
            catalogId: catalogId,
          )
        : (raw.isEmpty ? '' : LlmJsonSanitizer.sanitize(raw));

    if (cleaned.isEmpty && surfaceId != null) {
      cleaned = A2uiResponseNormalizer.fallbackResponse(
        surfaceId,
        LlmJsonSanitizer.defaultFallbackMessage,
        catalogId: catalogId,
      );
    }

    if (cleaned.isEmpty) return;

    if (surfaceId != null) {
      final normalized = A2uiResponseNormalizer.normalize(
        cleaned,
        surfaceId: surfaceId,
        catalogId: catalogId,
      );
      cleaned = normalized.trim().isEmpty
          ? A2uiResponseNormalizer.fallbackResponse(
              surfaceId,
              LlmJsonSanitizer.defaultFallbackMessage,
              catalogId: catalogId,
            )
          : normalized;
    }

    A2uiControllerDispatch.dispatchNormalized(controller, cleaned);

    if (surfaceId != null &&
        !GenUiSurfaceReadiness.hasRootComponent(
          controller.registry.getSurface(surfaceId),
        )) {
      throw StateError(
        'La IA no generó una interfaz válida. Intentá reformular la consulta.',
      );
    }

    history.add(
      OpenAIChatCompletionChoiceMessageModel(
        role: OpenAIChatMessageRole.assistant,
        content: [
          OpenAIChatCompletionChoiceMessageContentItemModel.text(raw),
        ],
      ),
    );
  }

  void dispose() {
    isDisposed = true;
    conversation.dispose();
    transport.dispose();
    controller.dispose();
  }
}
