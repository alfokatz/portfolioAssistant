import 'dart:convert';

import 'package:genui/genui.dart';
import 'package:http/http.dart' as http;
import 'package:portfolio_assistant/features/assistant/catalog/assistant_catalog.dart';
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
  }) : super(
         postProcess: AssistantAnswerReview.postProcess,
         answerCheck: AssistantAnswerReview.check,
       );

  factory AssistantOpenAiService({
    AiProxyConfig? proxy,
    String? model,
    http.Client? httpClient,
  }) {
    final catalog = AssistantCatalog.build();
    return AssistantOpenAiService._(
      proxy: proxy,
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

  /// Cómo usar `user_profile` sin volverse repetitivo: solo cuando cambia
  /// la respuesta, y la experiencia se nota en el tono, no se nombra.
  static const userProfileGuidance =
      'Sobre user_profile (el perfil de inversor que completó el usuario):\n'
      '- Usalo SOLO cuando cambia la respuesta: concentración o '
      'diversificación, caídas o volatilidad, el riesgo de una acción, ideas '
      'de inversión y metas. Para todo lo demás (precios, noticias, '
      'resultados, datos de la cartera) ignoralo.\n'
      '- No lo nombres salvo que sea la razón concreta de lo que decís; nunca '
      'abras la respuesta con él ni lo repitas de un mensaje a otro.\n'
      '- experience ajusta el nivel en silencio: principiante = sin jerga y '
      'con una línea de contexto; avanzada = directo. Nunca digas "como sos '
      'principiante".\n'
      '- drawdown_reaction "vendería" y la cartera o una acción cae fuerte → '
      'contexto calmo, sin alarmismo.\n'
      '- stale true → el perfil tiene más de un año; usalo igual, sin '
      'mencionarlo.\n'
      '- Nunca cambia un número.\n';

  /// Cómo usar `user_memory` (lo que Porty anotó del usuario en charlas
  /// anteriores): para conectar la respuesta con su vida, no para recitarlo.
  static const userMemoryGuidance =
      'Sobre user_memory (lo que sabés del usuario por charlas anteriores):\n'
      '- Usalo para que la respuesta sea SUYA: si pregunta cómo ahorrar o '
      'invertir y tiene una meta anotada, conectalo con esa meta; si dijo '
      'cuánto ahorra por mes, usalo como monthly_contribution; respetá sus '
      'preferencias al elegir ideas.\n'
      '- Si el dato resuelve lo que preguntarías, no lo preguntes de nuevo '
      '(confirmalo en pocas palabras: "¿seguís con la idea de la MacBook?").\n'
      '- No lo recites ni lo repitas de un mensaje a otro; nunca abras la '
      'respuesta con él. Nunca cambia un número.\n'
      '- since es la fecha en que lo anotaste: si es viejo y pesa en la '
      'respuesta, confirmalo.\n';

  /// El mensaje de contexto de cada turno: la cartera (y el perfil, si lo
  /// completó). Las instrucciones del perfil van ANTES del JSON y sin llaves:
  /// el análisis de empresa lee la posición parseando desde la primera "{".
  /// Van acá y no en las reglas fijas para no cambiar el hash del prompt
  /// (que exigiría desplegar `ai-chat`).
  static String pinnedContextFor(Map<String, Object?> portfolioBrief) =>
      '${PortfolioBrief.label} — la cartera ACTUAL del usuario (dato de '
      'referencia, se actualiza en cada turno; no es parte de ninguna '
      'pregunta):\n'
      '${portfolioBrief.containsKey(PortfolioBrief.userProfileKey) ? userProfileGuidance : ''}'
      '${portfolioBrief.containsKey(PortfolioBrief.userMemoryKey) ? userMemoryGuidance : ''}'
      '${jsonEncode(portfolioBrief)}';

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
      pinnedContext: pinnedContextFor(portfolioBrief),
      context:
          'SURFACE_ID (usar exactamente en createSurface y '
          'updateComponents): $surfaceId\n\n'
          'PREGUNTA DEL USUARIO:',
    );
  }
}
