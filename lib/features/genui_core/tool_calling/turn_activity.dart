/// En qué anda un turno de tool calling, para mostrárselo al usuario
/// mientras espera (ver `PortyHeader`). Es solo lectura: nadie decide nada
/// a partir de esto.
enum TurnPhase {
  /// Sin turno en curso.
  idle,

  /// Esperando la primera respuesta del modelo (o preparando el turno).
  thinking,

  /// Ejecutando las tools de [TurnActivity.calls], en paralelo.
  runningTools,

  /// Las tools ya volvieron; el modelo arma la respuesta final.
  composing,
}

/// Una tool que el modelo pidió y todavía no terminó.
class PendingToolCall {
  const PendingToolCall(this.name, [this.args = const {}]);

  final String name;
  final Map<String, Object?> args;
}

class TurnActivity {
  const TurnActivity._(this.phase, [this.calls = const []]);

  const TurnActivity.tools(List<PendingToolCall> calls)
    : this._(TurnPhase.runningTools, calls);

  static const idle = TurnActivity._(TurnPhase.idle);
  static const thinking = TurnActivity._(TurnPhase.thinking);
  static const composing = TurnActivity._(TurnPhase.composing);

  final TurnPhase phase;

  /// Solo en [TurnPhase.runningTools].
  final List<PendingToolCall> calls;

  bool get isIdle => phase == TurnPhase.idle;
}

typedef TurnActivityCallback = void Function(TurnActivity activity);
