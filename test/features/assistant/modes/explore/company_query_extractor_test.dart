import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/company_query_extractor.dart';

void main() {
  group('CompanyQueryExtractor', () {
    test('extracts company name from natural language question', () {
      expect(
        CompanyQueryExtractor.fromMessage(
          'como le fue a la accion de takes two esta semana',
        ),
        'takes two',
      );
    });

    test('extracts company from precio de phrasing', () {
      expect(
        CompanyQueryExtractor.fromMessage('¿Cuál es el precio de Netflix hoy?'),
        'netflix',
      );
    });

    test('returns null for empty noise-only message', () {
      expect(
        CompanyQueryExtractor.fromMessage('¿Cómo está el mercado?'),
        isNull,
      );
    });
  });
}
