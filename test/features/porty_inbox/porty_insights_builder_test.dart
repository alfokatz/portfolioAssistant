// Lo que Porty marca en la Home: cuándo aparece cada insight, cómo se
// ordenan, el tope, lo oculto y que lo oculto vuelve a la semana.
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/investor_profile.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/position_valuation.dart';
import 'package:portfolio_assistant/features/allocation/domain/allocation_plan.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/savings_plan_calculator.dart';
import 'package:portfolio_assistant/features/assistant/models/porty_screen_context.dart';
import 'package:portfolio_assistant/features/goals/domain/user_goal.dart';
import 'package:portfolio_assistant/features/notifications/domain/price_alert.dart';
import 'package:portfolio_assistant/features/porty_memory/domain/porty_topic.dart';
import 'package:portfolio_assistant/features/porty_inbox/domain/porty_insight.dart';
import 'package:portfolio_assistant/features/porty_inbox/domain/porty_insights_builder.dart';
import 'package:portfolio_assistant/features/porty_inbox/providers/porty_inbox_provider.dart';

/// Cartera con [values] por ticker (compradas a 100, valen 150 salvo que
/// [pnl] diga otra cosa).
PortfolioSummary _summary(
  Map<String, double> values, {
  Map<String, double> pnl = const {},
}) {
  final vals = [
    for (final MapEntry(key: t, value: v) in values.entries)
      PositionValuation(
        position: Position(
          id: t,
          ticker: t,
          quantity: v / 150,
          purchasePrice: 100,
          purchaseDate: DateTime(2024, 1, 1),
        ),
        currentPrice: 150,
        marketValue: v,
        pnlAbsolute: 0,
        pnlPercent: pnl[t] ?? 50,
      ),
  ];
  final total = values.values.fold(0.0, (a, b) => a + b);
  return PortfolioSummary(
    totalValue: total,
    totalCostBasis: total,
    totalPnlAbsolute: 0,
    totalPnlPercent: 0,
    valuations: vals,
  );
}

/// Una meta de 1.200 en 12 meses desde el 1/1/2026 (como en goals_test).
UserGoal _goal({String id = 'g1', String label = 'MacBook', double outside = 0}) {
  final inputs = SavingsPlanInputs(
    targetAmount: 1200,
    months: 12,
    currentAmount: 0,
    risk: RiskTolerance.moderate,
    startDate: DateTime(2026, 1, 1),
    shortTerm: true,
  );
  return UserGoal(
    id: id,
    label: label,
    type: GoalType.purchase,
    targetAmount: 1200,
    targetDate: DateTime(2027, 1, 1),
    snapshot: GoalPlanSnapshot(inputs: inputs),
    status: GoalStatus.active,
    createdAt: DateTime(2026, 1, 1),
    externalSavings: outside,
  );
}

PriceAlert _alert(String symbol, double target, {bool up = true}) => PriceAlert(
  id: 'alert-$symbol',
  symbol: symbol,
  condition: up ? PriceAlertCondition.above : PriceAlertCondition.below,
  target: target,
  status: PriceAlertStatus.active,
  createdAt: DateTime(2026, 1, 1),
);

final _now = DateTime(2026, 7, 2);

List<PortyInsightKind> _kinds(List<PortyInsight> list) => [
  for (final i in list) i.kind,
];

void main() {
  group('PortyInsightsBuilder', () {
    test('a balanced portfolio with nothing going on: nothing to mark', () {
      final out = PortyInsightsBuilder.build(
        summary: _summary({'A': 200, 'B': 200, 'C': 200, 'D': 200, 'E': 200}),
        now: _now,
      );
      expect(out, isEmpty);
    });

    test('concentration: the biggest position from 25%, never with a single '
        'position', () {
      final out = PortyInsightsBuilder.build(
        summary: _summary({'NVDA': 600, 'AAPL': 400}),
        now: _now,
      );
      expect(_kinds(out), [PortyInsightKind.concentration]);
      expect(out.single.ticker, 'NVDA');
      expect(out.single.numbers['weight'], closeTo(60, 0.01));
      expect(out.single.screen!.screen, PortyScreen.positionDetail);
      expect(out.single.screen!.ticker, 'NVDA');

      expect(
        PortyInsightsBuilder.build(summary: _summary({'NVDA': 600}), now: _now),
        isEmpty,
      );
    });

    test('a price alert within 3% that has not jumped yet; the closest one',
        () {
      // Valen 150 por acción.
      final out = PortyInsightsBuilder.build(
        summary: _summary({'A': 200, 'B': 200, 'C': 200, 'D': 200, 'E': 200}),
        now: _now,
        alerts: [
          _alert('A', 154), // 2,7 %
          _alert('B', 151), // 0,7 %
          _alert('C', 160), // 6,7 %: lejos
          _alert('D', 140), // ya pasó (por arriba)
          _alert('E', 148, up: false), // 1,3 % por abajo
        ],
      );
      expect(_kinds(out), [PortyInsightKind.alertNear]);
      expect(out.single.ticker, 'B');
      expect(out.single.numbers['target'], 151);
    });

    test('a deep loss only if it weighs something; the worst one', () {
      final out = PortyInsightsBuilder.build(
        summary: _summary(
          {'A': 200, 'B': 200, 'C': 200, 'D': 200, 'E': 200, 'TINY': 20},
          pnl: {'A': -25, 'B': -40, 'TINY': -80},
        ),
        now: _now,
      );
      expect(_kinds(out), [PortyInsightKind.deepLoss]);
      expect(out.single.ticker, 'B');
    });

    test('goals: behind and almost there, with their label and screen', () {
      final out = PortyInsightsBuilder.build(
        summary: null,
        now: DateTime(2026, 11, 2),
        goals: [
          _goal(id: 'late', label: 'Viaje'),
          _goal(id: 'near', label: 'MacBook', outside: 1100),
        ],
      );
      expect(_kinds(out), [
        PortyInsightKind.goalBehind,
        PortyInsightKind.goalAlmost,
      ]);
      expect(out.first.goalLabel, 'Viaje');
      expect(out.first.numbers['required']!, greaterThan(out.first.numbers['planned']!));
      expect(out.first.screen!.screen, PortyScreen.goalDetail);
      expect(out.first.screen!.goalLabel, 'Viaje');
      expect(out.last.tone, PortyInsightTone.good);
    });

    test('an overdue goal goes first, then the plan drift, then the rest; '
        'never more than 3', () {
      final out = PortyInsightsBuilder.build(
        summary: _summary({'NVDA': 700, 'AAPL': 300}, pnl: {'AAPL': -30}),
        now: DateTime(2027, 2, 1),
        drift: const AllocationRow(
          ticker: 'NVDA',
          value: 700,
          currentPct: 70,
          targetPct: 50,
        ),
        goals: [_goal(outside: 300)],
        alerts: [_alert('NVDA', 152)],
      );
      expect(out, hasLength(PortyInsightsBuilder.max));
      expect(_kinds(out), [
        PortyInsightKind.goalOverdue,
        PortyInsightKind.allocationDrift,
        PortyInsightKind.concentration,
      ]);
    });

    test('what the user hid does not show, and the next one takes its place',
        () {
      final summary = _summary({'NVDA': 700, 'AAPL': 300}, pnl: {'AAPL': -30});
      final all = PortyInsightsBuilder.build(summary: summary, now: _now);
      expect(_kinds(all), [
        PortyInsightKind.concentration,
        PortyInsightKind.deepLoss,
      ]);
      final hidden = PortyInsightsBuilder.build(
        summary: summary,
        now: _now,
        hidden: {all.first.id},
      );
      expect(_kinds(hidden), [PortyInsightKind.deepLoss]);
    });
  });

  group('topicMoved (porty_topics)', () {
    PortyTopic topic(String t, double? then, {int daysAgo = 10}) => PortyTopic(
      ticker: t,
      question: '¿Qué pasa con $t?',
      lastAskedAt: _now.subtract(Duration(days: daysAgo)),
      priceAt: then,
    );

    test('what moved 5% or more since they asked; the biggest move; no '
        'screen (the question names the ticker)', () {
      final out = PortyInsightsBuilder.build(
        summary: null,
        now: _now,
        topicPrices: [
          (topic: topic('AMZN', 200), price: 184), // −8 %
          (topic: topic('KO', 70), price: 71), // +1,4 %: no
          (topic: topic('MELI', 2000), price: 2200), // +10 %
        ],
      );
      expect(_kinds(out), [PortyInsightKind.topicMoved]);
      expect(out.single.ticker, 'MELI');
      expect(out.single.numbers['change'], closeTo(10, 0.001));
      expect(out.single.numbers['days'], 10);
      expect(out.single.screen, isNull);
    });

    test('asking again makes it a new insight (the id carries the date)', () {
      PortyInsight build(int daysAgo) =>
          PortyInsightsBuilder.build(
            summary: null,
            now: _now,
            topicPrices: [
              (topic: topic('AMZN', 200, daysAgo: daysAgo), price: 180),
            ],
          ).single;
      expect(build(10).id, isNot(build(3).id));
      expect(build(10).id, startsWith('topicMoved:AMZN@'));
    });

    test('without the price of that day, nothing', () {
      expect(
        PortyInsightsBuilder.build(
          summary: null,
          now: _now,
          topicPrices: [(topic: topic('AMZN', null), price: 180)],
        ),
        isEmpty,
      );
    });
  });

  group('PortyInboxHiddenNotifier', () {
    test('hidden for a week, then it can come back', () async {
      var now = DateTime(2026, 7, 2, 9);
      final notifier = PortyInboxHiddenNotifier(null, now: () => now);
      await notifier.hide('concentration:NVDA');
      expect(notifier.activeIds, {'concentration:NVDA'});

      now = now.add(const Duration(days: 6));
      expect(notifier.activeIds, {'concentration:NVDA'});
      now = now.add(const Duration(days: 2));
      expect(notifier.activeIds, isEmpty);
    });
  });
}
