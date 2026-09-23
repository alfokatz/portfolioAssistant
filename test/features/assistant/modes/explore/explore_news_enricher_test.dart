import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/company_news_item.dart';
import 'package:portfolio_assistant/domain/repositories/company_news_repository.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/explore_news_enricher.dart';

class _FakeCompanyNewsRepository implements CompanyNewsRepository {
  _FakeCompanyNewsRepository(this.onGetRecentNews);

  final Future<Either<HttpError, List<CompanyNewsItem>>> Function(
    String ticker,
  )
  onGetRecentNews;

  @override
  Future<Either<HttpError, List<CompanyNewsItem>>> getRecentNews(
    String ticker, {
    int limit = 3,
  }) {
    return onGetRecentNews(ticker);
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
        newsRepository: _FakeCompanyNewsRepository(
          (_) async => throw StateError('should not be called'),
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

    test('enriches snapshot with structured sources on success', () async {
      final enricher = ExploreNewsEnricher(
        newsRepository: _FakeCompanyNewsRepository((ticker) async {
          expect(ticker, 'AAPL');
          return Right([
            CompanyNewsItem(
              ticker: 'AAPL',
              headline: 'Apple shares rise on earnings',
              summary: 'Apple beat analyst expectations this quarter.',
              url: 'https://reuters.com/aapl-earnings',
              source: 'Reuters',
              publishedAt: DateTime.utc(2026, 9, 20),
            ),
          ]);
        }),
      );

      final result = await enricher.enrich(
        snapshot: Map<String, Object?>.from(baseSnapshot),
        userMessage: '¿qué pasó con AAPL esta semana?',
      );

      expect(result['news_enrichment'], 'ok');
      final sources = result['news_sources'] as List<dynamic>;
      expect(sources, hasLength(1));
      final source = sources.first as Map<String, dynamic>;
      expect(source['ticker'], 'AAPL');
      expect(source['title'], 'Apple shares rise on earnings');
      expect(source['url'], 'https://reuters.com/aapl-earnings');
      expect(source['source'], 'Reuters');
      expect(source['snippet'], contains('Apple beat analyst expectations'));
      expect(source['published_at'], DateTime.utc(2026, 9, 20).toIso8601String());
    });

    // Fallback honesto: cuando la API respondió bien pero no hay artículos
    // para el ticker, el snapshot debe decirlo explícitamente ("empty"), no
    // simular una fuente ni pretender que hubo error.
    test(
      'marks enrichment empty when repository returns no articles for the ticker',
      () async {
        final enricher = ExploreNewsEnricher(
          newsRepository: _FakeCompanyNewsRepository(
            (_) async => const Right(<CompanyNewsItem>[]),
          ),
        );

        final result = await enricher.enrich(
          snapshot: Map<String, Object?>.from(baseSnapshot),
          userMessage: '¿noticias de NVDA?',
        );

        expect(result['news_enrichment'], 'empty');
        expect(result['news_sources'], isEmpty);
      },
    );

    test(
      'marks enrichment failed when repository fails without rethrowing',
      () async {
        final enricher = ExploreNewsEnricher(
          newsRepository: _FakeCompanyNewsRepository(
            (_) async => Left(HttpError(code: 'network_error')),
          ),
        );

        final result = await enricher.enrich(
          snapshot: Map<String, Object?>.from(baseSnapshot),
          userMessage: '¿por qué cayó NVDA?',
        );

        expect(result['news_enrichment'], 'failed');
        expect(result['news_sources'], isEmpty);
        expect(result['mode'], 'explore');
      },
    );

    test('marks enrichment empty when the message has no ticker', () async {
      final enricher = ExploreNewsEnricher(
        newsRepository: _FakeCompanyNewsRepository(
          (_) async => throw StateError('should not be called'),
        ),
      );

      final result = await enricher.enrich(
        snapshot: Map<String, Object?>.from(baseSnapshot),
        userMessage: '¿qué noticias hay del mercado hoy?',
      );

      expect(result['news_enrichment'], 'empty');
      expect(result['news_sources'], isEmpty);
    });
  });
}
