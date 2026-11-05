import 'dart:convert';

import 'package:genui/genui.dart';
import 'package:http/http.dart' as http;
import 'package:portfolio_assistant/features/assistant/areas/area_specs.dart';
import 'package:portfolio_assistant/features/assistant/catalog/assistant_catalog.dart';
import 'package:portfolio_assistant/features/assistant/prompts/assistant_prompt_rules.dart';
import 'package:portfolio_assistant/features/assistant/tools/portfolio_tools.dart';
import 'package:portfolio_assistant/features/assistant/utils/assistant_answer_review.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/ai_proxy_client.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';

/// Servicio GenUI de Porty: un catálogo, un set de reglas, una conversación.
class AssistantOpenAiService extends OpenAIGenUiService {
  AssistantOpenAiService._({
    super.proxy,
    super.model,
    super.httpClient,
    required super.systemPrompt,
    required super.catalog,
    this.variant = PromptVariant.classic,
  }) : super(
         postProcess: AssistantAnswerReview.postProcess,
         answerCheck: AssistantAnswerReview.check,
       );

  factory AssistantOpenAiService({
    AiProxyConfig? proxy,
    String? model,
    http.Client? httpClient,
    PromptVariant variant = PromptVariant.classic,
  }) {
    return AssistantOpenAiService._(
      proxy: proxy,
      model: model,
      httpClient: httpClient,
      systemPrompt: systemPromptFor(AssistantCatalog.build(variant: variant)),
      // Para mostrar, siempre el catálogo completo: un widget diferido
      // llega descripto en su `area_spec`, y los que agrega la app
      // (QaBrokerLink) no van en el prompt.
      catalog: AssistantCatalog.build(forDisplay: true),
      variant: variant,
    );
  }

  /// Con qué prompt corre esta conversación (ver [PromptVariant]).
  final PromptVariant variant;

  /// Los esquemas de los widgets, como los describe el prompt clásico (de
  /// ahí salen los de `area_spec`).
  static final Map<String, Object?> _widgetSchemas = AreaSpecs.widgetSchemas(
    systemPromptFor(AssistantCatalog.build()),
  );

  /// Con el prompt lean: el `area_spec` de cada tool que difiere algo.
  ResultExtrasFor? get _resultExtras =>
      variant == PromptVariant.lean
          ? (record) => AreaSpecs.extraFor(
            record,
            rules: assistantPromptRules,
            schemas: _widgetSchemas,
          )
          : null;

  /// `PromptBuilder` ya agrega `catalog.systemPromptFragments` por su
  /// cuenta; pasarlos también como argumento los duplicaba (~8,9K tokens
  /// repetidos en cada request).
  static String systemPromptFor(Catalog catalog) => _compactSchemas(
    PromptBuilder.custom(
      catalog: catalog,
      allowedOperations: SurfaceOperations.createAndUpdate(dataModel: false),
      technicalPossibilities: const TechnicalPossibilities(
        codeExecution: false,
        toolCall: false,
        functionCall: false,
      ),
    ).systemPromptJoined(),
  );

  /// Mensajes A2UI que la app no permite (`createAndUpdate` sin data
  /// model): describirlos solo invita al modelo a usarlos.
  static const _unusedMessages = {
    'UpdateDataModelMessage',
    'DeleteSurfaceMessage',
  };

  /// Los esquemas JSON de la UI son casi la mitad del prompt, y genui los
  /// manda indentados: minificados dicen lo mismo con ~35 % menos tokens.
  /// También saca del esquema de mensajes los que no se permiten.
  static String _compactSchemas(String prompt) => prompt.replaceAllMapped(
    RegExp(
      r'(-----(COMMON_TYPES|CATALOG_SCHEMA|MESSAGE_SCHEMA)_START-----\n)'
      r'(.*?)'
      r'(\n-----\2_END-----)',
      dotAll: true,
    ),
    (m) {
      final schema = jsonDecode(m.group(3)!) as Map<String, Object?>;
      if (m.group(2) == 'MESSAGE_SCHEMA') {
        final defs = schema[r'$defs'] as Map<String, Object?>;
        _unusedMessages.forEach(defs.remove);
        (schema['oneOf'] as List).removeWhere(
          (ref) => _unusedMessages.any(
            (name) => (ref as Map)[r'$ref'] == '#/\$defs/$name',
          ),
        );
      }
      return '${m.group(1)}${jsonEncode(schema)}${m.group(4)}';
    },
  );

  /// Cómo usar `user_profile` sin volverse repetitivo: solo cuando cambia
  /// la respuesta, y la experiencia se nota en el tono, no se nombra.
  static const userProfileGuidance =
      'About user_profile (the investor profile the user filled in):\n'
      '- Use it ONLY when it changes the answer: concentration or '
      'diversification, drops or volatility, the risk of a stock, investment '
      'ideas and goals. For everything else (prices, news, earnings, '
      'portfolio data) ignore it.\n'
      '- Don\'t name it unless it is the concrete reason for what you say; '
      'never open the answer with it or repeat it from one message to the '
      'next.\n'
      '- experience silently sets the level: beginner = no jargon and one '
      'line of context; advanced = straight to the point. Never say "since '
      'you are a beginner".\n'
      '- drawdown_reaction "would sell" and the portfolio or a stock drops '
      'sharply → calm context, no alarmism.\n'
      '- stale true → the profile is over a year old; use it anyway, '
      'without mentioning it.\n'
      '- It never changes a number.\n';

  /// Cómo usar `user_memory` (lo que Porty anotó del usuario en charlas
  /// anteriores): para conectar la respuesta con su vida, no para recitarlo.
  static const userMemoryGuidance =
      'About user_memory (what you know about the user from earlier '
      'conversations):\n'
      '- Use it to make the answer THEIRS: if they ask how to save or invest '
      'and have a goal noted, connect it to that goal; if they said how much '
      'they save per month, use it as monthly_contribution; respect their '
      'preferences when picking ideas.\n'
      '- If the fact answers what you would ask, don\'t ask again (confirm '
      'it in a few words: "still thinking about the MacBook?").\n'
      '- Don\'t recite it or repeat it from one message to the next; never '
      'open the answer with it. It never changes a number.\n'
      '- since is when you noted it: if it is old and matters for the '
      'answer, confirm it.\n';

  /// Cómo usar `screen_context` (la pantalla desde donde abrió el chat).
  static const screenContextGuidance =
      'About screen_context (what the user was looking at when they opened '
      'the chat; turns_ago 0 = this question):\n'
      '- If the question names nothing else, "this", "this stock", "this '
      'goal", "why did it drop?" or "is it ok?" are about that screen: the '
      'ticker or goal in screen_context. Resolve it without asking.\n'
      '- If the question names another ticker or topic, the question wins.\n'
      '- With turns_ago above 0, use it only if the question is still about '
      'the same thing.\n'
      '- Don\'t mention it ("I see you are on…"). It never changes a '
      'number.\n';

  /// Cómo usar `recent_topics` (tickers de charlas anteriores): para
  /// retomar un tema, no para recitarlo.
  static const recentTopicsGuidance =
      'About recent_topics (tickers the user talked to you about in earlier '
      'conversations: when, and at what price they were):\n'
      '- If the question is about one of them, you can bring it back in one '
      'sentence ("last time you asked me about AMZN, on 10/14, it was at '
      '\$182"); today\'s price comes from get_quote. Don\'t compute the '
      'change since then: say both prices.\n'
      '- If it is not about them, ignore it. Never recite them or open the '
      'answer with them. It never changes a number.\n';

  /// El mensaje de contexto de cada turno: la cartera (y el perfil, si lo
  /// completó). Las instrucciones del perfil van ANTES del JSON y sin llaves:
  /// el análisis de empresa lee la posición parseando desde la primera "{".
  /// Van acá y no en las reglas fijas para no cambiar el hash del prompt
  /// (que exigiría desplegar `ai-chat`).
  static String pinnedContextFor(Map<String, Object?> portfolioBrief) =>
      '${PortfolioBrief.label} — the user\'s CURRENT portfolio (reference '
      'data, refreshed every turn; not part of any question):\n'
      '${_languageLine(portfolioBrief[PortfolioBrief.appLanguageKey])}'
      '${portfolioBrief.containsKey(PortfolioBrief.userProfileKey) ? userProfileGuidance : ''}'
      '${portfolioBrief.containsKey(PortfolioBrief.userMemoryKey) ? userMemoryGuidance : ''}'
      '${portfolioBrief.containsKey(PortfolioBrief.screenContextKey) ? screenContextGuidance : ''}'
      '${portfolioBrief.containsKey(PortfolioBrief.recentTopicsKey) ? recentTopicsGuidance : ''}'
      '${jsonEncode(portfolioBrief)}';

  /// El recordatorio de idioma de cada turno (ver LANGUAGE en las reglas).
  static String _languageLine(Object? appLanguage) => appLanguage == 'en'
      ? 'App language: ENGLISH. Reply in English (natural US English) '
          'unless the user\'s latest message is clearly written in Spanish.\n'
      : 'App language: SPANISH. Reply in Spanish (Rioplatense voseo) unless '
          'the user\'s latest message is clearly written in English.\n';

  /// Un turno de Porty: [question] + resumen de cartera fresco + tools.
  Future<TurnOutcome> ask({
    required String question,
    required Map<String, Object?> portfolioBrief,
    required String surfaceId,
    required List<DataTool> tools,
    TurnAbortCheck? abortCheck,
    TurnActivityCallback? onActivity,
    BeforeToolRound? beforeRound,
    ContentDeltaCallback? onContent,
  }) {
    return runTurn(
      userText: question,
      surfaceId: surfaceId,
      tools: tools,
      abortCheck: abortCheck,
      onActivity: onActivity,
      beforeRound: beforeRound,
      onContent: onContent,
      resultExtras: _resultExtras,
      pinnedContext: pinnedContextFor(portfolioBrief),
      context:
          'SURFACE_ID (usar exactamente en createSurface y '
          'updateComponents): $surfaceId\n\n'
          'PREGUNTA DEL USUARIO:',
    );
  }
}
