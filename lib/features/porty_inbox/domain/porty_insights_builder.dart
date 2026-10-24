import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/features/allocation/domain/allocation_plan.dart';
import 'package:portfolio_assistant/features/goals/domain/goal_progress.dart';
import 'package:portfolio_assistant/features/goals/domain/user_goal.dart';
import 'package:portfolio_assistant/features/notifications/domain/price_alert.dart';
import 'package:portfolio_assistant/features/porty_inbox/domain/porty_insight.dart';
import 'package:portfolio_assistant/features/porty_memory/domain/porty_topic.dart';

/// Arma lo que Porty marca en la Home a partir de lo que la app ya tiene
/// cargado (cartera, plan, metas, alertas). Puro y determinístico: los
/// mismos números que el usuario ve en cada pantalla, sin pasar por el
/// modelo ni gastar una consulta.
///
/// Nunca dice qué hacer: cada insight es un dato y una pregunta para Porty.
/// El precio de hoy de un tema de charla (ver `portyTopicPricesProvider`).
typedef TopicPrice = ({PortyTopic topic, double price});

abstract final class PortyInsightsBuilder {
  /// Cuántos se muestran como máximo: más que eso ya es una lista de tareas.
  static const max = 3;

  /// Peso desde el que una sola acción se marca como concentración (en una
  /// cartera de al menos dos).
  static const concentrationPct = 25.0;

  /// Distancia (en %) al precio de una alerta para marcarla como cercana.
  static const alertNearPct = 3.0;

  /// Pérdida desde la compra (en %) y peso mínimo para marcarla.
  static const deepLossPct = -20.0;
  static const deepLossMinWeightPct = 5.0;

  /// Avance de una meta desde el que "te falta poco".
  static const goalAlmostFraction = 0.9;

  /// Cambio (en %) desde que el usuario preguntó por algo para marcarlo.
  static const topicMovePct = 5.0;

  static List<PortyInsight> build({
    required PortfolioSummary? summary,
    required DateTime now,
    AllocationRow? drift,
    List<UserGoal> goals = const [],
    Map<String, double> holdings = const {},
    List<PriceAlert> alerts = const [],
    List<TopicPrice> topicPrices = const [],
    Set<String> hidden = const {},
  }) {
    final all = <PortyInsight>[
      if (drift != null) _drift(drift),
      ..._goals(goals, holdings, now),
      if (summary != null) ..._portfolio(summary, alerts),
      if (_topicMoved(topicPrices, now) case final moved?) moved,
    ];
    all.sort((a, b) => b.score.compareTo(a.score));
    return [
      for (final i in all)
        if (!hidden.contains(i.id)) i,
    ].take(max).toList();
  }

  /// El que más se movió desde que el usuario preguntó por él, si pasa
  /// [topicMovePct]. El id lleva la fecha de la pregunta: si vuelve a
  /// preguntar, es otro insight.
  static PortyInsight? _topicMoved(List<TopicPrice> prices, DateTime now) {
    PortyInsight? best;
    for (final (:topic, :price) in prices) {
      final then = topic.priceAt;
      if (then == null || !(then > 0) || !(price > 0)) continue;
      final change = (price - then) / then * 100;
      if (change.abs() < topicMovePct) continue;
      if (best != null && best.numbers['change']!.abs() >= change.abs()) {
        continue;
      }
      final asked = topic.lastAskedAt.toLocal();
      best = PortyInsight(
        kind: PortyInsightKind.topicMoved,
        subject:
            '${topic.ticker}@${asked.year}-${asked.month}-${asked.day}',
        tone: PortyInsightTone.neutral,
        score: 45 + (change.abs() - topicMovePct).clamp(0, 15),
        ticker: topic.ticker,
        numbers: {
          'change': change,
          'days': now.difference(topic.lastAskedAt).inDays.toDouble(),
          'price_then': then,
          'price': price,
        },
      );
    }
    return best;
  }

  static PortyInsight _drift(AllocationRow row) => PortyInsight(
    kind: PortyInsightKind.allocationDrift,
    subject: 'plan',
    tone: PortyInsightTone.attention,
    // Con tope: una meta vencida (90) va siempre antes.
    score: 80 + row.drift.abs().clamp(0, 9),
    ticker: row.ticker,
    numbers: {'current': row.currentPct, 'target': row.targetPct},
  );

  static Iterable<PortyInsight> _goals(
    List<UserGoal> goals,
    Map<String, double> holdings,
    DateTime now,
  ) sync* {
    for (final goal in goals) {
      if (goal.status == GoalStatus.achieved) continue;
      final p = GoalProgress.of(goal, now, holdings: holdings);
      final pct = p.fraction * 100;
      switch (p.status) {
        case GoalProgressStatus.overdue:
          yield PortyInsight(
            kind: PortyInsightKind.goalOverdue,
            subject: goal.id,
            tone: PortyInsightTone.attention,
            score: 90,
            goalLabel: goal.label,
            numbers: {'pct': pct},
          );
        case GoalProgressStatus.behind:
          // Cuánto más por mes, relativo al plan: un atraso chico no le
          // gana a una concentración fuerte.
          final extra =
              p.plannedMonthly <= 0
                  ? 1.0
                  : (p.requiredMonthlyNow - p.plannedMonthly) /
                      p.plannedMonthly;
          yield PortyInsight(
            kind: PortyInsightKind.goalBehind,
            subject: goal.id,
            tone: PortyInsightTone.attention,
            score: 70 + (extra * 20).clamp(0, 15),
            goalLabel: goal.label,
            numbers: {
              'required': p.requiredMonthlyNow,
              'planned': p.plannedMonthly,
            },
          );
        case GoalProgressStatus.onTrack || GoalProgressStatus.ahead
            when p.fraction >= goalAlmostFraction:
          yield PortyInsight(
            kind: PortyInsightKind.goalAlmost,
            subject: goal.id,
            tone: PortyInsightTone.good,
            score: 50,
            goalLabel: goal.label,
            numbers: {'pct': pct, 'left': p.target - p.saved},
          );
        default:
          break;
      }
    }
  }

  static Iterable<PortyInsight> _portfolio(
    PortfolioSummary summary,
    List<PriceAlert> alerts,
  ) sync* {
    final total = summary.totalValue;
    if (!(total > 0)) return;
    final positions = summary.valuations;
    double weightOf(String ticker) =>
        positions
            .where((v) => v.position.ticker.toUpperCase() == ticker)
            .fold(0.0, (s, v) => s + v.marketValue) /
        total *
        100;

    // La más grande, si pesa demasiado (con una sola posición no hay con
    // qué comparar: no es un dato útil).
    if (positions.length >= 2) {
      final biggest = positions.reduce(
        (a, b) => a.marketValue >= b.marketValue ? a : b,
      );
      final weight = biggest.marketValue / total * 100;
      if (weight >= concentrationPct) {
        yield PortyInsight(
          kind: PortyInsightKind.concentration,
          subject: biggest.position.ticker.toUpperCase(),
          tone: PortyInsightTone.neutral,
          score: 60 + (weight - concentrationPct).clamp(0, 20),
          ticker: biggest.position.ticker.toUpperCase(),
          numbers: {'weight': weight},
        );
      }
    }

    // Una alerta de precio (fijo) que está por saltar.
    PortyInsight? nearest;
    for (final alert in alerts) {
      if (alert.status != PriceAlertStatus.active || alert.condition.isPercent) {
        continue;
      }
      final ticker = alert.symbol.toUpperCase();
      final held = positions.where(
        (v) => v.position.ticker.toUpperCase() == ticker,
      );
      if (held.isEmpty || !(alert.target > 0)) continue;
      final price = held.first.currentPrice;
      final crossed =
          alert.condition.isUp ? price >= alert.target : price <= alert.target;
      if (crossed) continue;
      final distance = (alert.target - price).abs() / price * 100;
      if (distance > alertNearPct) continue;
      if (nearest != null && nearest.numbers['distance']! <= distance) {
        continue;
      }
      nearest = PortyInsight(
        kind: PortyInsightKind.alertNear,
        subject: alert.id,
        tone: PortyInsightTone.neutral,
        score: 55 + (alertNearPct - distance) * 3,
        ticker: ticker,
        numbers: {'price': price, 'target': alert.target, 'distance': distance},
      );
    }
    if (nearest != null) yield nearest;

    // La pérdida más fuerte entre las que pesan algo.
    PortyInsight? loss;
    for (final v in positions) {
      final ticker = v.position.ticker.toUpperCase();
      final weight = weightOf(ticker);
      if (v.pnlPercent > deepLossPct || weight < deepLossMinWeightPct) continue;
      if (loss != null && loss.numbers['pnl']! <= v.pnlPercent) continue;
      loss = PortyInsight(
        kind: PortyInsightKind.deepLoss,
        subject: ticker,
        tone: PortyInsightTone.neutral,
        score: 40 + (deepLossPct - v.pnlPercent).clamp(0, 20),
        ticker: ticker,
        numbers: {'pnl': v.pnlPercent, 'weight': weight},
      );
    }
    if (loss != null) yield loss;
  }
}
