import 'package:dart_openai/dart_openai.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';

/// Una ronda de tools: el mensaje del asistente con `tool_calls` y un
/// mensaje `tool` por cada `tool_call_id`, en el mismo orden. Se guardan
/// juntos porque la API rechaza (400) uno sin el otro:
/// "An assistant message with 'tool_calls' must be followed by tool
/// messages responding to each 'tool_call_id'" y "messages with role
/// 'tool' must be a response to a preceeding message with 'tool_calls'"
/// (verificado contra gpt-4.1-mini).
class ToolExchange {
  ToolExchange({required this.call, required this.results})
    : assert(
        (call.toolCalls?.length ?? 0) == results.length,
        'Every tool_call_id needs exactly one tool message.',
      );

  final OpenAIChatCompletionChoiceMessageModel call;
  final List<RequestFunctionMessage> results;
}

/// Un turno de la conversación tal como se le reenvía al modelo.
class TurnRecord {
  TurnRecord({required this.userText, this.context});

  /// Lo que escribió el usuario (o, para un turno sintético, su resumen).
  final String userText;

  /// Contexto efímero del turno (ej. el resumen de cartera): va solo en
  /// el request de ESTE turno y no se reenvía después — los datos viejos
  /// no deben competir con los frescos.
  String? context;

  final List<ToolExchange> exchanges = [];

  /// Tool calls ejecutadas en este turno (con su resultado).
  final List<ToolCallRecord> calls = [];

  /// Una respuesta rechazada + la corrección pedida, en el lugar
  /// cronológico donde ocurrieron (después de [scratchAfter] rondas). Solo
  /// se envía mientras el turno está en curso: al cerrarlo se descarta, así
  /// el historial no guarda la respuesta mala.
  final List<OpenAIChatCompletionChoiceMessageModel> scratch = [];
  int scratchAfter = 0;

  /// Respuesta final cruda del modelo (A2UI). `null` si el turno falló.
  String? finalText;
}

/// Historial de la conversación para Chat Completions, armado por turnos.
///
/// Reemplaza a una lista plana recortada por cantidad de mensajes: un
/// recorte así puede separar un `tool_calls` de sus respuestas (400).
/// Acá la integridad es por construcción — [render] emite cada
/// [ToolExchange] completo o no lo emite.
///
/// Memoria (ver docs/superpowers/plans/2026-09-29-tool-calling-migration.md
/// §E.2): los últimos [rawTurns] turnos van completos, con sus tool calls y
/// resultados, así un seguimiento ("¿cuánto subió?") puede usar los datos
/// ya traídos. Los anteriores se compactan a pregunta + respuesta final
/// (que igual trae los números que se mostraron), y más allá de [maxTurns]
/// se descartan.
class ConversationLog {
  ConversationLog({
    required this.systemPrompt,
    this.rawTurns = 3,
    this.maxTurns = 12,
  });

  final String systemPrompt;

  /// Contexto de referencia que va como segundo mensaje de sistema, ANTES
  /// de la conversación, y se reemplaza en cada turno (ej. la cartera
  /// actual). Lejos de la última pregunta: pegado al mensaje del usuario,
  /// el modelo lo tomaba como sujeto de preguntas sin sujeto ("¿cuánto
  /// subió?" → la cartera en vez del ticker del que se venía hablando).
  String? pinnedContext;
  final int rawTurns;
  final int maxTurns;
  final List<TurnRecord> turns = [];

  TurnRecord beginTurn(String userText, {String? context}) {
    final turn = TurnRecord(userText: userText, context: context);
    turns.add(turn);
    if (turns.length > maxTurns) {
      turns.removeRange(0, turns.length - maxTurns);
    }
    return turn;
  }

  /// Turno ya resuelto por otro medio que igual tiene que quedar en la
  /// memoria del modelo (no pasó por el loop).
  void addCompletedTurn(String userText, String answer) {
    beginTurn(userText).finalText = answer;
  }

  TurnRecord? get currentTurn => turns.isEmpty ? null : turns.last;

  /// Tool calls de los turnos cuyo tráfico de tools todavía se reenvía al
  /// modelo (los últimos [rawTurns], incluido el actual): lo que el modelo
  /// tiene "a la vista" como datos.
  List<ToolCallRecord> get visibleCalls => [
    for (final turn in turns.skip(
      turns.length > rawTurns ? turns.length - rawTurns : 0,
    ))
      ...turn.calls,
  ];

  /// Saca el último turno (rollback de un turno cortado antes de responder,
  /// ej. paywall).
  void dropLastTurn() {
    if (turns.isNotEmpty) turns.removeLast();
  }

  List<OpenAIChatCompletionChoiceMessageModel> render() {
    final pinned = pinnedContext;
    final messages = <OpenAIChatCompletionChoiceMessageModel>[
      _text(OpenAIChatMessageRole.system, systemPrompt),
      if (pinned != null && pinned.isNotEmpty)
        _text(OpenAIChatMessageRole.system, pinned),
    ];
    for (var i = 0; i < turns.length; i++) {
      final turn = turns[i];
      final isCurrent = i == turns.length - 1;
      final raw = turns.length - 1 - i < rawTurns;

      final context = isCurrent ? turn.context : null;
      messages.add(
        _text(
          OpenAIChatMessageRole.user,
          context == null || context.isEmpty
              ? turn.userText
              : '$context\n\n${turn.userText}',
        ),
      );
      // Un turno viejo que falló (sin respuesta final) no reenvía sus
      // rondas: los datos quedarían colgando sin respuesta que los use.
      if (isCurrent || (raw && turn.finalText != null)) {
        for (var e = 0; e < turn.exchanges.length; e++) {
          if (isCurrent && e == turn.scratchAfter) {
            messages.addAll(turn.scratch);
          }
          messages
            ..add(turn.exchanges[e].call)
            ..addAll(turn.exchanges[e].results);
        }
        if (isCurrent && turn.scratchAfter >= turn.exchanges.length) {
          messages.addAll(turn.scratch);
        }
      }
      final answer = turn.finalText;
      if (answer != null && answer.isNotEmpty) {
        messages.add(_text(OpenAIChatMessageRole.assistant, answer));
      }
    }
    return messages;
  }

  static OpenAIChatCompletionChoiceMessageModel _text(
    OpenAIChatMessageRole role,
    String text,
  ) => OpenAIChatCompletionChoiceMessageModel(
    role: role,
    content: [OpenAIChatCompletionChoiceMessageContentItemModel.text(text)],
  );
}
