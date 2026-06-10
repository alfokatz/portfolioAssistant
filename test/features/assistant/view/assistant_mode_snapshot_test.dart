import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';
import 'package:portfolio_assistant/features/assistant/utils/assistant_snapshot_builder.dart';

class _FakeQuoteRepository implements QuoteRepository {
  @override
  Future<Either<HttpError, double>> getCurrentPrice(String ticker) async {
    if (ticker == 'NVDA') return const Right(120.0);
    return Left(HttpError(code: 'not_found'));
  }

  @override
  Future<Either<HttpError, List<PriceCandle>>> getHistoricalDaily(
    String ticker,
  ) async {
    if (ticker == 'NVDA') {
      final end = DateTime(2026, 6, 10);
      return Right(
        List<PriceCandle>.generate(
          10,
          (i) => PriceCandle(
            date: end.subtract(Duration(days: 9 - i)),
            close: 110.0 + i,
          ),
        ),
      );
    }
    return Left(HttpError(code: 'not_found'));
  }
}

void main() {
  group('buildSnapshotJson', () {
    final fixedAsOf = DateTime.utc(2026, 6, 10, 12, 0);

    test('learn mode returns minimal snapshot with mode learn', () async {
      final json = await buildSnapshotJson(
        mode: AssistantMode.learn,
        asOf: fixedAsOf,
      );
      final snapshot = jsonDecode(json) as Map<String, dynamic>;

      expect(snapshot['mode'], 'learn');
      expect(snapshot['as_of'], fixedAsOf.toIso8601String());
      expect(snapshot.containsKey('has_portfolio_data'), isFalse);
    });

    test('explore mode without quote repo returns empty explore_tickers', () async {
      final json = await buildSnapshotJson(
        mode: AssistantMode.explore,
        asOf: fixedAsOf,
      );
      final snapshot = jsonDecode(json) as Map<String, dynamic>;

      expect(snapshot['mode'], 'explore');
      expect(snapshot['data_source'], 'yahoo_finance');
      expect(snapshot['explore_tickers'], isEmpty);
      expect(snapshot['as_of'], fixedAsOf.toIso8601String());
    });

    test('explore mode with userMessage extracts tickers via quote repo', () async {
      final json = await buildSnapshotJson(
        mode: AssistantMode.explore,
        userMessage: '¿Cómo está NVDA?',
        quoteRepository: _FakeQuoteRepository(),
        asOf: fixedAsOf,
      );
      final snapshot = jsonDecode(json) as Map<String, dynamic>;

      expect(snapshot['mode'], 'explore');
      final tickers = snapshot['explore_tickers'] as Map<String, dynamic>;
      expect(tickers.containsKey('NVDA'), isTrue);
      expect((tickers['NVDA'] as Map)['fetch_ok'], isTrue);
    });

    test('invest mode without quote repo returns empty candidates', () async {
      final json = await buildSnapshotJson(
        mode: AssistantMode.invest,
        asOf: fixedAsOf,
      );
      final snapshot = jsonDecode(json) as Map<String, dynamic>;

      expect(snapshot['mode'], 'invest');
      expect(snapshot['data_source'], 'yahoo_finance');
      expect(snapshot['as_of'], fixedAsOf.toIso8601String());
      expect(snapshot['has_budget'], isFalse);
      expect(snapshot['candidates'], isEmpty);
    });

    test('invest mode with userMessage builds candidates via quote repo', () async {
      final json = await buildSnapshotJson(
        mode: AssistantMode.invest,
        userMessage: 'Invertir \$500 en NVDA',
        quoteRepository: _FakeQuoteRepository(),
        riskProfile: 0.5,
        asOf: fixedAsOf,
      );
      final snapshot = jsonDecode(json) as Map<String, dynamic>;

      expect(snapshot['mode'], 'invest');
      expect(snapshot['has_budget'], isTrue);
      expect(snapshot['budget_usd'], 500.0);
      expect(snapshot['risk_profile'], 0.5);

      final candidates = snapshot['candidates'] as List<dynamic>;
      expect(candidates, isNotEmpty);
      final first = candidates.first as Map<String, dynamic>;
      expect(first['ticker'], 'NVDA');
      expect(first['fetch_ok'], isTrue);
    });

    test('plan mode builds computed snapshot via PlanContextBuilder', () async {
      final json = await buildSnapshotJson(
        mode: AssistantMode.plan,
        userMessage: 'Quiero ahorrar \$50.000 para 2030',
        monthlyContribution: 200,
        asOf: fixedAsOf,
      );
      final snapshot = jsonDecode(json) as Map<String, dynamic>;

      expect(snapshot['mode'], 'plan');
      expect(snapshot['data_source'], 'computed');
      expect(snapshot['as_of'], fixedAsOf.toIso8601String());
      expect(snapshot['has_complete_goal'], isTrue);
      expect(snapshot['projection'], isNotNull);
    });

    test('portfolio mode without data returns has_portfolio_data false', () async {
      final json = await buildSnapshotJson(
        mode: AssistantMode.portfolio,
        asOf: fixedAsOf,
      );
      final snapshot = jsonDecode(json) as Map<String, dynamic>;

      expect(snapshot['has_portfolio_data'], isFalse);
      expect(snapshot['as_of'], fixedAsOf.toIso8601String());
    });
  });
}
