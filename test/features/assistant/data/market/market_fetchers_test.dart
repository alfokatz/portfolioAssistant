import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/company_fundamentals.dart';
import 'package:portfolio_assistant/domain/entities/earnings_calendar_entry.dart';
import 'package:portfolio_assistant/domain/entities/earnings_report_result.dart';
import 'package:portfolio_assistant/features/assistant/data/market/earnings_fetcher.dart';
import 'package:portfolio_assistant/features/assistant/data/market/fundamentals_fetcher.dart';
import 'package:portfolio_assistant/features/assistant/data/market/news_fetcher.dart';

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
        'date_label': '13 nov 2026',
        'fiscal_period_label': 'T3 FY27',
        'eps_estimate': 1.72,
      });
      expect((nvda['latest_result'] as Map)['beat'], isTrue);
    });

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

    test('failed when every source fails', () async {
      final result = await NewsFetcher(
        repository: FakeCompanyNewsRepository(fail: true),
      ).fetch(['AAPL']);
      expect(result['status'], 'failed');
    });
  });
}
