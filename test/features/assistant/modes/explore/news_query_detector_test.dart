import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/news_query_detector.dart';

void main() {
  group('isNewsQuery', () {
    test('detects portfolio news questions', () {
      expect(isNewsQuery('¿qué noticias hay de mi portfolio?'), isTrue);
    });

    test('detects ticker-specific news questions', () {
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

    test('detects causation queries about price moves', () {
      expect(isNewsQuery('¿por qué cayó NVDA?'), isTrue);
      expect(isNewsQuery('why did AAPL fall today?'), isTrue);
      expect(isNewsQuery('what caused the drop in TSLA'), isTrue);
      expect(isNewsQuery('motivo de la caída de MSFT'), isTrue);
    });

    test('does not flag regular portfolio analysis', () {
      expect(isNewsQuery('¿Cómo estoy hoy?'), isFalse);
      expect(isNewsQuery('Haceme un resumen de mi portfolio actual'), isFalse);
    });

    test('does not flag generic ticker exploration', () {
      expect(isNewsQuery('Cuéntame de AAPL'), isFalse);
      expect(isNewsQuery('Compare GOOGL and AMZN'), isFalse);
    });
  });

  // Regresión (producción): el paywall Gold y el peso 3 de cuota usaban
  // `isNewsQuery`, que también cuenta "esta semana", "por qué", "subió",
  // "caída"… Un Premium quedaba bloqueado por preguntas de precio que su
  // plan cubre, y un Gold pagaba triple por ellas.
  group('isExplicitNewsRequest', () {
    test('price/time/why phrasings are NOT explicit news requests', () {
      for (final message in const [
        '¿Cómo está NVDA esta semana?',
        '¿Cuál es el precio de NVDA? ¿Por qué subió?',
        '¿Cómo está TSLA después de la caída?',
        '¿Cómo está AAPL? Porque la quiero comprar',
        'últimas cotizaciones de MSFT',
      ]) {
        expect(isNewsQuery(message), isTrue, reason: 'broad detector: $message');
        expect(isExplicitNewsRequest(message), isFalse, reason: message);
      }
    });

    test('explicit news / events requests are', () {
      for (final message in const [
        '¿Qué noticias hay de AAPL?',
        'últimas novedades de MSFT',
        'titulares de TSLA',
        '¿Qué pasó con NVDA?',
        'latest news on AAPL',
        'what happened to TSLA?',
      ]) {
        expect(isExplicitNewsRequest(message), isTrue, reason: message);
      }
    });
  });
}
