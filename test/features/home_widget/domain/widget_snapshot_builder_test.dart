// Snapshot v2: bloque v1 sin montos ni tickers, mood, y posiciones ocultas
// sin ningún dato de la cartera en el JSON.
// Correr: flutter test test/features/home_widget/domain/widget_snapshot_builder_test.dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/company_news_item.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_day_move.dart';
import 'package:portfolio_assistant/features/home_widget/data/home_widget_store.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_insight_copy.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_items_selector.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_portfolio_facts.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_snapshot_builder.dart';

import '../home_widget_test_helpers.dart';

final _now = DateTime.utc(2026, 11, 6, 15);

PortfolioDayMove _move(double pct) => PortfolioDayMove(
  absolute: 123.45,
  percent: pct,
  period: DayMovePeriod.today,
  asOfDay: DateTime(2026, 11, 6),
  topContributor: const TopContributor(ticker: 'ACME', amount: 80),
);

const _holdings = [
  WidgetHolding(ticker: 'ACME', marketValue: 5000),
  WidgetHolding(ticker: 'GLOBX', marketValue: 4000),
];

Map<String, Object?> _build({
  bool hidden = false,
  double pct = 1.2,
  SubscriptionTier tier = SubscriptionTier.gold,
}) {
  final selection = WidgetItemsSelector.select(
    holdings: _holdings,
    news: [
      CompanyNewsItem(
        ticker: 'ACME',
        headline: 'Titular secreto de ACME',
        summary: '',
        url: 'https://example.com/acme',
        source: 'Fuente Ejemplo',
        publishedAt: _now.subtract(const Duration(hours: 2)),
      ),
    ],
    earnings: [(ticker: 'GLOBX', date: DateTime(2026, 11, 7))],
    tier: tier,
    teasersEnabled: false,
    platform: WidgetPlatform.android,
    now: _now,
    cap: WidgetItemsSelector.maxItemsV2,
  );
  final snapshot = WidgetSnapshotBuilder.ready(
    move: _move(pct),
    positionsHidden: hidden,
    lang: 'es',
    now: _now,
    dataAsOf: _now,
    texts: realTexts('es'),
    tier: tier,
    selection: selection,
    insights: const [
      WidgetInsightInput(
        id: 'goalBehind:g1',
        kind: WidgetInsightKind.goalBehind,
        score: 80,
        goalLabel: 'Meta secreta',
      ),
    ],
    mover: const WidgetMoverFact(ticker: 'GLOBX', pct: 4.1),
    biggest: const WidgetBiggestFact(ticker: 'ACME', weightPct: 55),
  );
  return jsonDecode(jsonEncode(snapshot.toJson())) as Map<String, Object?>;
}

void main() {
  group('WidgetSnapshotBuilder.ready', () {
    test('v1 block has no amounts, no total, no questions, no ticker', () {
      final json = _build();
      expect(json['v'], 1);
      expect(json['amounts_hidden'], true);
      for (final key in [
        'total_text',
        'change_text',
        'questions',
        'items',
        'items_section',
        'teaser',
        'plan_until',
      ]) {
        expect(json.containsKey(key), isFalse, reason: key);
      }
      expect(json['phrase'], 'Tu cartera sube hoy.');
      expect(json['v2'], isA<Map>());
    });

    test('no currency amount in any string of the JSON', () {
      final text = jsonEncode(_build());
      expect(RegExp(r'[$€]|US\$|USD\s?\d').hasMatch(text), isFalse);
    });

    test('mood follows the direction', () {
      expect((_build(pct: 1.2)['v2']! as Map)['mood'], 'happy');
      expect((_build(pct: -1.2)['v2']! as Map)['mood'], 'concerned');
      expect((_build(pct: 0.1)['v2']! as Map)['mood'], 'neutral');
    });

    test('positions hidden: no ticker, headline, source or goal anywhere', () {
      final text = jsonEncode(_build(hidden: true));
      for (final secret in [
        'ACME',
        'GLOBX',
        'Titular secreto',
        'Fuente Ejemplo',
        'Meta secreta',
      ]) {
        expect(text, isNot(contains(secret)), reason: secret);
      }
      final v2 = _build(hidden: true)['v2']! as Map;
      expect(v2['positions_hidden'], true);
      expect(v2.containsKey('feed_rev'), isFalse);
      for (final item in v2['feed'] as List) {
        expect((item as Map).keys.toSet().difference({
          'kind',
          'icon',
          'paid',
          'expires_at',
          'segments',
        }), isEmpty);
      }
    });

    test('visible positions: feed has ids, a feed_rev and a head question', () {
      final v2 = _build()['v2']! as Map;
      expect(v2['feed_rev'], matches(RegExp(r'^[0-9a-f]{8}$')));
      final feed = v2['feed'] as List;
      expect((feed.first as Map)['kind'], 'earnings');
      expect(((v2['questions']! as Map)['large']! as List), isNotEmpty);
    });

    test('Free never gets news or earnings', () {
      final feed = (_build(tier: SubscriptionTier.free)['v2']! as Map)['feed'] as List;
      final kinds = {for (final i in feed) (i as Map)['kind']};
      expect(kinds, isNot(contains('news')));
      expect(kinds, isNot(contains('earnings')));
    });
  });

  group('scrubPositionsFromSnapshotJson', () {
    test('turns a visible v2 snapshot into the hidden form', () {
      final scrubbed = scrubPositionsFromSnapshotJson(_build())!;
      final text = jsonEncode(scrubbed);
      for (final secret in ['ACME', 'GLOBX', 'Titular secreto', 'Meta secreta']) {
        expect(text, isNot(contains(secret)));
      }
      expect((scrubbed['v2']! as Map)['positions_hidden'], true);
    });

    test('legacy or non-ready JSON: nothing to scrub', () {
      expect(scrubPositionsFromSnapshotJson({'state': 'ready'}), isNull);
      expect(scrubPositionsFromSnapshotJson({'state': 'signed_out'}), isNull);
    });
  });
}
