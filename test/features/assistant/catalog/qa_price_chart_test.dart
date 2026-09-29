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
import 'package:portfolio_assistant/features/assistant/catalog/widgets/qa_price_chart.dart';
import 'package:portfolio_assistant/features/assistant/services/company_brand_loader.dart';
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

class _NoBrandRepo implements CompanyBrandRepository {
  @override
  Future<CompanyBrand?> getBrand(String ticker) async => null;
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
    ValueChanged<String>? onFollowUp,
    double weightPct = 0,
  }) async {
    haptics = [];
    finished = false;
    await tester.binding.setSurfaceSize(const Size(390, 844));
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
            PortyHapticsService(
              enabled: true,
              performer: (p) async => haptics.add(p),
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: QaFollowUpScope(
              onFollowUp: onFollowUp ?? (_) {},
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
                  child: QaPriceChart(
                    ticker: 'AAPL',
                    initialRange: initialRange,
                    weightPct: weightPct,
                    fallback: const Text('FALLBACK'),
                    onFinished: () => finished = true,
                  ),
                ),
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

  String hero(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(QaPriceChart.heroKey)).data!;

  final chartFinder = find.byWidgetPredicate(
    (w) => w is CustomPaint && w.painter is PriceLinePainter,
  );

  testWidgets('renders the line with range summary and finishes its reveal', (
    tester,
  ) async {
    final repo = _FakeQuoteRepository(daily: _daily);
    await pump(tester, repo);

    // 1M = últimos 30 días: 129 → 159.
    expect(find.text('AAPL'), findsOneWidget);
    expect(hero(tester), '\$159.00');
    expect(find.text('\$30.00 (23.26%)'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_drop_up_rounded), findsOneWidget);
    expect(find.textContaining('Último mes'), findsOneWidget);
    // Stats del rango, calculados de las velas cargadas.
    expect(find.text('Inicio'), findsOneWidget);
    // Serie siempre en alza: inicio = mínimo ($129), máximo = último.
    expect(find.text('\$129.00'), findsNWidgets(2));
    expect(find.text('Máximo'), findsOneWidget);
    expect(find.text('Mínimo'), findsOneWidget);
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

      final box = tester.getRect(chartFinder);
      final gesture = await tester.startGesture(
        box.centerLeft + const Offset(2, 0),
      );
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      await gesture.moveTo(box.centerLeft + const Offset(1, 0));
      await tester.pump();

      // Primer punto del rango 1M: 26 ago 2026, $129.
      expect(find.text('\$129.00 · 26 ago 2026'), findsOneWidget);
      expect(hero(tester), '\$129.00');
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
      expect(hero(tester), '\$159.00');
    },
  );

  testWidgets('weight tag, high/low references and follow-ups', (tester) async {
    final sent = <String>[];
    await pump(
      tester,
      _FakeQuoteRepository(daily: _daily),
      weightPct: 12.4,
      onFollowUp: sent.add,
    );
    expect(find.text('12% de tu portfolio'), findsOneWidget);
    expect(painter(tester).showReferences, isTrue);

    // Follow-ups: sin "Gráfico" (es esta card), tres como máximo.
    expect(find.text('Gráfico'), findsNothing);
    expect(find.text('Noticias'), findsOneWidget);
    expect(find.text('Earnings'), findsOneWidget);
    expect(find.text('Fundamentals'), findsOneWidget);
    expect(find.text('vs. S&P 500'), findsNothing);

    await tester.tap(find.text('Noticias'));
    await tester.pumpAndSettle();
    expect(sent, ['¿Qué noticias hay de AAPL?']);
  });

  group('catalog integration', () {
    final catalog = AssistantCatalog.build();

    testWidgets(
      'without data the catalog widget falls back to QaTickerMove content '
      'when the model sent an explicit period',
      (tester) async {
        final item = catalog.items.firstWhere((i) => i.name == 'QaPriceChart');
        // Sin ProviderScope no hay loader → mismo camino que "sin datos".
        await pumpCatalogItemExample(tester, catalog, item);
        await tester.pumpAndSettle();

        expect(find.text('NVDA'), findsOneWidget);
        expect(find.text('Últimos 7 días'), findsOneWidget); // QaTickerMove
        expect(find.text('\$2.59 (2.10%)'), findsOneWidget);
        expect(find.text('Inicio'), findsOneWidget);
        // Día / Semana / Mes del payload, como chips.
        expect(find.text('Semana'), findsOneWidget);
        expect(find.text('5.80%'), findsOneWidget);
        // Sin QaFollowUpScope no hay follow-ups.
        expect(find.text('Noticias'), findsNothing);
      },
    );
  });
}
