import 'package:portfolio_assistant/features/home_widget/domain/widget_questions.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_texts.dart';
import 'package:portfolio_assistant/presentation/shared/formatting/app_number_format.dart';

/// Los tipos de aviso de la Home (mismos nombres que `PortyInsightKind`).
/// El widget no importa la feature de la bandeja: el adaptador mapea por
/// `kind.name`.
enum WidgetInsightKind {
  allocationDrift('drift', WidgetQuestionTemplate.planFar),
  goalOverdue('goal_overdue', WidgetQuestionTemplate.goalProgress),
  goalBehind('goal_behind', WidgetQuestionTemplate.goalProgress),
  goalAlmost('goal_almost', WidgetQuestionTemplate.goalProgress),
  concentration('concentration', WidgetQuestionTemplate.biggest),
  alertNear('alert_near', WidgetQuestionTemplate.alertWeek),
  deepLoss('deep_loss', WidgetQuestionTemplate.sinceBought),
  topicMoved('topic_moved', WidgetQuestionTemplate.topicSince);

  const WidgetInsightKind(this.key, this.question);

  /// Parte de la clave `porty_inbox_<key>_title`.
  final String key;

  /// La pregunta de su kind (§4.4 regla 3).
  final WidgetQuestionTemplate question;

  bool get isGoal =>
      this == goalOverdue || this == goalBehind || this == goalAlmost;

  static WidgetInsightKind? fromName(String name) {
    for (final k in values) {
      if (k.name == name) return k;
    }
    return null;
  }
}

/// Un aviso de la Home tal como lo necesita el widget (ya ordenado por
/// `score` desc y sin los "ya lo vi").
class WidgetInsightInput {
  const WidgetInsightInput({
    required this.id,
    required this.kind,
    required this.score,
    this.ticker,
    this.goalLabel,
    this.numbers = const {},
  });

  /// `PortyInsight.id` (`kind:subject`).
  final String id;
  final WidgetInsightKind kind;
  final double score;
  final String? ticker;
  final String? goalLabel;

  /// Los mismos `numbers` de `PortyInsight` (`weight`, `pnl`, `change`...).
  final Map<String, double> numbers;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'score': score,
    if (ticker != null) 'ticker': ticker,
    if (goalLabel != null) 'goal_label': goalLabel,
    'numbers': numbers,
  };

  static WidgetInsightInput? fromJson(Map<String, Object?> json) {
    final kind = WidgetInsightKind.fromName(json['kind'] as String? ?? '');
    final id = json['id'];
    final score = json['score'];
    if (kind == null || id is! String || score is! num) return null;
    final raw = json['numbers'];
    return WidgetInsightInput(
      id: id,
      kind: kind,
      score: score.toDouble(),
      ticker: json['ticker'] as String?,
      goalLabel: json['goal_label'] as String?,
      numbers: {
        if (raw is Map)
          for (final e in raw.entries)
            if (e.key is String && e.value is num)
              e.key as String: (e.value as num).toDouble(),
      },
    );
  }
}

/// El título de cada aviso, con las MISMAS claves `porty_inbox_*_title` de
/// la Home y el mismo formato de %. Sin `.tr()`: corre en el isolate de
/// fondo. Nunca lleva montos (los títulos de la Home no los tienen).
abstract final class WidgetInsightCopy {
  static String _pct(double? v, {int decimals = 0}) =>
      AppNumberFormat.percent(v ?? 0, decimals: decimals, signed: false);

  static String title(WidgetInsightInput i, WidgetTexts t) {
    final n = i.numbers;
    final args = {
      'ticker': i.ticker ?? '',
      'goal': i.goalLabel ?? '',
      'weight': _pct(n['weight']),
      'pnl': AppNumberFormat.percent(n['pnl'] ?? 0, decimals: 0),
      'move': AppNumberFormat.percent((n['change'] ?? 0).abs(), signed: false),
    };
    if (i.kind == WidgetInsightKind.topicMoved) {
      return t.getInbox(
        (n['change'] ?? 0) < 0
            ? 'topic_moved_down_title'
            : 'topic_moved_up_title',
        args,
      );
    }
    return t.getInbox('${i.kind.key}_title', args);
  }
}
