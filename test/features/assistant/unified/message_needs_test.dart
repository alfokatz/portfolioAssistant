import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/entities/symbol_search_result.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/company_ticker_resolver.dart';
import 'package:portfolio_assistant/features/assistant/unified/message_needs.dart';
import 'package:portfolio_assistant/features/assistant/unified/unified_access_policy.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';

import 'unified_test_fakes.dart';

/// Capa determinística debajo de la decisión del modelo: qué datos pide el
/// pipeline unificado para cada mensaje y qué gating aplica. Acá viven los
/// adversariales que se pueden afirmar SIN el modelo (ej. que "¿qué es un
/// ETF, como SPY?" no pide datos de SPY ni dispara el paywall).
void main() {
  Future<MessageNeeds> analyze(
    String message, {
    String? followUp,
    CompanyTickerResolver? resolver,
  }) => MessageNeedsAnalyzer.analyze(
    message: message,
    summary: heldSummary,
    followUpTicker: followUp,
    tickerResolver: resolver,
  );

  group('adversarial: a ticker mentioned in passing is not a data request', () {
    for (final message in const [
      '¿Qué es un ETF, como SPY?',
      '¿Qué es un split, como el de NVDA?',
      'Explicame qué significa P/E, por ejemplo en AAPL',
      '¿Cómo funciona un ETF como QQQ?',
    ]) {
      test(
        '"$message" → conceptual, no tickers, no market data, no paywall',
        () async {
          final needs = await analyze(message, followUp: 'MSFT');
          expect(needs.isConceptual, isTrue);
          expect(needs.tickers, isEmpty);
          expect(needs.needsMarketData, isFalse);
          expect(needs.usedFollowUpTicker, isFalse);
          expect(
            UnifiedAccessPolicy.paywallFor(needs, SubscriptionTier.free),
            isNull,
          );
        },
      );
    }

    test('"¿qué es un bono de bajo riesgo?" is conceptual too', () async {
      expect(
        (await analyze('¿Qué es un bono de bajo riesgo?')).isConceptual,
        isTrue,
      );
    });

    test('"qué es" about their own data is NOT conceptual', () async {
      final needs = await analyze(
        '¿Qué es lo que tiene más riesgo en mi portfolio?',
      );
      expect(needs.isConceptual, isFalse);
      expect(needs.mentionsOwnPortfolio, isTrue);
    });

    test('"qué es" + a price question is NOT conceptual', () async {
      final needs = await analyze('¿qué es lo que pasó con el precio de AAPL?');
      expect(needs.isConceptual, isFalse);
      expect(needs.tickers, ['AAPL']);
    });
  });

  group('holding decides free vs. market data', () {
    test('a held ticker is free', () async {
      final needs = await analyze('¿A cuánto está AAPL?');
      expect(needs.tickers, ['AAPL']);
      expect(needs.heldTickers, {'AAPL'});
      expect(needs.needsMarketData, isFalse);
      expect(
        UnifiedAccessPolicy.paywallFor(needs, SubscriptionTier.free),
        isNull,
      );
    });

    test('a ticker they do not hold needs market data (Premium)', () async {
      final needs = await analyze('¿A cuánto está TSLA?');
      expect(needs.externalTickers, {'TSLA'});
      expect(
        UnifiedAccessPolicy.paywallFor(needs, SubscriptionTier.free),
        PaywallReason.marketDataLocked,
      );
      expect(
        UnifiedAccessPolicy.paywallFor(needs, SubscriptionTier.premium),
        isNull,
      );
    });

    test('a comparison with one external ticker needs market data', () async {
      final needs = await analyze('comparame AAPL y TSLA');
      expect(needs.heldTickers, {'AAPL'});
      expect(needs.externalTickers, {'TSLA'});
    });

    test('"the market" uses the SPY proxy and needs market data', () async {
      final needs = await analyze('¿Cómo está el mercado hoy?');
      expect(needs.marketProxyTicker, 'SPY');
      expect(needs.needsMarketData, isTrue);
    });

    test('B5: a market-wide superlative does NOT fetch the proxy', () async {
      final needs = await analyze('¿Qué acción subió más hoy en el mercado?');
      expect(needs.marketProxyTicker, isNull);
      expect(needs.tickers, isEmpty);
      expect(needs.needsMarketData, isFalse);
    });
  });

  group('news gating uses explicit requests only', () {
    test('an explicit news request needs Gold', () async {
      final needs = await analyze('¿Qué noticias hay de AAPL?');
      expect(needs.isExplicitNewsRequest, isTrue);
      expect(
        UnifiedAccessPolicy.paywallFor(needs, SubscriptionTier.premium),
        PaywallReason.newsRequiresGold,
      );
      expect(
        UnifiedAccessPolicy.paywallFor(needs, SubscriptionTier.gold),
        isNull,
      );
    });

    test(
      '"esta semana" is not a news request (no paywall for a held ticker)',
      () async {
        final needs = await analyze('¿Cómo le fue a AAPL esta semana?');
        expect(needs.isNewsQuery, isTrue, reason: 'broad detector, kept as-is');
        expect(needs.isExplicitNewsRequest, isFalse);
        expect(
          UnifiedAccessPolicy.paywallFor(needs, SubscriptionTier.free),
          isNull,
        );
      },
    );
  });

  group('position_periods for all holdings only when needed (B4)', () {
    test(
      'a superlative over their holdings in a window needs all of them',
      () async {
        final needs = await analyze(
          '¿Cuál de mis acciones subió más esta semana?',
        );
        expect(needs.needsAllPositionPeriods, isTrue);
        expect(needs.tickers, isEmpty);
      },
    );

    test('"¿cómo está mi cartera?" does not', () async {
      expect(
        (await analyze('¿Cómo está mi cartera?')).needsAllPositionPeriods,
        isFalse,
      );
    });
  });

  group('follow-up ticker from stored turns', () {
    test('"¿y las noticias?" continues the previous ticker', () async {
      final needs = await analyze('¿Y las noticias?', followUp: 'AAPL');
      expect(needs.tickers, ['AAPL']);
      expect(needs.usedFollowUpTicker, isTrue);
    });

    test('"¿y este año?" continues the previous ticker', () async {
      expect((await analyze('¿y este año?', followUp: 'NVDA')).tickers, [
        'NVDA',
      ]);
    });

    test('"¿por qué?" continues the previous ticker', () async {
      expect((await analyze('¿Por qué?', followUp: 'NVDA')).tickers, ['NVDA']);
    });

    test('"hola" does NOT re-fetch the previous ticker', () async {
      expect(
        (await analyze('Hola, gracias', followUp: 'AAPL')).tickers,
        isEmpty,
      );
    });

    test(
      'a question about their own portfolio does NOT carry the ticker',
      () async {
        expect(
          (await analyze(
            '¿Y cómo va mi cartera este año?',
            followUp: 'AAPL',
          )).tickers,
          isEmpty,
        );
      },
    );

    test('an explicit ticker in the message always wins', () async {
      expect(
        (await analyze('¿Y las noticias de MSFT?', followUp: 'AAPL')).tickers,
        ['MSFT'],
      );
    });
  });

  group('company name resolution', () {
    CompanyTickerResolver resolver(
      Map<String, List<SymbolSearchResult>> results,
    ) => CompanyTickerResolver(repository: FakeSymbolSearchRepository(results));

    test('"¿cómo viene Apple?" resolves to AAPL', () async {
      final needs = await analyze(
        '¿Cómo viene Apple?',
        resolver: resolver({
          'Apple': const [
            SymbolSearchResult(
              symbol: 'AAPL',
              description: 'APPLE INC',
              type: 'Common Stock',
            ),
          ],
        }),
      );
      expect(needs.tickers, ['AAPL']);
    });

    test(
      'an ambiguous name asks instead of guessing (and no follow-up)',
      () async {
        final needs = await analyze(
          '¿Cómo viene Meta?',
          followUp: 'AAPL',
          resolver: resolver({
            'Meta': const [
              SymbolSearchResult(
                symbol: 'META',
                description: 'META PLATFORMS',
                type: 'Common Stock',
              ),
              SymbolSearchResult(
                symbol: 'MMTA',
                description: 'META MATERIALS',
                type: 'Common Stock',
              ),
            ],
          }),
        );
        expect(needs.tickers, isEmpty);
        expect(needs.ambiguousCandidate, 'Meta');
        expect(needs.ambiguousMatches, hasLength(2));
      },
    );

    test('conceptual questions never hit the symbol search', () async {
      final repo = FakeSymbolSearchRepository(const {});
      await analyze(
        '¿Qué es Apple Pay?',
        resolver: CompanyTickerResolver(repository: repo),
      );
      expect(repo.queries, isEmpty);
    });
  });
}
