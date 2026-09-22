import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/position_valuation.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/explore_news_enricher.dart';
import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';
import 'package:portfolio_assistant/features/assistant/utils/assistant_snapshot_builder.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_raw_chat_client.dart';

class _FakeOpenAIRawChatClient extends OpenAIRawChatClient {
  _FakeOpenAIRawChatClient()
      : super(apiKey: 'test-key', model: 'test-model');

  @override
  Future<String> searchNews({
    required String userQuery,
    required List<String> tickers,
  }) async {
    throw StateError('should not be called');
  }
}

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
        exploreNewsEnricher: ExploreNewsEnricher(
          client: _FakeOpenAIRawChatClient(),
        ),
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
      expect(snapshot['monthly_contribution'], 200);
      expect(snapshot['has_complete_goal'], isTrue);
      expect(snapshot['projection'], isNotNull);
    });

    test('plan mode merges saved goal when message has no parsed goal', () async {
      final json = await buildSnapshotJson(
        mode: AssistantMode.plan,
        userMessage: '¿Voy bien con mi meta?',
        savedGoal: (
          label: 'Retiro',
          targetAmount: 50000,
          targetDate: '2030-01-01',
        ),
        monthlyContribution: 300,
        asOf: fixedAsOf,
      );
      final snapshot = jsonDecode(json) as Map<String, dynamic>;

      expect(snapshot['mode'], 'plan');
      expect(snapshot['parsed_goal'], isNull);
      expect(snapshot['has_complete_goal'], isTrue);
      expect(snapshot['saved_goal'], isNotNull);
      expect(
        (snapshot['active_goal'] as Map)['target_amount'],
        50000,
      );
      expect(snapshot['projection'], isNotNull);
    });

    test('plan mode returns incomplete snapshot without projection', () async {
      final json = await buildSnapshotJson(
        mode: AssistantMode.plan,
        userMessage: '¿Cuánto debo ahorrar por mes?',
        asOf: fixedAsOf,
      );
      final snapshot = jsonDecode(json) as Map<String, dynamic>;

      expect(snapshot['has_complete_goal'], isFalse);
      expect(snapshot['projection'], isNull);
      expect(snapshot['milestones'], isNull);
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

    // Regresión: antes learn/explore/invest/plan no recibían los datos
    // reales del portfolio, así que una pregunta sobre "mi portfolio" caída
    // en cualquiera de esos motores hacía que Porty respondiera que no
    // podía ver las inversiones del usuario. Ahora todos reciben un bloque
    // `portfolio_context` con la cartera real, sin importar qué motor
    // atienda el turno (de cara al usuario es un solo chat, sin pestañas).
    group('portfolio_context is available in every non-portfolio mode', () {
      final summary = PortfolioSummary(
        totalValue: 1000,
        totalCostBasis: 900,
        totalPnlAbsolute: 100,
        totalPnlPercent: 11.11,
        valuations: [
          PositionValuation(
            position: Position(
              id: '1',
              ticker: 'NVDA',
              quantity: 2,
              purchasePrice: 100,
              purchaseDate: DateTime(2024, 1, 1),
            ),
            currentPrice: 150,
            marketValue: 300,
            pnlAbsolute: 100,
            pnlPercent: 50,
          ),
        ],
      );

      test('learn mode includes the real portfolio in portfolio_context', () async {
        final json = await buildSnapshotJson(
          mode: AssistantMode.learn,
          summary: summary,
          asOf: fixedAsOf,
        );
        final snapshot = jsonDecode(json) as Map<String, dynamic>;

        expect(snapshot.containsKey('has_portfolio_data'), isFalse);
        final portfolioContext =
            snapshot['portfolio_context'] as Map<String, dynamic>;
        expect(portfolioContext['has_portfolio_data'], isTrue);
        expect(portfolioContext['total_value'], 1000);
        final positions = portfolioContext['positions'] as List<dynamic>;
        expect((positions.first as Map)['ticker'], 'NVDA');
      });

      test('explore mode includes the real portfolio in portfolio_context', () async {
        final json = await buildSnapshotJson(
          mode: AssistantMode.explore,
          summary: summary,
          asOf: fixedAsOf,
        );
        final snapshot = jsonDecode(json) as Map<String, dynamic>;

        final portfolioContext =
            snapshot['portfolio_context'] as Map<String, dynamic>;
        expect(portfolioContext['has_portfolio_data'], isTrue);
        expect(portfolioContext['total_value'], 1000);
      });

      test('invest mode includes the real portfolio in portfolio_context', () async {
        final json = await buildSnapshotJson(
          mode: AssistantMode.invest,
          summary: summary,
          asOf: fixedAsOf,
        );
        final snapshot = jsonDecode(json) as Map<String, dynamic>;

        final portfolioContext =
            snapshot['portfolio_context'] as Map<String, dynamic>;
        expect(portfolioContext['has_portfolio_data'], isTrue);
        expect(portfolioContext['total_value'], 1000);
      });

      test('plan mode includes the real portfolio in portfolio_context', () async {
        final json = await buildSnapshotJson(
          mode: AssistantMode.plan,
          summary: summary,
          asOf: fixedAsOf,
        );
        final snapshot = jsonDecode(json) as Map<String, dynamic>;

        final portfolioContext =
            snapshot['portfolio_context'] as Map<String, dynamic>;
        expect(portfolioContext['has_portfolio_data'], isTrue);
        expect(portfolioContext['total_value'], 1000);
      });
    });
  });
}
