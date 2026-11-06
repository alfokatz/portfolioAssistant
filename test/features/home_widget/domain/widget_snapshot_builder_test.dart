// WidgetSnapshotBuilder: cada estado, stale_at, montos ocultos y a11y.
// Correr: flutter test test/features/home_widget/domain/widget_snapshot_builder_test.dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_day_move.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_snapshot_builder.dart';

import '../home_widget_test_helpers.dart';

PortfolioDayMove _move({
  double absolute = 123.45,
  double percent = 1.0,
  DayMovePeriod period = DayMovePeriod.today,
  String? top = 'NVDA',
}) => PortfolioDayMove(
  absolute: absolute,
  percent: percent,
  period: period,
  asOfDay: DateTime(2026, 11, 5),
  topContributor: top == null ? null : TopContributor(ticker: top, amount: 50),
);

Map<String, Object?> _ready({
  String lang = 'es',
  bool hidden = false,
  PortfolioDayMove? move,
  DateTime? asOf,
}) {
  final now = DateTime(2026, 11, 5, 10, 5);
  final s = WidgetSnapshotBuilder.ready(
    totalValue: 12345.67,
    move: move ?? _move(),
    amountsHidden: hidden,
    lang: lang,
    now: now,
    dataAsOf: asOf ?? DateTime(2026, 11, 5, 10),
    texts: realTexts(lang),
  );
  return jsonDecode(jsonEncode(s.toJson())) as Map<String, Object?>;
}

void main() {
  final now = DateTime(2026, 11, 5, 10, 5);

  group('signed out / no portfolio', () {
    test('only version, state, lang, written_at and the message', () {
      for (final lang in ['es', 'en']) {
        final signedOut =
            jsonDecode(
                  jsonEncode(
                    WidgetSnapshotBuilder.signedOut(
                      lang: lang,
                      now: now,
                      texts: realTexts(lang),
                    ).toJson(),
                  ),
                )
                as Map<String, Object?>;
        expect(signedOut.keys.toSet(), {
          'v',
          'state',
          'lang',
          'written_at',
          'labels',
        });
        expect(signedOut['state'], 'signed_out');
        expect((signedOut['labels']! as Map).keys, ['message']);
      }
      final es = WidgetSnapshotBuilder.signedOut(
        lang: 'es',
        now: now,
        texts: realTexts('es'),
      );
      expect(es.labels['message'], 'Entrá a Porty para ver tu cartera acá.');
      final en = WidgetSnapshotBuilder.noPortfolio(
        lang: 'en',
        now: now,
        texts: realTexts('en'),
      );
      expect(en.labels['message'], 'Add your portfolio to see it here.');
      expect(
        WidgetSnapshotBuilder.noPortfolio(
          lang: 'es',
          now: now,
          texts: realTexts('es'),
        ).labels['message'],
        'Cargá tu cartera y la vas a ver acá.',
      );
    });
  });

  group('ready', () {
    test('es: numbers formatted like the Home, phrase and questions', () {
      final j = _ready();
      expect(j['v'], 1);
      expect(j['state'], 'ready');
      expect(j['period'], 'today');
      expect(j['currency'], 'USD');
      expect(j['amounts_hidden'], false);
      expect(j['total_text'], r'$12,345.67');
      expect(j['change_text'], r'+$123.45');
      expect(j['change_pct_text'], '+1.0%');
      expect(j['direction'], 'up');
      expect(j['phrase'], 'Tu cartera sube hoy; NVDA sumó más.');
      expect(
        j['phrase_stale'],
        'Datos desactualizados. Abrí Porty para actualizarlos.',
      );
      expect(j['a11y_value'], r'Valor de la cartera $12,345.67, sube 1.0% hoy');
      expect(j['questions'], [
        {'id': 'today', 'text': '¿Cómo viene mi cartera hoy?'},
        {'id': 'top_mover', 'text': '¿Qué fue lo que más se movió?'},
      ]);
      expect((j['labels']! as Map)['stale_date'], 'al 5 nov');
    });

    test('en', () {
      final j = _ready(
        lang: 'en',
        move: _move(absolute: -50, percent: -0.8, top: 'AAPL'),
      );
      expect(j['lang'], 'en');
      expect(j['direction'], 'down');
      expect(
        j['phrase'],
        'Your portfolio is down today; AAPL took away the most.',
      );
      expect(j['change_text'], r'-$50.00');
      expect(j['a11y_value'], r'Portfolio value $12,345.67, down 0.8% today');
      expect((j['questions']! as List)[0], {
        'id': 'today',
        'text': "How's my portfolio doing today?",
      });
      expect((j['labels']! as Map)['stale_date'], 'as of Nov 5');
    });

    test('last close: no direction phrase, no ticker', () {
      final j = _ready(move: _move(period: DayMovePeriod.lastClose));
      expect(j['period'], 'last_close');
      expect(j['phrase'], 'Valores al último cierre.');
      expect(j['a11y_value'], contains('al último cierre'));
    });

    test('flat move', () {
      final j = _ready(move: _move(absolute: 1, percent: 0.1));
      expect(j['direction'], 'flat');
      expect(j['phrase'], 'Tu cartera casi no se movió hoy.');
    });

    test('no top contributor: the phrase without ticker', () {
      expect(_ready(move: _move(top: null))['phrase'], 'Tu cartera sube hoy.');
    });
  });

  group('hidden amounts', () {
    test('no totals, no amounts, no ticker anywhere in the JSON', () {
      for (final lang in ['es', 'en']) {
        final j = _ready(lang: lang, hidden: true);
        final raw = jsonEncode(j);
        expect(j.containsKey('total_text'), isFalse);
        expect(j.containsKey('change_text'), isFalse);
        expect(raw.contains('NVDA'), isFalse);
        expect(raw.contains('12,345'), isFalse);
        expect(raw.contains('123.45'), isFalse);
        expect(j['change_pct_text'], '+1.0%');
        expect(
          j['phrase'],
          lang == 'es' ? 'Tu cartera sube hoy.' : 'Your portfolio is up today.',
        );
        expect(
          j['a11y_value'],
          lang == 'es' ? 'Montos ocultos' : 'Amounts hidden',
        );
      }
    });

    test('no secrets or identifiers in any string', () {
      final raw = jsonEncode(_ready()).toLowerCase();
      for (final w in ['access_token', 'refresh_token', 'user_id', '@']) {
        expect(raw.contains(w), isFalse, reason: w);
      }
    });
  });

  group('staleAt', () {
    test('today: the earlier of 24 h and the next local midnight', () {
      final early = WidgetSnapshotBuilder.staleAt(
        DateTime(2026, 11, 5, 10),
        DayMovePeriod.today,
      );
      expect(early, DateTime(2026, 11, 6)); // medianoche (14 h) < 24 h
      final late = WidgetSnapshotBuilder.staleAt(
        DateTime(2026, 11, 5, 23, 59),
        DayMovePeriod.today,
      );
      expect(late, DateTime(2026, 11, 6)); // 1 min
    });

    test('last close: 24 h after the data', () {
      final at = WidgetSnapshotBuilder.staleAt(
        DateTime(2026, 11, 7, 10),
        DayMovePeriod.lastClose,
      );
      expect(at, DateTime(2026, 11, 8, 10));
    });

    test('is written as epoch ms UTC', () {
      final j = _ready();
      expect(
        j['stale_at'],
        DateTime(2026, 11, 6).toUtc().millisecondsSinceEpoch,
      );
      expect(
        j['data_as_of'],
        DateTime(2026, 11, 5, 10).toUtc().millisecondsSinceEpoch,
      );
    });
  });
}
