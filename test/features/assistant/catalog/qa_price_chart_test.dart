import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/features/assistant/catalog/portfolio_qa_catalog.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/qa_price_chart.dart';
import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/explore_prompt_rules.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/assistant/services/price_chart_data_loader.dart';

import '../../../helpers/genui_test_helpers.dart';

class _FakeQuoteRepository implements QuoteRepository {
  _FakeQuoteRepository({this.daily, this.intraday = const []});

  final List<PriceCandle>? daily;
  final List<PriceCandle> intraday;
  int dailyCalls = 0;
  int intradayCalls = 0;

  @override
  Future<Either<HttpError, double>> getCurrentPrice(String ticker) async =>
      const Right(1);

  @override
  Future<Either<HttpError, List<PriceCandle>>> getHistoricalDaily(
    String ticker,
  ) async {
    dailyCalls++;
    return daily == null ? Left(HttpError(code: 'x')) : Right(daily!);
  }

  @override
  Future<List<PriceCandle>> getIntradayCandles(String ticker) async {
    intradayCalls++;
    return intraday;
  }
}

/// 60 cierres diarios subiendo de 100 a 159 (último: 25 sep 2026).
final _daily = [
  for (var i = 0; i < 60; i++)
    PriceCandle(
      date: DateTime(2026, 9, 25).subtract(Duration(days: 59 - i)),
      close: 100.0 + i,
    ),
];

/// Sesión intradía bajando (para verificar que el color sigue al rango).
final _intraday = [
  for (var i = 0; i < 10; i++)
    PriceCandle(date: DateTime(2026, 9, 25, 10, 30 + i * 5), close: 160.0 - i),
];

void main() {
  late List<PortyHapticPattern> haptics;
  late bool finished;

  Future<void> pump(
    WidgetTester tester,
    _FakeQuoteRepository repo, {
    PriceChartRange initialRange = PriceChartRange.month,
  }) async {
    haptics = [];
    finished = false;
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          priceChartDataLoaderProvider.overrideWithValue(
            PriceChartDataLoader(repo),
          ),
          portyHapticsServiceProvider.overrideWithValue(
            PortyHapticsService(
              enabled: true,
              performer: (p) async => haptics.add(p),
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: QaPriceChart(
                ticker: 'AAPL',
                initialRange: initialRange,
                fallback: const Text('FALLBACK'),
                onFinished: () => finished = true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  PriceLinePainter painter(WidgetTester tester) =>
      tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((c) => c.painter)
          .whereType<PriceLinePainter>()
          .single;

  testWidgets('renders the line with range summary and finishes its reveal', (
    tester,
  ) async {
    final repo = _FakeQuoteRepository(daily: _daily);
    await pump(tester, repo);

    // 1M = últimos 30 días: 129 → 159.
    expect(find.text('AAPL'), findsOneWidget);
    expect(find.text('\$159.00'), findsOneWidget);
    expect(find.textContaining('+\$30.00 (+23.26%)'), findsOneWidget);
    expect(find.textContaining('Último mes'), findsOneWidget);
    expect(painter(tester).values.first, 129);
    expect(painter(tester).color, isNot(painter(tester).color.withAlpha(0)));
    expect(finished, isTrue);
    expect(find.text('FALLBACK'), findsNothing);
  });

  testWidgets('switching periods refetches client-side and caches each range', (
    tester,
  ) async {
    final repo = _FakeQuoteRepository(daily: _daily, intraday: _intraday);
    await pump(tester, repo);
    expect(repo.dailyCalls, 1);

    await tester.tap(find.text('1D'));
    await tester.pumpAndSettle();
    expect(repo.intradayCalls, 1);
    expect(painter(tester).values, [for (final c in _intraday) c.close]);
    expect(find.textContaining('Hoy'), findsOneWidget);

    await tester.tap(find.text('1W'));
    await tester.pumpAndSettle();
    expect(repo.dailyCalls, 2);

    // Volver a rangos ya vistos no refetchea.
    await tester.tap(find.text('1D'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1M'));
    await tester.pumpAndSettle();
    expect(repo.intradayCalls, 1);
    expect(repo.dailyCalls, 2);
  });

  testWidgets('line color follows the sign of the selected range', (
    tester,
  ) async {
    final repo = _FakeQuoteRepository(daily: _daily, intraday: _intraday);
    await pump(tester, repo);
    final upColor = painter(tester).color;

    await tester.tap(find.text('1D'));
    await tester.pumpAndSettle();
    expect(painter(tester).color, isNot(upColor));
  });

  group('single fallback path', () {
    testWidgets('no history for the ticker → QaTickerSnapshot/Move content', (
      tester,
    ) async {
      await pump(tester, _FakeQuoteRepository(daily: []));
      expect(find.text('FALLBACK'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is PriceLinePainter,
        ),
        findsNothing,
      );
      expect(finished, isTrue);
    });

    testWidgets('failed history fetch → same fallback', (tester) async {
      await pump(tester, _FakeQuoteRepository());
      expect(find.text('FALLBACK'), findsOneWidget);
      expect(finished, isTrue);
    });

    testWidgets('failed Yahoo intraday on an initial 1D → same fallback', (
      tester,
    ) async {
      await pump(
        tester,
        _FakeQuoteRepository(daily: _daily),
        initialRange: PriceChartRange.day,
      );
      expect(find.text('FALLBACK'), findsOneWidget);
      expect(finished, isTrue);
    });

    testWidgets(
      'a later period without data keeps the chart and tabs, showing an '
      'inline empty state for that range only',
      (tester) async {
        await pump(tester, _FakeQuoteRepository(daily: _daily));
        await tester.tap(find.text('1D'));
        await tester.pumpAndSettle();

        expect(find.text('FALLBACK'), findsNothing);
        expect(find.text('Sin datos para este período'), findsOneWidget);
        expect(find.text('1M'), findsOneWidget);

        await tester.tap(find.text('1M'));
        await tester.pumpAndSettle();
        expect(find.text('Sin datos para este período'), findsNothing);
      },
    );
  });

  testWidgets(
    'scrub shows a tooltip with exact price + date, ticks a haptic per '
    'point crossed, and restores the range summary on release',
    (tester) async {
      await pump(tester, _FakeQuoteRepository(daily: _daily));
      haptics.clear();

      final chart = find.byType(CustomPaint).last;
      final box = tester.getRect(chart);
      final gesture = await tester.startGesture(
        box.centerLeft + const Offset(2, 0),
      );
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      await gesture.moveTo(box.centerLeft + const Offset(1, 0));
      await tester.pump();

      // Primer punto del rango 1M: 26 ago 2026, $129.
      expect(find.text('\$129.00 · 26 ago 2026'), findsOneWidget);
      expect(painter(tester).scrubIndex, 0);
      expect(find.textContaining('Último mes'), findsNothing);
      expect(find.textContaining('desde el inicio'), findsOneWidget);
      expect(haptics, isNotEmpty);
      expect(haptics.toSet(), {PortyHapticPattern.selection});

      await gesture.up();
      await tester.pump();
      expect(find.textContaining(' · 26 ago 2026'), findsNothing);
      expect(painter(tester).scrubIndex, isNull);
      expect(find.textContaining('Último mes'), findsOneWidget);
      expect(find.text('\$159.00'), findsOneWidget);
    },
  );

  group('catalog integration', () {
    final catalog = PortfolioQaCatalog.buildFor(
      AssistantMode.explore,
      explorePromptRules,
    );

    testWidgets(
      'without data the catalog widget falls back to QaTickerMove content '
      'when the model sent an explicit period',
      (tester) async {
        final item = catalog.items.firstWhere((i) => i.name == 'QaPriceChart');
        // Sin ProviderScope no hay loader → mismo camino que "sin datos".
        await pumpCatalogItemExample(tester, catalog, item);
        await tester.pumpAndSettle();

        expect(find.text('NVDA'), findsOneWidget);
        expect(find.text('últimos 7 días'), findsOneWidget); // QaTickerMove
        expect(find.text('-2.1%'), findsOneWidget);
      },
    );
  });
}
