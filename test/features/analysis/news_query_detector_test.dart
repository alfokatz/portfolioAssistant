import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/analysis/utils/news_query_detector.dart';

void main() {
  group('isNewsQuery', () {
    test('detects portfolio news questions', () {
      expect(isNewsQuery('¿qué noticias hay de mi portfolio?'), isTrue);
    });

    test('detects tickerx-specific news questions', () {
      expect(isNewsQuery('¿qué pasó con AAPL esta semana?'), isTrue);
    });

    test('detects pre-investment risk questions', () {
      expect(
        isNewsQuery('¿hay algo que debería saber antes de invertir más?'),
        isTrue,
      );
    });

    test('detects general market questions', () {
      expect(isNewsQuery('¿cómo está el mercado hoy?'), isTrue);
    });

    test('does not flag regular portfolio analysis', () {
      expect(isNewsQuery('¿Cómo estoy hoy?'), isFalse);
      expect(isNewsQuery('Haceme un resumen de mi portfolio actual'), isFalse);
    });
  });
}
