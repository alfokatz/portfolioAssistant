import 'dart:async';
import 'dart:convert';

import 'package:dart_openai/dart_openai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:genui/genui.dart';
import 'package:http/http.dart' as http;
import 'package:portfolio_assistant/features/genui_core/tool_calling/conversation_log.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/openai_body_patch_client.dart';
import 'package:portfolio_assistant/features/genui_core/utils/a2ui_controller_dispatch.dart';
import 'package:portfolio_assistant/features/genui_core/utils/async_call_queue.dart';
import 'package:portfolio_assistant/features/genui_core/utils/a2ui_response_normalizer.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_debug_log.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_error_message.dart';
import 'package:portfolio_assistant/features/genui_core/utils/llm_json_sanitizer.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_surface_readiness.dart';
import 'package:portfolio_assistant/features/genui_core/utils/openai_request_throttle.dart';

export 'package:portfolio_assistant/features/genui_core/genui_surface_ids.dart';

/// Resultado de un turno: qué tools corrieron (para cuota, avisos y
/// telemetría).
class TurnOutcome {
  const TurnOutcome(this.toolCalls);

  final List<ToolCallRecord> toolCalls;

  bool ran(String toolName) => toolCalls.any((c) => c.name == toolName);
}

/// Un turno cortado a propósito después de una ronda de tools (ej. todo lo
/// que pidió el modelo está fuera del plan del usuario): el turno se
/// descarta del historial y [reason] vuelve al llamador.
class TurnAbortedException implements Exception {
  const TurnAbortedException(this.reason);

  final Object reason;

  @override
  String toString() => 'TurnAbortedException($reason)';
}

/// Verifica la respuesta final antes de mostrarla: devuelve una corrección
/// para el modelo (ej. "mostraste QaFundamentals sin get_fundamentals"), o
/// `null` si está bien. [visibleCalls] son las tool calls cuyos resultados
/// el modelo tiene a la vista.
typedef AnswerCheck =
    String? Function(String rawAnswer, List<ToolCallRecord> visibleCalls);

/// Decide, con los resultados de una ronda, si el turno se corta ahí.
/// Devuelve el motivo, o `null` para seguir.
typedef TurnAbortCheck = Object? Function(List<ToolCallRecord> roundCalls);

/// Servicio GenUI sobre OpenAI Chat Completions con tool calling.
///
/// Un turno ([runTurn]):
/// 1. el modelo recibe el historial ([ConversationLog]) y las tools de datos;
/// 2. si pide tools, se ejecutan en paralelo y sus resultados vuelven al
///    historial — hasta [maxToolRounds] rondas;
/// 3. la respuesta sin tool calls es la final: A2UI en texto, que pasa por
///    el sanitizer/normalizer/dispatch de siempre hacia genui (que solo
///    renderiza — genui no participa de la decisión de datos).
///
/// Sin streaming: la respuesta A2UI solo sirve completa (se sanea y
/// despacha al final), así que un `create` no cambia lo que ve el usuario,
/// un turno sin tools sigue siendo 1 llamada, y la respuesta trae `usage`.
///
/// Por defecto usa [defaultModel]; override con `OPENAI_MODEL` en `.env`.
class OpenAIGenUiService {
  static const defaultModel = 'gpt-4.1-mini';
  static const maxRateLimitRetries = 3;

  /// Rondas con tools por turno; después, una ronda más con
  /// `tool_choice: none` obliga a responder. Máximo 3 llamadas por turno.
  static const maxToolRounds = 2;

  /// Tools ejecutadas por turno (protege Finnhub/Yahoo, cuya key comparten
  /// todos los usuarios, de un modelo que pida de más).
  static const maxToolCallsPerTurn = 6;

  // Reintento corto para fallas transitorias que NO son rate-limit: la
  // ronda final colgada, o un payload que ya reparado seguía sin
  // componente raíz. Solo re-pide la ronda final: las tools ya corrieron.
  static const maxTransientRetries = 1;
  static const _transientRetryBackoff = Duration(milliseconds: 600);

  static const _toolRoundTimeout = Duration(seconds: 10);
  static const _finalRoundTimeout = Duration(seconds: 20);
  static const _toolTimeout = Duration(seconds: 8);

  // Deadline del turno completo, por debajo de los 60 s de
  // `GenUiRequestTracker`: si no alcanza para otra ronda de tools, la
  // siguiente es la final.
  static const _turnDeadline = Duration(seconds: 55);
  static const _minTimeForToolRound = Duration(seconds: 25);

  static const _temperature = 0.35;

  OpenAIGenUiService({
    String? apiKey,
    String? model,
    required this.systemPrompt,
    required Catalog catalog,
    this.a2uiCatalogId,
    this.postProcess,
    this.answerCheck,
    http.Client? httpClient,
  }) : apiKey = apiKey ?? dotenv.env['OPENAI_API_KEY'] ?? '',
       model = model ?? dotenv.env['OPENAI_MODEL'] ?? defaultModel,
       _httpClient = OpenAiBodyPatchClient(httpClient),
       log = ConversationLog(systemPrompt: systemPrompt) {
    OpenAI.apiKey = this.apiKey;
    controller = SurfaceController(catalogs: [catalog]);
    transport = A2uiTransportAdapter(onSend: handleSend);
    conversation = Conversation(controller: controller, transport: transport);
    // `Conversation` ya reenvía `controller.onSubmit` a `handleSend` (ej. el
    // mensaje que arma genui tras una validación fallida); esta suscripción
    // es solo para loguearlo.
    _debugResubmitSubscription = controller.onSubmit.listen(
      GenUiDebugLog.controllerResubmit,
    );
  }

  final String apiKey;
  final String model;
  final String systemPrompt;
  final String? a2uiCatalogId;

  /// Ajuste propio del producto sobre el A2UI ya normalizado, antes de
  /// despacharlo (ej. reglas de layout que el modelo no siempre respeta).
  final String Function(String normalized)? postProcess;

  /// Ver [AnswerCheck]. Se aplica una vez por turno: si falla, el modelo
  /// recibe la corrección y una ronda más con tools obligatorias.
  final AnswerCheck? answerCheck;
  final http.Client _httpClient;
  final ConversationLog log;
  late final SurfaceController controller;
  late final A2uiTransportAdapter transport;
  late final Conversation conversation;
  bool isDisposed = false;
  StreamSubscription<ChatMessage>? _debugResubmitSubscription;

  // Tools y surface del último turno: los reusa la reparación que dispara
  // genui tras una validación fallida (llega sin surfaceId ni tools).
  List<DataTool> _lastTools = const [];
  String? _lastSurfaceId;
  var _repairsThisTurn = 0;
  static const _maxRepairsPerTurn = 1;

  // Serializa todo lo que toca [log]: un turno nuevo y una reparación de
  // genui (o un turno viejo que siguió corriendo tras un timeout externo —
  // los Future de Dart no se cancelan) nunca se intercalan.
  final _sendQueue = AsyncCallQueue();

  /// Un turno completo del usuario. [context] va pegado al mensaje de este
  /// turno; [pinnedContext] va como mensaje de sistema antes de toda la
  /// conversación y reemplaza al del turno anterior (ver
  /// `ConversationLog.pinnedContext`). [abortCheck] se evalúa tras la
  /// primera ronda de tools.
  Future<TurnOutcome> runTurn({
    required String userText,
    required String surfaceId,
    required List<DataTool> tools,
    String? context,
    String? pinnedContext,
    TurnAbortCheck? abortCheck,
  }) {
    return _sendQueue.run(() {
      log.pinnedContext = pinnedContext;
      return _runTurn(
        userText: userText,
        surfaceId: surfaceId,
        tools: tools,
        context: context,
        abortCheck: abortCheck,
      );
    });
  }

  /// Entrada de genui (`A2uiTransportAdapter.onSend`): mensajes que la UI
  /// arma sola, sin pasar por el provider — hoy solo el error de validación
  /// de `SurfaceController.reportError`. Se responde con una ronda final
  /// sobre el último turno (sin tools nuevas), como mucho una vez por turno.
  Future<void> handleSend(ChatMessage message) {
    return _sendQueue.run(() => _repair(message));
  }

  /// Turno resuelto fuera del loop que igual tiene que quedar en la memoria
  /// del modelo.
  void recordExternalTurn(String userText, String answer) {
    unawaited(
      _sendQueue.run(() async => log.addCompletedTurn(userText, answer)),
    );
  }

  Future<TurnOutcome> _runTurn({
    required String userText,
    required String surfaceId,
    required List<DataTool> tools,
    String? context,
    TurnAbortCheck? abortCheck,
  }) async {
    if (apiKey.isEmpty) {
      throw StateError('OPENAI_API_KEY no configurada');
    }
    _lastTools = tools;
    _lastSurfaceId = surfaceId;
    _repairsThisTurn = 0;

    final turn = log.beginTurn(userText, context: context);
    final deadline = DateTime.now().add(_turnDeadline);
    final executor = _ToolExecutor(tools);

    Object? forcedChoice;
    var retried = false;
    var checked = false;
    var extraRound = false;
    for (var round = 0; ; round++) {
      final canUseTools =
          tools.isNotEmpty &&
          (round < maxToolRounds || extraRound) &&
          executor.hasBudget &&
          deadline.difference(DateTime.now()) > _minTimeForToolRound;
      extraRound = false;

      final message = await _request(
        tools: tools,
        toolChoice: !canUseTools ? 'none' : forcedChoice ?? 'auto',
        timeout: canUseTools ? _toolRoundTimeout : _finalRoundTimeout,
        throttle: round == 0,
        deadline: deadline,
      );

      final calls = message.toolCalls;
      if (canUseTools && calls != null && calls.isNotEmpty) {
        final records = await executor.runAll(calls);
        turn.calls.addAll(records);
        turn.exchanges.add(
          ToolExchange(
            call: message,
            results: [
              for (var i = 0; i < calls.length; i++)
                RequestFunctionMessage(
                  role: OpenAIChatMessageRole.tool,
                  content: [
                    OpenAIChatCompletionChoiceMessageContentItemModel.text(
                      jsonEncode(records[i].result),
                    ),
                  ],
                  toolCallId: calls[i].id!,
                ),
            ],
          ),
        );
        GenUiDebugLog.toolRound(round: round, calls: records);

        // Una tool pidió que la vuelvan a llamar con otros argumentos: la
        // próxima ronda se fuerza a esa tool (sin eso, el modelo tiende a
        // responder en texto en vez de reintentar — verificado en evals).
        forcedChoice = null;
        if (!retried) {
          for (final record in records) {
            if (record.status == DataTool.needsRetryStatus) {
              forcedChoice = {
                'type': 'function',
                'function': {'name': record.name},
              };
              retried = true;
              break;
            }
          }
        }

        if (round == 0 && abortCheck != null) {
          final reason = abortCheck(records);
          if (reason != null) {
            log.dropLastTurn();
            throw TurnAbortedException(reason);
          }
        }
        continue;
      }

      final raw = _textOf(message);
      final check = answerCheck;
      if (check != null && !checked && tools.isNotEmpty) {
        checked = true;
        final correction = check(raw, log.visibleCalls);
        if (correction != null &&
            deadline.difference(DateTime.now()) > _minTimeForToolRound) {
          GenUiDebugLog.answerRejected(correction);
          turn
            ..scratchAfter = turn.exchanges.length
            ..scratch.addAll([
              message,
              OpenAIChatCompletionChoiceMessageModel(
                role: OpenAIChatMessageRole.user,
                content: [
                  OpenAIChatCompletionChoiceMessageContentItemModel.text(
                    correction,
                  ),
                ],
              ),
            ]);
          forcedChoice = 'required';
          extraRound = true;
          continue;
        }
      }

      turn.scratch.clear();
      await _finishTurn(turn, raw, surfaceId, tools, deadline);
      return TurnOutcome(executor.records);
    }
  }

  /// Aplica la respuesta final; si no deja una surface válida, reintenta
  /// una sola vez la ronda final (las tools ya están en el historial).
  Future<void> _finishTurn(
    TurnRecord turn,
    String raw,
    String surfaceId,
    List<DataTool> tools,
    DateTime deadline,
  ) async {
    var attempt = raw;
    for (var transient = 0; ; transient++) {
      try {
        _applyFinal(attempt, surfaceId);
        turn.finalText = attempt;
        return;
      } on StateError {
        if (isDisposed || transient >= maxTransientRetries) rethrow;
        await Future<void>.delayed(_transientRetryBackoff);
        final retry = await _request(
          tools: tools,
          toolChoice: 'none',
          timeout: _finalRoundTimeout,
          throttle: false,
          deadline: deadline,
        );
        attempt = _textOf(retry);
      }
    }
  }

  Future<void> _repair(ChatMessage message) async {
    var text = message.text.trim();
    if (text.isEmpty) {
      final interactions = message.parts.uiInteractionParts;
      if (interactions.isNotEmpty) {
        text = _describeInteraction(interactions.first.interaction);
      }
    }
    if (text.isEmpty) return;

    final turn = log.currentTurn;
    final surfaceId = _lastSurfaceId;
    if (turn == null || surfaceId == null) return;
    if (_repairsThisTurn >= _maxRepairsPerTurn) return;
    _repairsThisTurn++;

    if (apiKey.isEmpty) {
      throw StateError('OPENAI_API_KEY no configurada');
    }
    final reply = await _request(
      tools: _lastTools,
      toolChoice: 'none',
      timeout: _finalRoundTimeout,
      throttle: true,
      extra: [
        OpenAIChatCompletionChoiceMessageModel(
          role: OpenAIChatMessageRole.user,
          content: [
            OpenAIChatCompletionChoiceMessageContentItemModel.text(text),
          ],
        ),
      ],
    );
    final raw = _textOf(reply);
    _applyFinal(raw, surfaceId);
    turn.finalText = raw;
  }

  /// Un request con retry ante rate limit. Nunca reejecuta tools.
  Future<OpenAIChatCompletionChoiceMessageModel> _request({
    required List<DataTool> tools,
    required Object toolChoice,
    required Duration timeout,
    required bool throttle,
    List<OpenAIChatCompletionChoiceMessageModel> extra = const [],
    DateTime? deadline,
  }) async {
    for (var attempt = 0; ; attempt++) {
      if (throttle) {
        // Espacia turnos, no las rondas de un mismo turno: una
        // continuación ya está "adentro" de un pedido del usuario.
        await OpenAiRequestThrottle.waitIfNeeded();
        OpenAiRequestThrottle.markRequestStarted();
      }
      try {
        final response = await OpenAI.instance.chat
            .create(
              model: model,
              messages: [...log.render(), ...extra],
              tools:
                  tools.isEmpty
                      ? null
                      : [for (final tool in tools) tool.toOpenAi()],
              toolChoice: tools.isEmpty ? null : toolChoice,
              temperature: _temperature,
              client: _httpClient,
            )
            .timeout(
              timeout,
              onTimeout:
                  () =>
                      throw TimeoutException(
                        'El modelo tardó demasiado en responder.',
                      ),
            );
        return response.choices.first.message;
      } on RequestFailedException catch (e) {
        final canRetry =
            isOpenAiRateLimitError(e) && attempt < maxRateLimitRetries;
        if (!canRetry || isDisposed) rethrow;
        final seconds = openAiSuggestedRetrySeconds(e.message) ?? 5;
        final wait = Duration(
          milliseconds: ((seconds + 1) * 1000).clamp(2000, 120000),
        );
        // Sin deadline, una ráfaga de 429 podía dejar al servicio esperando
        // minutos con la cola tomada (el tracker ya cortó a los 60 s y el
        // turno siguiente queda atrás de este). Si la espera no entra en el
        // tiempo del turno, se corta acá.
        if (deadline != null &&
            DateTime.now().add(wait).add(timeout).isAfter(deadline)) {
          rethrow;
        }
        await Future<void>.delayed(wait);
      }
    }
  }

  static String _textOf(OpenAIChatCompletionChoiceMessageModel message) =>
      message.content?.map((c) => c.text ?? '').join() ?? '';

  /// Sanea, normaliza y despacha el A2UI de la ronda final. Tira
  /// [StateError] si la surface no quedó con componente raíz.
  void _applyFinal(String raw, String surfaceId) {
    if (isDisposed) return;
    final catalogId = a2uiCatalogId ?? A2uiResponseNormalizer.defaultCatalogId;
    GenUiDebugLog.rawResponse(surfaceId: surfaceId, raw: raw);

    var cleaned = LlmJsonSanitizer.sanitizeOrFallback(
      raw,
      surfaceId: surfaceId,
      catalogId: catalogId,
    );
    if (cleaned.isEmpty) {
      cleaned = A2uiResponseNormalizer.fallbackResponse(
        surfaceId,
        LlmJsonSanitizer.defaultFallbackMessage,
        catalogId: catalogId,
      );
    }
    final normalized = A2uiResponseNormalizer.normalize(
      cleaned,
      surfaceId: surfaceId,
      catalogId: catalogId,
      ensureCreateSurface: controller.registry.getSurface(surfaceId) == null,
    );
    cleaned =
        normalized.trim().isEmpty
            ? A2uiResponseNormalizer.fallbackResponse(
              surfaceId,
              LlmJsonSanitizer.defaultFallbackMessage,
              catalogId: catalogId,
            )
            : normalized;

    final post = postProcess;
    if (post != null) cleaned = post(cleaned);
    GenUiDebugLog.componentChoice(surfaceId: surfaceId, normalized: cleaned);
    A2uiControllerDispatch.dispatchNormalized(controller, cleaned);

    if (!GenUiSurfaceReadiness.hasRootComponent(
      controller.registry.getSurface(surfaceId),
    )) {
      throw StateError(
        'La IA no generó una interfaz válida. Intentá reformular la consulta.',
      );
    }
  }

  /// Convierte el JSON de un `UiInteractionPart` en una instrucción legible.
  /// El único que dispara la app es el error de validación de
  /// `SurfaceController.reportError` (`{"error": {...}}`); cualquier otra
  /// forma se reenvía tal cual.
  static String _describeInteraction(String interactionJson) {
    try {
      final decoded = jsonDecode(interactionJson);
      if (decoded is Map && decoded['error'] is Map) {
        final error = decoded['error'] as Map;
        final message =
            error['message'] as String? ?? 'la interfaz no pudo renderizarse.';
        return 'ERROR DE VALIDACIÓN en tu última respuesta para este '
            'surface: $message Corregí la interfaz: usá solo ids que ya '
            'definiste vos mismo (o que ya existen) y tipos de componente '
            'que estén en el catálogo, y volvé a emitir createSurface + '
            'updateComponents completos para este mismo surface.';
      }
    } catch (_) {
      // Best-effort — si no es JSON o no tiene la forma esperada, se
      // reenvía tal cual abajo.
    }
    return interactionJson;
  }

  void dispose() {
    isDisposed = true;
    _debugResubmitSubscription?.cancel();
    conversation.dispose();
    transport.dispose();
    controller.dispose();
    _httpClient.close();
  }
}

/// Ejecuta las tool calls de un turno: en paralelo, con timeout por tool,
/// presupuesto por turno y sin repetir una llamada idéntica.
class _ToolExecutor {
  _ToolExecutor(List<DataTool> tools)
    : _byName = {for (final tool in tools) tool.name: tool};

  final Map<String, DataTool> _byName;
  final records = <ToolCallRecord>[];
  final _memo = <String, Map<String, Object?>>{};

  bool get hasBudget => records.length < OpenAIGenUiService.maxToolCallsPerTurn;

  Future<List<ToolCallRecord>> runAll(
    List<OpenAIResponseToolCall> calls,
  ) async {
    var remaining = OpenAIGenUiService.maxToolCallsPerTurn - records.length;
    final futures = <Future<ToolCallRecord>>[];
    for (final call in calls) {
      final name = call.function.name ?? '';
      final args = _decodeArgs(call.function.arguments);
      if (remaining <= 0) {
        futures.add(
          Future.value(
            ToolCallRecord(
              name: name,
              args: args ?? const {},
              result: const {'status': 'failed', 'reason': 'budget_exhausted'},
            ),
          ),
        );
        continue;
      }
      remaining--;
      futures.add(_runOne(name, args));
    }
    final done = await Future.wait(futures);
    records.addAll(done);
    return done;
  }

  Future<ToolCallRecord> _runOne(
    String name,
    Map<String, Object?>? args,
  ) async {
    if (args == null) {
      return ToolCallRecord(
        name: name,
        args: const {},
        result: const {'status': 'failed', 'reason': 'invalid_arguments'},
      );
    }
    final tool = _byName[name];
    if (tool == null) {
      return ToolCallRecord(
        name: name,
        args: args,
        result: const {'status': 'failed', 'reason': 'unknown_tool'},
      );
    }
    final key = '$name:${jsonEncode(args)}';
    final cached = _memo[key];
    if (cached != null) {
      return ToolCallRecord(name: name, args: args, result: cached);
    }
    Map<String, Object?> result;
    try {
      result = await tool.run(args).timeout(OpenAIGenUiService._toolTimeout);
    } on TimeoutException {
      result = const {'status': 'failed', 'reason': 'timeout'};
    } catch (_) {
      result = const {'status': 'failed', 'reason': 'error'};
    }
    // Un reintento pedido por la tool, o una falla, no se memoiza: la
    // próxima llamada idéntica tiene que volver a ejecutarse.
    final status = result['status'];
    if (status != DataTool.needsRetryStatus && status != 'failed') {
      _memo[key] = result;
    }
    return ToolCallRecord(name: name, args: args, result: result);
  }

  static Map<String, Object?>? _decodeArgs(Object? raw) {
    if (raw is Map) return Map<String, Object?>.from(raw);
    if (raw is! String || raw.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, Object?>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }
}
