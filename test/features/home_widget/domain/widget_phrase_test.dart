// Frase del widget: texto exacto de cada plantilla aprobada por compliance,
// en es y en, y que nunca recomiende, juzgue ni dé causas.
// Correr: flutter test test/features/home_widget/domain/widget_phrase_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_day_move.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_phrase.dart';

import '../home_widget_test_helpers.dart';

String _phrase(
  String lang,
  WidgetDirection d, {
  DayMovePeriod period = DayMovePeriod.today,
  String? ticker,
}) => WidgetPhrase.resolve(
  period: period,
  direction: d,
  topTicker: ticker,
  texts: realTexts(lang),
);

void main() {
  group('WidgetDirection.fromPercent', () {
    test('flat under 0.3 in absolute value', () {
      expect(WidgetDirection.fromPercent(0.29), WidgetDirection.flat);
      expect(WidgetDirection.fromPercent(-0.29), WidgetDirection.flat);
      expect(WidgetDirection.fromPercent(0.3), WidgetDirection.up);
      expect(WidgetDirection.fromPercent(-0.3), WidgetDirection.down);
    });
  });

  group('WidgetPhrase approved templates', () {
    test('es', () {
      expect(
        _phrase('es', WidgetDirection.flat),
        'Tu cartera casi no se movió hoy.',
      );
      expect(
        _phrase('es', WidgetDirection.up, ticker: 'NVDA'),
        'Tu cartera sube hoy; NVDA sumó más.',
      );
      expect(
        _phrase('es', WidgetDirection.down, ticker: 'NVDA'),
        'Tu cartera baja hoy; NVDA restó más.',
      );
      expect(_phrase('es', WidgetDirection.up), 'Tu cartera sube hoy.');
      expect(_phrase('es', WidgetDirection.down), 'Tu cartera baja hoy.');
      expect(
        _phrase(
          'es',
          WidgetDirection.up,
          period: DayMovePeriod.lastClose,
          ticker: 'X',
        ),
        'Valores al último cierre.',
      );
      expect(
        WidgetPhrase.stale(realTexts('es')),
        'Datos desactualizados. Abrí Porty para actualizarlos.',
      );
    });

    test('en', () {
      expect(
        _phrase('en', WidgetDirection.flat),
        'Your portfolio barely moved today.',
      );
      expect(
        _phrase('en', WidgetDirection.up, ticker: 'NVDA'),
        'Your portfolio is up today; NVDA added the most.',
      );
      expect(
        _phrase('en', WidgetDirection.down, ticker: 'NVDA'),
        'Your portfolio is down today; NVDA took away the most.',
      );
      expect(_phrase('en', WidgetDirection.up), 'Your portfolio is up today.');
      expect(
        _phrase('en', WidgetDirection.down),
        'Your portfolio is down today.',
      );
      expect(
        _phrase('en', WidgetDirection.down, period: DayMovePeriod.lastClose),
        'Values as of the last close.',
      );
      expect(
        WidgetPhrase.stale(realTexts('en')),
        'Data is out of date. Open Porty to refresh it.',
      );
    });
  });

  group('WidgetPhrase compliance rules', () {
    final forbidden = {
      'es': RegExp(
        r'mantené|aprovechá|comprá|vendé|buen|mal\b|tranquilo|preocupante|'
        r'por qué|gracias a|debido a|probablemente|va a|mercado cerrado',
        caseSensitive: false,
      ),
      'en': RegExp(
        r'\bkeep\b|\bbuy\b|\bsell\b|\bgood\b|\bbad\b|calm|worrying|because|'
        r'thanks to|due to|will|market closed|\bled by\b',
        caseSensitive: false,
      ),
    };

    for (final lang in ['es', 'en']) {
      test('no action, judgement, cause or projection ($lang)', () {
        for (final d in WidgetDirection.values) {
          for (final period in DayMovePeriod.values) {
            for (final ticker in [null, 'NVDA']) {
              final text = _phrase(lang, d, period: period, ticker: ticker);
              expect(forbidden[lang]!.hasMatch(text), isFalse, reason: text);
            }
          }
        }
        expect(
          forbidden[lang]!.hasMatch(WidgetPhrase.stale(realTexts(lang))),
          isFalse,
        );
      });

      test('last close never says today with a direction ($lang)', () {
        final word =
            lang == 'es'
                ? RegExp('hoy', caseSensitive: false)
                : RegExp('today', caseSensitive: false);
        for (final d in WidgetDirection.values) {
          final text = _phrase(
            lang,
            d,
            period: DayMovePeriod.lastClose,
            ticker: 'X',
          );
          expect(word.hasMatch(text), isFalse, reason: text);
        }
        expect(word.hasMatch(WidgetPhrase.stale(realTexts(lang))), isFalse);
      });
    }
  });
}
