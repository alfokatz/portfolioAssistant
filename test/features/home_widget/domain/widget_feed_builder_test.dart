// Candidatos, prioridades y orden base del feed v2 (spec §4.1–4.2).
// Correr: flutter test test/features/home_widget/domain/widget_feed_builder_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_day_move.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_feed_builder.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_insight_copy.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_items_selector.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_portfolio_facts.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_snapshot.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_texts.dart';

import '../home_widget_test_helpers.dart';

final _now = DateTime(2026, 11, 6, 12);

WidgetFeedInputs _inputs({
  WidgetItemsSelection? selection,
  List<WidgetInsightInput> insights = const [],
  WidgetMoverFact? mover,
  WidgetBiggestFact? biggest,
}) => WidgetFeedInputs(
  tier: SubscriptionTier.gold,
  now: _now,
  staleAt: _now.add(const Duration(hours: 24)),
  period: DayMovePeriod.today,
  platform: WidgetPlatform.ios,
  selection: selection,
  insights: insights,
  mover: mover,
  biggest: biggest,
);

WidgetItemsSelection _earnings(String ticker, DateTime date) =>
    WidgetItemsSelection(
      items: [SelectedEarnings(ticker, date)],
      teaser: null,
      itemsSection: true,
    );

const _drift = WidgetInsightInput(
  id: 'drift:GOOGL',
  kind: WidgetInsightKind.allocationDrift,
  score: 60,
  ticker: 'GOOGL',
  numbers: {'current': 0, 'target': 25},
);

const _concentration = WidgetInsightInput(
  id: 'concentration:VOO',
  kind: WidgetInsightKind.concentration,
  score: 50,
  ticker: 'VOO',
  numbers: {'weight': 50},
);

void main() {
  late WidgetTexts t;
  setUpAll(() async => t = await loadRealTexts('es'));

  test('order: dated (prio 1) before insights (2) before context (3)', () {
    final build = WidgetFeedBuilder.build(
      _inputs(
        selection: _earnings('NVDA', DateTime(2026, 11, 7)),
        insights: const [_drift],
        mover: const WidgetMoverFact(ticker: 'MSFT', pct: -2.1),
        biggest: const WidgetBiggestFact(ticker: 'VOO', weightPct: 50),
      ),
      t,
    );
    expect(
      [for (final i in build.items) i.kind],
      [
        WidgetFeedKind.earnings,
        WidgetFeedKind.insight,
        WidgetFeedKind.mover,
        WidgetFeedKind.biggest,
      ],
    );
    expect([for (final i in build.items) i.prioAt(_now)], [1, 2, 3, 3]);
    // Cada ítem con pregunta la tiene en drafts, por id.
    for (final item in build.items) {
      expect(item.id, isNotNull);
    }
    expect(build.drafts.keys, contains(build.items.first.id));
  });

  test('earnings far away start as context and become dated 2 days before', () {
    final build = WidgetFeedBuilder.build(
      _inputs(selection: _earnings('NVDA', DateTime(2026, 11, 12))),
      t,
    );
    final item = build.items.single;
    expect(item.prioAt(_now), 3);
    expect(item.prioAt(DateTime(2026, 11, 10, 9)), 1);
    expect(item.prioAt(DateTime(2026, 11, 12, 9)), 1);
  });

  test('biggest is skipped when a concentration insight already says it', () {
    final build = WidgetFeedBuilder.build(
      _inputs(
        insights: const [_concentration],
        biggest: const WidgetBiggestFact(ticker: 'VOO', weightPct: 50),
      ),
      t,
    );
    expect(
      build.items.where((i) => i.kind == WidgetFeedKind.biggest),
      isEmpty,
    );
  });

  test('biggest is skipped when it is the same ticker as the mover', () {
    final build = WidgetFeedBuilder.build(
      _inputs(
        mover: const WidgetMoverFact(ticker: 'voo', pct: 1.5),
        biggest: const WidgetBiggestFact(ticker: 'VOO', weightPct: 50),
      ),
      t,
    );
    expect([for (final i in build.items) i.kind], [WidgetFeedKind.mover]);
  });

  test('nothing to say: empty feed (the widget falls back to the chart)', () {
    final build = WidgetFeedBuilder.build(_inputs(), t);
    expect(build.items, isEmpty);
    expect(build.drafts, isEmpty);
  });

  test('ids are stable between builds', () {
    WidgetFeedBuild once() => WidgetFeedBuilder.build(
      _inputs(
        insights: const [_drift],
        mover: const WidgetMoverFact(ticker: 'MSFT', pct: -2.1),
      ),
      t,
    );
    expect(
      [for (final i in once().items) i.id],
      [for (final i in once().items) i.id],
    );
  });
}
