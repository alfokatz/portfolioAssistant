import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/company_brand.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/repositories/company_brand_repository.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/features/assistant/catalog/assistant_catalog.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_follow_up_scope.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/qa_compare_chart.dart';
import 'package:portfolio_assistant/features/assistant/services/company_brand_loader.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/assistant/services/price_chart_data_loader.dart';

import '../../../helpers/genui_test_helpers.dart';

class _FakeQuoteRepository implements QuoteRepository {
  _FakeQuoteRepository(this.daily);

  /// ticker → cierres diarios; ausente = falla.
  final Map<String, List<PriceCandle>> daily;
  final calls = <String>[];

  @override
  Future<Either<HttpError, double>> getCurrentPrice(String ticker) async =>
      const Right(1);

  @override
  Future<Either<HttpError, List<PriceCandle>>> getHistoricalDaily(
    String ticker,
  ) async {
    calls.add(ticker);
    final list = daily[ticker];
    return list == null ? Left(HttpError(code: 'x')) : Right(list);
  }

  @override
  Future<List<PriceCandle>> getIntradayCandles(String ticker) async => [];
}

class _NoBrandRepo implements CompanyBrandRepository {
  @override
  Future<CompanyBrand?> getBrand(String ticker) async => null;
}

/// 60 cierres diarios lineales desde [start] con paso [step] (último día:
/// 25 sep 2026).
List<PriceCandle> _series(double start, double step) => [
  for (var i = 0; i < 60; i++)
    PriceCandle(
      date: DateTime(2026, 9, 25).subtract(Duration(days: 59 - i)),
      close: start + step * i,
    ),
];

void main() {
  late bool finished;

  Future<void> pump(
    WidgetTester tester,
    _FakeQuoteRepository repo, {
    List<String> tickers = const ['AAPL', 'MSFT'],
    PriceChartRange initialRange = PriceChartRange.month,
    ValueChanged<String>? onFollowUp,
  }) async {
    finished = false;
    await tester.binding.setSurfaceSize(const Size(390, 844));
    final chart = Padding(
      padding: const EdgeInsets.all(16),
      child: QaCompareChart(
        tickers: tickers,
        initialRange: initialRange,
        fallback: const Text('FALLBACK'),
        onFinished: () => finished = true,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          companyBrandLoaderProvider.overrideWithValue(
            CompanyBrandLoader(_NoBrandRepo()),
          ),
          priceChartDataLoaderProvider.overrideWithValue(
            PriceChartDataLoader(repo),
          ),
          portyHapticsServiceProvider.overrideWithValue(
            PortyHapticsService(enabled: false, performer: (_) async {}),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body:
                onFollowUp == null
                    ? chart
                    : QaFollowUpScope(onFollowUp: onFollowUp, child: chart),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  CompareLinePainter painter(WidgetTester tester) =>
      tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((c) => c.painter)
          .whereType<CompareLinePainter>()
          .single;

  group('CompareSeries.align', () {
    test('normalizes each ticker to % from the first common day', () {
      final s =
          CompareSeries.align(
            ['A', 'B'],
            {
              'A': _series(100, 1).sublist(30),
              'B': _series(50, -0.5).sublist(30),
            },
          )!;
      expect(s.length, 30);
      expect(s.pctByTicker['A']!.first, 0);
      expect(s.pctByTicker['B']!.first, 0);
      expect(s.pctByTicker['A']!.last, closeTo((159 / 130 - 1) * 100, 1e-9));
      expect(s.pctByTicker['B']!.last, lessThan(0));
      expect(s.missing, isEmpty);
    });

    test('keeps only the days both tickers traded', () {
      final b = _series(50, 1)..removeAt(40);
      final s =
          CompareSeries.align(['A', 'B'], {'A': _series(100, 1), 'B': b})!;
      expect(s.length, 59);
    });

    test('a failing ticker is reported as missing; all failing → null', () {
      final s =
          CompareSeries.align(['A', 'B'], {'A': _series(1, 1), 'B': null})!;
      expect(s.pctByTicker.keys, ['A']);
      expect(s.missing, {'B'});
      expect(CompareSeries.align(['A', 'B'], {'A': null, 'B': []}), isNull);
    });
  });

  testWidgets('one line per ticker, legend with final %, and reveal', (
    tester,
  ) async {
    final repo = _FakeQuoteRepository({
      'AAPL': _series(100, 1),
      'MSFT': _series(200, -1),
    });
    await pump(tester, repo);

    expect(painter(tester).lines, hasLength(2));
    expect(find.text('AAPL vs MSFT'), findsOneWidget);
    expect(find.textContaining('Último mes'), findsOneWidget);
    // 1M: AAPL 129 → 159, MSFT 171 → 141.
    expect(find.text('23.26%'), findsOneWidget);
    expect(find.text('17.54%'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_drop_down_rounded), findsOneWidget);
    expect(finished, isTrue);
    expect(find.text('FALLBACK'), findsNothing);
    // Sin 1D ni "Todo" en el comparativo.
    expect(find.text('1D'), findsNothing);
    expect(find.text('Todo'), findsNothing);
  });

  testWidgets('switching range refetches every ticker once and caches it', (
    tester,
  ) async {
    final repo = _FakeQuoteRepository({
      'AAPL': _series(100, 1),
      'MSFT': _series(200, -1),
    });
    await pump(tester, repo);
    expect(repo.calls, ['AAPL', 'MSFT']);

    await tester.tap(find.text('1S'));
    await tester.pumpAndSettle();
    expect(repo.calls, hasLength(4));
    expect(find.textContaining('Última semana'), findsOneWidget);

    await tester.tap(find.text('1M'));
    await tester.pumpAndSettle();
    expect(repo.calls, hasLength(4));
  });

  testWidgets('one ticker failing keeps the chart for the others', (
    tester,
  ) async {
    await pump(tester, _FakeQuoteRepository({'AAPL': _series(100, 1)}));
    expect(painter(tester).lines, hasLength(1));
    expect(find.text('Sin datos'), findsOneWidget);
    expect(find.text('FALLBACK'), findsNothing);
    expect(finished, isTrue);
  });

  testWidgets('all tickers failing → fallback content', (tester) async {
    await pump(tester, _FakeQuoteRepository({}));
    expect(find.text('FALLBACK'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is CompareLinePainter,
      ),
      findsNothing,
    );
    expect(finished, isTrue);
  });

  testWidgets('an unsupported initial range (1D) starts at 1W', (tester) async {
    await pump(
      tester,
      _FakeQuoteRepository({'AAPL': _series(100, 1), 'MSFT': _series(9, 1)}),
      initialRange: PriceChartRange.day,
    );
    expect(find.textContaining('Última semana'), findsOneWidget);
  });

  testWidgets('scrub shows the date and each ticker % at that point', (
    tester,
  ) async {
    await pump(
      tester,
      _FakeQuoteRepository({'AAPL': _series(100, 1), 'MSFT': _series(200, -1)}),
    );
    final chart = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is CompareLinePainter,
    );
    final box = tester.getRect(chart);
    final gesture = await tester.startGesture(
      box.centerLeft + const Offset(2, 0),
    );
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    await gesture.moveTo(box.centerLeft + const Offset(1, 0));
    await tester.pump();

    expect(find.text('26 ago 2026'), findsOneWidget);
    expect(painter(tester).scrubIndex, 0);
    // En el primer punto ambos están en 0%.
    expect(find.text('0.00%'), findsNWidgets(2));

    await gesture.up();
    await tester.pump();
    expect(find.text('26 ago 2026'), findsNothing);
    expect(find.text('23.26%'), findsOneWidget);
  });

  testWidgets('follow-ups only with a scope, and they send the question', (
    tester,
  ) async {
    final repo = _FakeQuoteRepository({
      'AAPL': _series(100, 1),
      'MSFT': _series(200, -1),
    });
    await pump(tester, repo);
    expect(find.text('Noticias de AAPL'), findsNothing);

    final sent = <String>[];
    await pump(tester, repo, onFollowUp: sent.add);
    expect(find.text('Noticias de AAPL'), findsOneWidget);
    expect(find.text('Noticias de MSFT'), findsOneWidget);
    expect(find.text('Fundamentals de AAPL'), findsOneWidget);
    await tester.tap(find.text('Noticias de AAPL'));
    await tester.pumpAndSettle();
    expect(sent, ['¿Qué noticias hay de AAPL?']);
  });

  group('catalog integration', () {
    final catalog = AssistantCatalog.build();
    final item = catalog.items.firstWhere((i) => i.name == 'QaCompareChart');

    testWidgets('without a loader the card shows the model values', (
      tester,
    ) async {
      await pumpCatalogItemExample(tester, catalog, item);
      await tester.pumpAndSettle();
      expect(find.text('AAPL vs MSFT'), findsOneWidget);
      expect(find.text('1.96%'), findsOneWidget);
      expect(find.text('1.39%'), findsOneWidget);
      // MSFT (+1,39%) lidera.
      expect(find.text('Lidera'), findsOneWidget);
    });

    testWidgets('no tickers and no items → still renders, no crash', (
      tester,
    ) async {
      await tester.pumpWidget(
        genuiTestApp(
          child: Builder(
            builder:
                (context) => item.widgetBuilder(
                  catalogContextFor(
                    buildContext: context,
                    component: {
                      'id': 'c',
                      'component': 'QaCompareChart',
                      'tickers': <String>[],
                      'initialRange': 'ZZ',
                    },
                    catalog: catalog,
                  ),
                ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('No hay histórico de precios'),
        findsOneWidget,
      );
    });
  });
}
