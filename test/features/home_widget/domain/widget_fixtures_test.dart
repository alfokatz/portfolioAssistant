// Los JSON de test/fixtures/home_widget/ (datos de prueba del widget
// nativo) tienen que ser exactamente lo que arma el builder. Para
// regenerarlos: UPDATE_WIDGET_FIXTURES=1 flutter test <este archivo>
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/company_news_item.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_day_move.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_items_selector.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_snapshot.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_snapshot_builder.dart';

import '../home_widget_test_helpers.dart';

// Datos ficticios, fijos (no una cartera real).
final _now = DateTime.utc(2026, 11, 5, 15, 5);
final _asOf = DateTime.utc(2026, 11, 5, 15);

PortfolioDayMove _move(
  DayMovePeriod p, {
  double abs = 123.45,
  double pct = 1.0,
}) => PortfolioDayMove(
  absolute: abs,
  percent: pct,
  period: p,
  asOfDay: DateTime(2026, 11, 5),
  topContributor: const TopContributor(ticker: 'NVDA', amount: 80),
);

WidgetSnapshot _ready(
  String lang, {
  bool hidden = false,
  DayMovePeriod period = DayMovePeriod.today,
  double abs = 123.45,
  double pct = 1.0,
}) => WidgetSnapshotBuilder.ready(
  totalValue: 12345.67,
  move: _move(period, abs: abs, pct: pct),
  amountsHidden: hidden,
  lang: lang,
  now: _now,
  dataAsOf: _asOf,
  texts: realTexts(lang),
);

// Cartera ficticia para los fixtures de novedades (tickers inventados).
const _holdings = [
  WidgetHolding(ticker: 'ACME', marketValue: 5000),
  WidgetHolding(ticker: 'GLOBX', marketValue: 4000),
  WidgetHolding(ticker: 'NOVA', marketValue: 3000),
  WidgetHolding(ticker: 'ZETA', marketValue: 2000),
  WidgetHolding(ticker: 'ORBT', marketValue: 1000),
];

CompanyNewsItem _news(String ticker, String headline, Duration age) =>
    CompanyNewsItem(
      ticker: ticker,
      headline: headline,
      summary: '',
      url: 'https://example.com/${ticker.toLowerCase()}',
      source: 'Fuente Ejemplo',
      publishedAt: _now.subtract(age),
    );

WidgetSnapshot _withItems(
  String lang, {
  SubscriptionTier tier = SubscriptionTier.gold,
  bool hidden = false,
  WidgetPlatform platform = WidgetPlatform.android,
  bool teasers = false,
  WidgetTeaserCounts? counts,
  Duration newsAge = const Duration(hours: 3),
  DateTime? planUntil,
}) {
  final texts = realTexts(lang);
  final selection = WidgetItemsSelector.select(
    holdings: _holdings,
    news: [
      _news('ACME', 'ACME presenta una nueva línea de productos', newsAge),
      _news('GLOBX', 'GLOBX abre una planta en otro país', newsAge * 2),
      _news('NOVA', 'NOVA cierra un acuerdo de distribución', newsAge * 3),
    ],
    earnings: [(ticker: 'ZETA', date: DateTime(2026, 11, 6))],
    tier: tier,
    teasersEnabled: teasers,
    teaserCounts: counts,
    platform: platform,
    now: _now,
  );
  return WidgetSnapshotBuilder.withItems(
    base: _ready(lang, hidden: hidden),
    selection: selection,
    now: _now,
    checkedAt: _now,
    texts: texts,
    platform: platform,
    planUntil: planUntil,
  );
}

void main() {
  final fixtures = <String, WidgetSnapshot>{
    'ready_v1_legacy': _ready('es'),
    'ready_items_es': _withItems('es'),
    'ready_items_en': _withItems('en'),
    'ready_items_hidden': _withItems('es', hidden: true),
    'ready_items_expired': _withItems(
      'es',
      newsAge: const Duration(hours: 15, minutes: 30),
      planUntil: _now.add(const Duration(hours: 20)),
    ),
    'ready_teaser_android': _withItems(
      'es',
      tier: SubscriptionTier.free,
      teasers: true,
    ),
    'ready_teaser_ios': _withItems(
      'es',
      tier: SubscriptionTier.premium,
      platform: WidgetPlatform.ios,
      teasers: true,
      counts: const WidgetTeaserCounts(earnings7: 1),
    ),
    'ready_es': _ready('es'),
    'ready_en': _ready('en', abs: -50.2, pct: -0.4),
    'ready_hidden_es': _ready('es', hidden: true),
    'last_close_es': _ready('es', period: DayMovePeriod.lastClose),
    'signed_out_es': WidgetSnapshotBuilder.signedOut(
      lang: 'es',
      now: _now,
      texts: realTexts('es'),
    ),
    'signed_out_en': WidgetSnapshotBuilder.signedOut(
      lang: 'en',
      now: _now,
      texts: realTexts('en'),
    ),
    'no_portfolio_es': WidgetSnapshotBuilder.noPortfolio(
      lang: 'es',
      now: _now,
      texts: realTexts('es'),
    ),
  };
  final update = Platform.environment['UPDATE_WIDGET_FIXTURES'] == '1';

  group('home widget fixtures', () {
    fixtures.forEach((name, snapshot) {
      test('$name.json matches the builder', () {
        final file = File('test/fixtures/home_widget/$name.json');
        final text =
            '${const JsonEncoder.withIndent('  ').convert(snapshot.toJson())}\n';
        if (update) file.writeAsStringSync(text);
        expect(file.existsSync(), isTrue);
        // `stale_at` y `stale_date` dependen de la zona horaria de quien
        // corre el test (medianoche local): se comparan sin ellos.
        Map<String, Object?> load(String raw) {
          final json = jsonDecode(raw) as Map<String, Object?>;
          json.remove('stale_at');
          (json['labels'] as Map?)?.remove('stale_date');
          // Los cortes de resultados son medianoche local.
          for (final item in (json['items'] as List? ?? const [])) {
            if (item is! Map || item['kind'] != 'earnings') continue;
            item.remove('expires_at');
            for (final seg in item['segments'] as List) {
              (seg as Map).remove('from');
            }
          }
          return json;
        }

        expect(load(file.readAsStringSync()), load(text));
      });
    });
  });
}
