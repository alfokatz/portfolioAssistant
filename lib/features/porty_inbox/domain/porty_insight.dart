import 'package:portfolio_assistant/features/assistant/models/porty_screen_context.dart';

/// Lo que Porty puede marcar en la Home. Cada uno sale de un cálculo de la
/// app con los números que el usuario ya ve (nunca del modelo).
enum PortyInsightKind {
  /// La cartera se alejó del plan más que el umbral del usuario.
  allocationDrift,

  /// Una meta pasó la fecha sin llegar.
  goalOverdue,

  /// Una meta viene atrasada respecto de su plan.
  goalBehind,

  /// A una meta le falta poco (90 % o más).
  goalAlmost,

  /// Una sola acción pesa mucho en la cartera.
  concentration,

  /// Una acción que tiene está cerca del precio de una alerta suya.
  alertNear,

  /// Una posición con peso acumula una pérdida grande desde la compra.
  deepLoss,
}

/// Cómo se lee: pide atención, es un dato, o es una buena noticia. Decide
/// el color del ícono y la cara de Porty arriba de la lista.
enum PortyInsightTone { attention, neutral, good }

/// Una cosa que Porty marca en la Home: qué es, de qué (ticker o meta), los
/// números para el texto y cuánto importa para ordenar.
class PortyInsight {
  const PortyInsight({
    required this.kind,
    required this.subject,
    required this.tone,
    required this.score,
    this.ticker,
    this.goalLabel,
    this.numbers = const {},
  });

  final PortyInsightKind kind;

  /// De qué es (ticker, id de la meta, "plan"): con [kind] arma el [id].
  final String subject;
  final PortyInsightTone tone;

  /// Mayor = más arriba. Combina cuánto importa el tipo y la magnitud.
  final double score;
  final String? ticker;
  final String? goalLabel;

  /// Los números del texto (porcentajes en puntos, montos en dólares).
  final Map<String, double> numbers;

  /// Identifica el insight para ocultarlo ("ya lo vi").
  String get id => '${kind.name}:$subject';

  /// La pantalla de la que habla: viaja con la pregunta a Porty.
  PortyScreenContext get screen => switch (kind) {
    PortyInsightKind.allocationDrift => const PortyScreenContext(
      PortyScreen.allocation,
    ),
    PortyInsightKind.goalOverdue ||
    PortyInsightKind.goalBehind ||
    PortyInsightKind.goalAlmost => PortyScreenContext(
      PortyScreen.goalDetail,
      goalLabel: goalLabel,
    ),
    PortyInsightKind.concentration ||
    PortyInsightKind.alertNear ||
    PortyInsightKind.deepLoss => PortyScreenContext.position(ticker ?? ''),
  };
}
