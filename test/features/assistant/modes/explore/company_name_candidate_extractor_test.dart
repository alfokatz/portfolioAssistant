import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/company_name_candidate_extractor.dart';

void main() {
  group('CompanyNameCandidateExtractor', () {
    test('picks up a capitalized company name in a lowercase sentence', () {
      expect(
        CompanyNameCandidateExtractor.extract('noticias de Apple'),
        'Apple',
      );
    });

    test('picks up a multi-word capitalized company name', () {
      expect(
        CompanyNameCandidateExtractor.extract('cómo le fue a Johnson Johnson'),
        'Johnson Johnson',
      );
    });

    test('prefers the longest capitalized run when there are several', () {
      expect(
        CompanyNameCandidateExtractor.extract('Cuéntame de Johnson Johnson'),
        'Johnson Johnson',
      );
    });

    test(
      'falls back to filtered lowercase words when nothing is capitalized',
      () {
        final candidate = CompanyNameCandidateExtractor.extract(
          'noticias de apple',
        );
        expect(candidate, isNotNull);
        expect(candidate, contains('apple'));
        expect(candidate, isNot(contains('noticias')));
      },
    );

    test(
      'excludes a leading question word even when capitalized, instead of '
      'treating it as the company candidate',
      () {
        // "Como" queda excluido por ser un leading stop word; el resto de
        // las palabras ("esta", "el", "mercado", "hoy") son conectores
        // filtrados también — no queda ningún candidato razonable.
        final candidate = CompanyNameCandidateExtractor.extract(
          'Como esta el mercado hoy',
        );
        expect(candidate, isNull);
      },
    );

    test('returns null when there is no plausible candidate', () {
      // Sin ninguna palabra capitalizada y con todo el resto de tokens
      // demasiado cortos (menos de 3 letras) para ser un candidato
      // razonable — no hay nada sensato que mandarle a Finnhub /search.
      expect(CompanyNameCandidateExtractor.extract('es de mi'), isNull);
    });
  });
}
