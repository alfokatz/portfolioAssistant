import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/company_news_item.dart';
import 'package:portfolio_assistant/domain/entities/company_fundamentals.dart';
import 'package:portfolio_assistant/domain/entities/earnings_calendar_entry.dart';
import 'package:portfolio_assistant/domain/entities/earnings_report_result.dart';
import 'package:portfolio_assistant/domain/entities/earnings_surprise.dart';
import 'package:portfolio_assistant/domain/repositories/company_news_repository.dart';
import 'package:portfolio_assistant/domain/repositories/earnings_history_repository.dart';
import 'package:portfolio_assistant/features/assistant/data/market/earnings_fetcher.dart';
import 'package:portfolio_assistant/features/assistant/data/market/fundamentals_fetcher.dart';
import 'package:portfolio_assistant/features/assistant/data/market/news_fetcher.dart';
import 'package:portfolio_assistant/features/assistant/data/market/news_media_index.dart';

import '../../fakes/assistant_fakes.dart';

void main() {
  group('FundamentalsFetcher', () {
    test('ok with data, empty without, failed when the source fails', () async {
      final ok = await FundamentalsFetcher(
        repository: FakeCompanyFundamentalsRepository(
          data: const CompanyFundamentals(
            ticker: 'AAPL',
            peTTM: 38.6,
            dividendYieldIndicatedAnnual: 0.51,
          ),
        ),
      ).fetch(['AAPL']);
      expect(ok['status'], 'ok');
      expect((ok['fundamentals'] as Map)['AAPL'], {
        'pe_ttm': 38.6,
        'dividend_yield_indicated_annual': 0.51,
      });

      final empty = await FundamentalsFetcher(
        repository: FakeCompanyFundamentalsRepository(),
      ).fetch(['AAPL']);
      expect(empty['status'], 'empty');

      final failed = await FundamentalsFetcher(
        repository: FakeCompanyFundamentalsRepository(fail: true),
      ).fetch(['AAPL']);
      expect(failed['status'], 'failed');
    });

    test(
      'caches per ticker (the Finnhub key is shared by every user)',
      () async {
        final repo = FakeCompanyFundamentalsRepository(
          data: const CompanyFundamentals(ticker: 'AAPL', peTTM: 1),
        );
        final fetcher = FundamentalsFetcher(repository: repo);
        await fetcher.fetch(['AAPL']);
        await fetcher.fetch(['AAPL']);
        expect(repo.calls, ['AAPL']);
      },
    );
  });

  group('EarningsFetcher', () {
    test('next report with consensus EPS and last result with beat', () async {
      final result = await EarningsFetcher(
        repository: FakeEarningsCalendarRepository(
          next: EarningsCalendarEntry(
            ticker: 'NVDA',
            reportDate: DateTime(2026, 11, 13),
            fiscalQuarter: 3,
            fiscalYear: 2027,
            epsEstimate: 1.72,
            hour: 'amc',
          ),
          latest: EarningsReportResult(
            ticker: 'NVDA',
            reportDate: DateTime(2026, 8, 27),
            epsActual: 1.57,
            epsEstimate: 1.43,
          ),
        ),
      ).fetch(['NVDA']);

      final nvda = (result['earnings'] as Map)['NVDA'] as Map;
      expect(result['status'], 'ok');
      expect(nvda['next_report'], {
        'date': '2026-11-13',
        'date_label': '13 nov 2026',
        'fiscal_period_label': 'T3 FY27',
        'timing_label': 'Después del cierre',
        'eps_estimate': 1.72,
      });
      expect((nvda['latest_result'] as Map)['beat'], isTrue);
      expect((nvda['latest_result'] as Map)['surprise_pct'], 9.8);
      expect(nvda.containsKey('history'), isFalse);
    });

    test('history oldest first (max 4) and latest_result falls back to it '
        'when the calendar has no actual', () async {
      final result = await EarningsFetcher(
        repository: FakeEarningsCalendarRepository(),
        historyRepository: _FakeHistory([
          for (var q = 5; q >= 1; q--)
            EarningsSurprise(
              ticker: 'TSLA',
              period: DateTime(2026, q * 2),
              fiscalQuarter: (q - 1) % 4 + 1,
              fiscalYear: 2026,
              epsActual: q * 0.1,
              epsEstimate: 0.25,
              surprisePercent: q * 1.0,
            ),
        ]),
      ).fetch(['TSLA']);

      final tsla = (result['earnings'] as Map)['TSLA'] as Map;
      final history = tsla['history'] as List;
      expect(history, hasLength(EarningsFetcher.maxHistory));
      expect((history.first as Map)['eps_actual'], closeTo(0.2, 1e-9));
      expect((history.last as Map)['eps_actual'], closeTo(0.5, 1e-9));
      expect(history.last, {
        'fiscal_period_label': 'T1 FY26',
        'eps_actual': 0.5,
        'eps_estimate': 0.25,
        'surprise_pct': 5.0,
        'beat': true,
      });
      expect(tsla['latest_result'], history.last);
    });

    test(
      'a failing history does not fail the calendar (and is not cached)',
      () async {
        final history = _FakeHistory(const [], fail: true);
        final fetcher = EarningsFetcher(
          repository: FakeEarningsCalendarRepository(
            next: EarningsCalendarEntry(
              ticker: 'X',
              reportDate: DateTime(2026, 11, 1),
            ),
          ),
          historyRepository: history,
        );
        final first = await fetcher.fetch(['X']);
        expect(first['status'], 'ok');
        await fetcher.fetch(['X']);
        expect(history.calls, 2);
      },
    );

    test('failed vs empty', () async {
      expect(
        (await EarningsFetcher(
          repository: FakeEarningsCalendarRepository(fail: true),
        ).fetch(['X']))['status'],
        'failed',
      );
      expect(
        (await EarningsFetcher(
          repository: FakeEarningsCalendarRepository(),
        ).fetch(['X']))['status'],
        'empty',
      );
    });
  });

  group('NewsFetcher', () {
    test('merges tickers, newest first, max 3', () async {
      final result = await NewsFetcher(
        repository: FakeCompanyNewsRepository(),
      ).fetch(['AAPL', 'MSFT', 'NVDA', 'TSLA']);
      expect(result['status'], 'ok');
      expect(result['news'], hasLength(NewsFetcher.maxItems));
    });

    test('records image + timestamp by url, never sends the image', () async {
      final index = NewsMediaIndex();
      final result = await NewsFetcher(
        repository: _ImageNews(),
        mediaIndex: index,
      ).fetch(['AAPL']);
      final item = (result['news'] as List).single as Map;
      expect(item.containsKey('image'), isFalse);
      expect(item.values, isNot(contains('https://example.com/a.jpg')));
      expect(
        index.lookup(item['url'] as String)?.imageUrl,
        'https://example.com/a.jpg',
      );
    });

    test('failed when every source fails', () async {
      final result = await NewsFetcher(
        repository: FakeCompanyNewsRepository(fail: true),
      ).fetch(['AAPL']);
      expect(result['status'], 'failed');
    });
  });
}

class _FakeHistory implements EarningsHistoryRepository {
  _FakeHistory(this.items, {this.fail = false});

  final List<EarningsSurprise> items;
  final bool fail;
  var calls = 0;

  @override
  Future<Either<HttpError, List<EarningsSurprise>>> getEpsHistory(
    String ticker,
  ) async {
    calls++;
    return fail ? Left(HttpError(code: 'x')) : Right(items);
  }
}

class _ImageNews implements CompanyNewsRepository {
  @override
  Future<Either<HttpError, List<CompanyNewsItem>>> getRecentNews(
    String ticker, {
    int limit = 3,
    DateTime? from,
    DateTime? to,
  }) async => Right([
    CompanyNewsItem(
      ticker: ticker,
      headline: 'AAPL headline',
      summary: 's',
      url: 'https://example.com/a',
      source: 'Reuters',
      publishedAt: DateTime.utc(2026, 9, 24),
      imageUrl: 'https://example.com/a.jpg',
    ),
  ]);
}
