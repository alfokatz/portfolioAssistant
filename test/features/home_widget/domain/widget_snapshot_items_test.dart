// Bloque de novedades del snapshot: expires_at, segmentos de resultados,
// textos aprobados (es/en), teaser por plataforma, montos ocultos con
// ítems, ninguna URL en el JSON y el scrub que conserva los ítems.
// Correr: flutter test test/features/home_widget/domain
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/company_news_item.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_day_move.dart';
import 'package:portfolio_assistant/features/home_widget/data/home_widget_store.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_items_selector.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_snapshot.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_snapshot_builder.dart';

import '../home_widget_test_helpers.dart';

final _now = DateTime(2026, 11, 5, 12);

WidgetSnapshot _base(String lang, {bool hidden = false}) =>
    WidgetSnapshotBuilder.ready(
      totalValue: 1000,
      move: PortfolioDayMove(
        absolute: 10,
        percent: 1,
        period: DayMovePeriod.today,
        asOfDay: DateTime(2026, 11, 5),
        topContributor: const TopContributor(ticker: 'AAA', amount: 8),
      ),
      amountsHidden: hidden,
      lang: lang,
      now: _now,
      dataAsOf: _now,
      texts: realTexts(lang),
    );

WidgetItemsSelection _selection({
  List<SelectedWidgetItem> items = const [],
  SelectedTeaser? teaser,
  bool section = true,
}) => WidgetItemsSelection(items: items, teaser: teaser, itemsSection: section);

SelectedNews _news({DateTime? at}) => SelectedNews(
  'AAA',
  CompanyNewsItem(
    ticker: 'AAA',
    headline: 'AAA abre una planta',
    summary: '',
    url: 'https://example.com/secret-path?x=1',
    source: 'Fuente Ejemplo',
    publishedAt: at ?? _now.subtract(const Duration(hours: 3)),
  ),
);

WidgetSnapshot _build(
  String lang,
  WidgetItemsSelection selection, {
  bool hidden = false,
  WidgetPlatform platform = WidgetPlatform.android,
}) => WidgetSnapshotBuilder.withItems(
  base: _base(lang, hidden: hidden),
  selection: selection,
  now: _now,
  checkedAt: _now,
  texts: realTexts(lang),
  platform: platform,
);

Map<String, Object?> _json(WidgetSnapshot s) =>
    jsonDecode(jsonEncode(s.toJson())) as Map<String, Object?>;

void main() {
  group('news item', () {
    test('expires 48 h after publishing and keeps the headline as is', () {
      final at = _now.subtract(const Duration(hours: 3));
      final json = _json(_build('es', _selection(items: [_news(at: at)])));
      final item = (json['items']! as List).single as Map;
      expect(item['kind'], 'news');
      expect(item['headline'], 'AAA abre una planta');
      expect(item['source'], 'Fuente Ejemplo');
      expect(
        item['expires_at'],
        at.add(const Duration(hours: 48)).toUtc().millisecondsSinceEpoch,
      );
      expect(item['id'], matches(RegExp(r'^[0-9a-f]{8}$')));
    });

    test('no url anywhere in the JSON', () {
      final text = jsonEncode(_build('es', _selection(items: [_news()])).toJson());
      expect(text, isNot(contains('http')));
      expect(text, isNot(contains('secret-path')));
      expect(text, isNot(contains('"url"')));
    });
  });

  group('earnings item', () {
    SelectedEarnings at(DateTime d) => SelectedEarnings('AAA', d);

    test('expires at the end of the local day', () {
      final json = _json(
        _build('es', _selection(items: [at(DateTime(2026, 11, 7))])),
      );
      final item = (json['items']! as List).single as Map;
      expect(
        item['expires_at'],
        DateTime(2026, 11, 7, 23, 59, 59).toUtc().millisecondsSinceEpoch,
      );
    });

    test('expiry follows the local day across a DST change', () {
      expect(
        WidgetSnapshotBuilder.earningsExpiry(DateTime(2026, 3, 29)),
        DateTime(2026, 3, 29, 23, 59, 59),
      );
    });

    test('segments: date, tomorrow, today', () {
      final segments = WidgetSnapshotBuilder.earningsSegments(
        ticker: 'AAA',
        date: DateTime(2026, 11, 9),
        now: _now,
        texts: realTexts('es'),
      );
      expect([for (final s in segments) s.text], [
        'AAA · fecha estimada de resultados: lun 9 nov',
        'AAA · fecha estimada de resultados: mañana',
        'AAA · fecha estimada de resultados: hoy',
      ]);
      expect(segments[0].from, _now);
      expect(segments[1].from, DateTime(2026, 11, 8));
      expect(segments[2].from, DateTime(2026, 11, 9));
    });

    test('segments for tomorrow and for today', () {
      final tomorrow = WidgetSnapshotBuilder.earningsSegments(
        ticker: 'AAA',
        date: DateTime(2026, 11, 6),
        now: _now,
        texts: realTexts('en'),
      );
      expect([for (final s in tomorrow) s.text], [
        'AAA · estimated earnings date: tomorrow',
        'AAA · estimated earnings date: today',
      ]);
      final today = WidgetSnapshotBuilder.earningsSegments(
        ticker: 'AAA',
        date: DateTime(2026, 11, 5),
        now: _now,
        texts: realTexts('en'),
      );
      expect(today.single.text, 'AAA · estimated earnings date: today');
    });

    test('never says confirmed: every text says estimated', () {
      for (final lang in ['es', 'en']) {
        final json = _json(
          _build(lang, _selection(items: [at(DateTime(2026, 11, 8))])),
        );
        final item = (json['items']! as List).single as Map;
        final texts = [
          for (final s in item['segments'] as List) (s as Map)['text'] as String,
          item['a11y'] as String,
        ];
        for (final t in texts) {
          expect(t.toLowerCase(), contains(lang == 'es' ? 'estimad' : 'estimated'));
        }
      }
    });

    test('long date in english', () {
      expect(
        WidgetSnapshotBuilder.dateLabel(realTexts('en'), DateTime(2026, 11, 5)),
        'Thu, Nov 5',
      );
    });
  });

  group('approved texts', () {
    String teaser(
      String lang,
      WidgetPlatform p,
      SelectedTeaser t,
    ) => _build(lang, _selection(teaser: t), platform: p).teaser!.text;

    test('android free, es and en', () {
      const none = SelectedTeaser(kind: 'news');
      expect(
        teaser('es', WidgetPlatform.android, none),
        'Noticias de tu cartera · Premium',
      );
      expect(
        teaser('en', WidgetPlatform.android, none),
        'News on your holdings · Premium',
      );
      expect(
        teaser('es', WidgetPlatform.android, const SelectedTeaser(kind: 'news', count: 2)),
        'Hay 2 noticias de tu cartera · Premium',
      );
      expect(
        teaser('es', WidgetPlatform.android, const SelectedTeaser(kind: 'news', count: 1)),
        'Hay 1 noticia de tu cartera · Premium',
      );
      expect(
        teaser('en', WidgetPlatform.android, const SelectedTeaser(kind: 'news', count: 2)),
        '2 news stories on your holdings · Premium',
      );
      expect(
        teaser('en', WidgetPlatform.android, const SelectedTeaser(kind: 'news', count: 1)),
        '1 news story on your holdings · Premium',
      );
    });

    test('android premium earnings', () {
      expect(
        teaser('es', WidgetPlatform.android, const SelectedTeaser(kind: 'earnings', count: 1)),
        'Una acción de tu cartera tiene resultados estimados esta semana · Gold',
      );
      expect(
        teaser('es', WidgetPlatform.android, const SelectedTeaser(kind: 'earnings', count: 2)),
        '2 acciones de tu cartera tienen resultados estimados esta semana · Gold',
      );
      expect(
        teaser('en', WidgetPlatform.android, const SelectedTeaser(kind: 'earnings', count: 1)),
        'One of your holdings has an estimated earnings date this week · Gold',
      );
      expect(
        teaser('en', WidgetPlatform.android, const SelectedTeaser(kind: 'earnings', count: 2)),
        '2 of your holdings have estimated earnings dates this week · Gold',
      );
    });

    test('ios: neutral, no plan name', () {
      expect(
        teaser('es', WidgetPlatform.ios, const SelectedTeaser(kind: 'news', count: 2)),
        'Hay 2 noticias de tu cartera en Porty',
      );
      expect(
        teaser('es', WidgetPlatform.ios, const SelectedTeaser(kind: 'news', count: 1)),
        'Hay 1 noticia de tu cartera en Porty',
      );
      expect(
        teaser('en', WidgetPlatform.ios, const SelectedTeaser(kind: 'news', count: 2)),
        '2 news stories on your holdings in Porty',
      );
      expect(
        teaser('es', WidgetPlatform.ios, const SelectedTeaser(kind: 'earnings', count: 1)),
        'Una acción de tu cartera tiene resultados estimados esta semana',
      );
      for (final lang in ['es', 'en']) {
        for (final kind in ['news', 'earnings']) {
          final text = teaser(
            lang,
            WidgetPlatform.ios,
            SelectedTeaser(kind: kind, count: 2),
          );
          expect(text, isNot(contains('Premium')));
          expect(text, isNot(contains('Gold')));
        }
      }
    });

    test('labels and the settings note', () {
      final es = _build('es', _selection()).itemsLabels!;
      expect(es['section'], 'Novedades de tu cartera');
      expect(
        es['empty'],
        'No encontramos novedades de tu cartera en las últimas 48 h',
      );
      expect(es['all_expired'], 'Abrí Porty para ver las novedades de tu cartera');
      expect(es['redacted'], 'Desbloqueá tu iPhone para ver las novedades');
      final en = _build('en', _selection()).itemsLabels!;
      expect(en['section'], 'Your holdings news');
      expect(en['redacted'], 'Unlock your iPhone to see the news');
      expect(
        realTexts('es').get('privacy_note'),
        'Oculta solo los montos. Las noticias y los resultados del widget siguen mostrando tus tickers. El widget guarda un resumen de tu cartera en este teléfono. Se borra al cerrar sesión.',
      );
    });

    test('sheet texts', () {
      final es = realTexts('es');
      expect(es.get('sheet_legend'), contains('Titulares vía GDELT Project.'));
      expect(es.get('locked_premium'), 'Esto viene con Premium');
      expect(es.get('locked_gold'), 'Esto viene con Gold');
      expect(
        es.get('question_earnings_when', {'ticker': 'AAA'}),
        '¿Cuándo se espera que AAA presente resultados y qué presentó la última vez?',
      );
      final en = realTexts('en');
      expect(en.get('sheet_legend'), contains('Headlines via GDELT Project.'));
      expect(en.get('question_news_why', {'ticker': 'AAA'}), 'What happened with AAA?');
    });
  });

  group('hidden amounts', () {
    test('no amounts but the items stay', () {
      final snap = _build('es', _selection(items: [_news()]), hidden: true);
      final json = _json(snap);
      expect(json.containsKey('total_text'), isFalse);
      expect(json.containsKey('change_text'), isFalse);
      expect((json['items']! as List), hasLength(1));
      expect(snap.items.single.ticker, 'AAA');
    });

    test('scrubAmountsFromSnapshotJson keeps items, teaser and items_*', () {
      final json = _json(
        _build(
          'es',
          _selection(
            items: [_news()],
            teaser: const SelectedTeaser(kind: 'news', count: 2),
          ),
        ),
      );
      final scrubbed = scrubAmountsFromSnapshotJson(json)!;
      expect(scrubbed['amounts_hidden'], isTrue);
      expect(scrubbed.containsKey('total_text'), isFalse);
      expect(scrubbed.containsKey('phrase'), isFalse);
      expect(scrubbed['items'], json['items']);
      expect(scrubbed['teaser'], json['teaser']);
      expect(scrubbed['items_section'], true);
      expect(scrubbed['items_labels'], json['items_labels']);
      expect(scrubbed['items_checked_at'], json['items_checked_at']);
    });
  });

  group('section flag', () {
    test('without section: false, no items, no labels', () {
      final json = _json(_build('es', _selection(section: false)));
      expect(json['items_section'], false);
      expect(json['items'], isEmpty);
      expect(json.containsKey('items_labels'), isFalse);
      expect(json['teaser'], isNull);
    });

    test('non-ready states never carry the block', () {
      final out = WidgetSnapshotBuilder.withItems(
        base: WidgetSnapshotBuilder.signedOut(
          lang: 'es',
          now: _now,
          texts: realTexts('es'),
        ),
        selection: _selection(items: [_news()]),
        now: _now,
        checkedAt: _now,
        texts: realTexts('es'),
        platform: WidgetPlatform.ios,
      );
      expect(_json(out).containsKey('items'), isFalse);
    });

    test('a v1 snapshot has none of the new fields', () {
      final json = _json(_base('es'));
      for (final k in [
        'items_section',
        'items_checked_at',
        'plan_until',
        'items',
        'teaser',
        'items_labels',
      ]) {
        expect(json.containsKey(k), isFalse, reason: k);
      }
    });
  });
}
