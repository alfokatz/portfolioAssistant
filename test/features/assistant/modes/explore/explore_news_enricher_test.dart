import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/explore_news_enricher.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_raw_chat_client.dart';

class _FakeOpenAIRawChatClient extends OpenAIRawChatClient {
  _FakeOpenAIRawChatClient({
    required this.onSearchNews,
  }) : super(apiKey: 'test-key', model: 'test-model');

  final Future<String> Function({
    required String userQuery,
    required List<String> tickers,
  }) onSearchNews;

  @override
  Future<String> searchNews({
    required String userQuery,
    required List<String> tickers,
  }) {
    return onSearchNews(userQuery: userQuery, tickers: tickers);
  }
}

void main() {
  group('ExploreNewsEnricher', () {
    const baseSnapshot = <String, Object?>{
      'mode': 'explore',
      'data_source': 'yahoo_finance',
    };

    test('skips enrichment for non-news queries', () async {
      final enricher = ExploreNewsEnricher(
        client: _FakeOpenAIRawChatClient(
          onSearchNews: ({required userQuery, required tickers}) async =>
              throw StateError('should not be called'),
        ),
      );

      final result = await enricher.enrich(
        snapshot: Map<String, Object?>.from(baseSnapshot),
        userMessage: 'Cuéntame de AAPL',
      );

      expect(result['mode'], 'explore');
      expect(result['data_source'], 'yahoo_finance');
      expect(result['news_sources'], isEmpty);
      expect(result['news_enrichment'], 'skipped');
    });

    test('enriches snapshot with parsed sources on success', () async {
      final enricher = ExploreNewsEnricher(
        client: _FakeOpenAIRawChatClient(
          onSearchNews: ({required userQuery, required tickers}) async {
            expect(userQuery, '¿qué pasó con AAPL esta semana?');
            expect(tickers, ['AAPL']);
            return '''
- headline: Apple shares rise on earnings
- url: https://reuters.com/aapl-earnings
- Apple beat analyst expectations this quarter.
''';
          },
        ),
      );

      final result = await enricher.enrich(
        snapshot: Map<String, Object?>.from(baseSnapshot),
        userMessage: '¿qué pasó con AAPL esta semana?',
      );

      expect(result['news_enrichment'], 'ok');
      final sources = result['news_sources'] as List<dynamic>;
      expect(sources, hasLength(1));
      final source = sources.first as Map<String, dynamic>;
      expect(source['title'], 'Apple shares rise on earnings');
      expect(source['url'], 'https://reuters.com/aapl-earnings');
      expect(source['snippet'], contains('Apple beat analyst expectations'));
    });

    test('marks enrichment empty when search returns no urls', () async {
      final enricher = ExploreNewsEnricher(
        client: _FakeOpenAIRawChatClient(
          onSearchNews: ({required userQuery, required tickers}) async =>
              'No se encontraron noticias recientes.',
        ),
      );

      final result = await enricher.enrich(
        snapshot: Map<String, Object?>.from(baseSnapshot),
        userMessage: '¿noticias de NVDA?',
      );

      expect(result['news_enrichment'], 'empty');
      expect(result['news_sources'], isEmpty);
    });

    test('marks enrichment failed on client exception without rethrowing', () async {
      final enricher = ExploreNewsEnricher(
        client: _FakeOpenAIRawChatClient(
          onSearchNews: ({required userQuery, required tickers}) async =>
              throw StateError('API down'),
        ),
      );

      final result = await enricher.enrich(
        snapshot: Map<String, Object?>.from(baseSnapshot),
        userMessage: '¿por qué cayó NVDA?',
      );

      expect(result['news_enrichment'], 'failed');
      expect(result['news_sources'], isEmpty);
      expect(result['mode'], 'explore');
    });
  });
}
