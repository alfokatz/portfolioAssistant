import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/news_source_parser.dart';

void main() {
  group('ExploreNewsSourceParser', () {
    test('parses structured story blocks with headline and summary', () {
      const rawText = '''
Story 1:
- headline: Apple reportó ganancias sólidas
- source: Reuters
- publishedAt: hace 2 horas
- url: https://reuters.com/aapl-earnings
- affected tickers: AAPL
- Apple superó las expectativas del mercado. Las ventas de iPhone crecieron.

Story 2:
- headline: Nvidia cae tras resultados mixtos
- url: https://bloomberg.com/nvda-mixed
- Nvidia reportó ingresos por debajo del consenso. Los analistas recortaron objetivos.
''';

      final sources = ExploreNewsSourceParser.parse(rawText);

      expect(sources, hasLength(2));
      expect(sources[0].url, 'https://reuters.com/aapl-earnings');
      expect(sources[0].title, 'Apple reportó ganancias sólidas');
      expect(sources[0].snippet, contains('Apple superó las expectativas'));
      expect(sources[1].url, 'https://bloomberg.com/nvda-mixed');
      expect(sources[1].title, 'Nvidia cae tras resultados mixtos');
    });

    test('parses Sources section appended by extractResponsesOutputText', () {
      const rawText = '''
Apple reportó ganancias sólidas esta semana.

Sources:
- https://reuters.com/aapl-earnings
- https://finance.yahoo.com/news/aapl-q2
''';

      final sources = ExploreNewsSourceParser.parse(rawText);

      expect(sources, hasLength(2));
      expect(sources.map((s) => s.url), contains('https://reuters.com/aapl-earnings'));
      expect(sources.map((s) => s.url), contains('https://finance.yahoo.com/news/aapl-q2'));
    });

    test('merges Sources section with earlier structured entries', () {
      const rawText = '''
- headline: Apple earnings beat
- url: https://reuters.com/aapl-earnings
- Apple superó expectativas.

Sources:
- https://reuters.com/aapl-earnings
- https://finance.yahoo.com/news/aapl-q2
''';

      final sources = ExploreNewsSourceParser.parse(rawText);

      expect(sources, hasLength(2));
      expect(sources.first.url, 'https://reuters.com/aapl-earnings');
      expect(sources.first.title, 'Apple earnings beat');
      expect(sources.last.url, 'https://finance.yahoo.com/news/aapl-q2');
    });

    test('returns empty list when no valid http urls are present', () {
      expect(ExploreNewsSourceParser.parse('No hay noticias recientes.'), isEmpty);
      expect(ExploreNewsSourceParser.parse(''), isEmpty);
      expect(
        ExploreNewsSourceParser.parse('Visita example.com para más info'),
        isEmpty,
      );
    });

    test('never fabricates urls and deduplicates by url', () {
      const rawText = '''
- url: https://reuters.com/aapl
- url: https://reuters.com/aapl
- headline: Duplicate story
- url: https://reuters.com/aapl
''';

      final sources = ExploreNewsSourceParser.parse(rawText);

      expect(sources, hasLength(1));
      expect(sources.single.url, 'https://reuters.com/aapl');
    });

    test('toJson returns title url and snippet', () {
      const source = ExploreNewsSource(
        title: 'Headline',
        url: 'https://example.com/story',
        snippet: 'Summary text',
      );

      expect(source.toJson(), {
        'title': 'Headline',
        'url': 'https://example.com/story',
        'snippet': 'Summary text',
      });
    });
  });
}
