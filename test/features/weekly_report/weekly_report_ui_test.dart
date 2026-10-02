import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/ai_proxy_client.dart';
import 'package:portfolio_assistant/features/weekly_report/data/weekly_report_generator.dart';
import 'package:portfolio_assistant/features/weekly_report/data/weekly_report_input_builder.dart';
import 'package:portfolio_assistant/features/weekly_report/data/weekly_report_repository.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/report_week.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/weekly_report.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/weekly_report_claim.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/weekly_report_draft.dart';
import 'package:portfolio_assistant/features/weekly_report/nav/weekly_report_router.dart';
import 'package:portfolio_assistant/features/weekly_report/providers/weekly_report_controller.dart';
import 'package:portfolio_assistant/features/weekly_report/view/weekly_report_card.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/fade_slide_in.dart';

import 'weekly_report_fixtures.dart';

class _NoStore implements WeeklyReportStore {
  @override
  Future<WeeklyReportClaim> claim(ReportWeek week) async =>
      const ClaimUnavailable();
  @override
  Future<bool> complete(ReportWeek week, Map<String, Object?> payload) async =>
      true;
  @override
  Future<void> fail(ReportWeek week) async {}
}

class _NoQuotes implements QuoteRepository {
  @override
  Future<Either<HttpError, double>> getCurrentPrice(String t) =>
      throw UnimplementedError();
  @override
  Future<Either<HttpError, List<PriceCandle>>> getHistoricalDaily(String t) =>
      throw UnimplementedError();
  @override
  Future<List<PriceCandle>> getIntradayCandles(String t) =>
      throw UnimplementedError();
}

/// Muestra un estado fijo y deja cambiarlo (sin red ni Supabase).
class FixedWeeklyReportController extends WeeklyReportController {
  FixedWeeklyReportController(WeeklyReportState initial)
    : super(
        store: _NoStore(),
        builder: WeeklyReportInputBuilder(quotes: _NoQuotes()),
        generator: WeeklyReportGenerator(
          config: AiProxyConfig.fixed(Uri.parse('https://x/ai-chat'), 'jwt'),
          model: 'gpt-4.1-mini',
        ),
        tier: () => SubscriptionTier.gold,
      ) {
    state = initial;
  }

  void emit(WeeklyReportState next) => state = next;

  @override
  Future<void> ensureFor(
    List<Position> lots, {
    List<ClosedPosition> closed = const [],
  }) async {}
}

WeeklyReport fullReport({bool courtesy = false}) => WeeklyReport.compose(
  input: fixtureInput(),
  draft: const WeeklyReportDraft(
    headline: 'Apple empujó tu cartera en una semana tranquila',
    movers: [
      DraftMover(
        ticker: 'AAPL',
        why: 'Coincidió con las buenas reservas del nuevo iPhone.',
        newsId: 'n1',
      ),
      DraftMover(
        ticker: 'MSFT',
        why: 'Bajó en una semana en la que la UE abrió una investigación.',
        newsId: 'n2',
      ),
    ],
    news: [
      DraftNews(
        newsId: 'n2',
        take: 'Una investigación así suele llevar meses antes de definirse.',
      ),
    ],
    investors: [
      DraftInvestor(
        itemId: 'i2',
        take:
            'Según CNBC, Bill Ackman ve a Microsoft como su principal apuesta '
            'en inteligencia artificial. Tenés MSFT en tu cartera.',
      ),
      DraftInvestor(
        itemId: 'i1',
        take:
            'Berkshire Hathaway, la firma de Warren Buffett, informó compras '
            'de acciones de Lennar.',
      ),
    ],
    learn: DraftLearn(
      topic: 'earnings',
      concept: 'Qué es un reporte de resultados',
      text:
          'Cada trimestre las empresas cuentan cuánto vendieron y ganaron. '
          'El mercado lo compara con lo que esperaba.',
    ),
    followUpQuestion: '¿Qué espera el mercado de los resultados de MSFT?',
    closing: 'La semana que viene presenta resultados Microsoft.',
  ),
  variant: WeeklyReportVariant.full,
  courtesy: courtesy,
);

WeeklyReport numbersReport(WeeklyReportVariant variant) => WeeklyReport.compose(
  input: fixtureInput(),
  draft: WeeklyReportDraft.empty,
  variant: variant,
);

final _lots = [
  Position(
    id: '1',
    ticker: 'AAPL',
    quantity: 10,
    purchasePrice: 50,
    purchaseDate: DateTime(2026, 1, 5),
  ),
];

/// App con la tarjeta en "/" y la pantalla del informe como ruta.
Widget reportApp(
  FixedWeeklyReportController controller, {
  bool benchmarkAllowed = true,
  bool reduceMotion = false,
  bool openScreen = false,
  Brightness brightness = Brightness.light,
  List<PortyHapticPattern>? haptics,
  // Para screenshots con textos reales (EasyLocalization).
  List<LocalizationsDelegate<Object?>>? localizationsDelegates,
  List<Locale>? supportedLocales,
  Locale? locale,
}) {
  final container = ProviderContainer();
  final theme =
      brightness == Brightness.light
          ? container.read(themeDataLightProvider)
          : container.read(themeDataDarkProvider);
  final router = GoRouter(
    initialLocation: openScreen ? WeeklyReportRouter.path : '/',
    routes: [
      GoRoute(
        path: '/',
        builder:
            (_, __) => Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: WeeklyReportCard(lots: _lots),
                ),
              ),
            ),
      ),
      WeeklyReportRouter.getRoute(),
    ],
  );
  return ProviderScope(
    overrides: [
      weeklyReportControllerProvider.overrideWith((ref) => controller),
      weeklyReportBenchmarkAllowedProvider.overrideWithValue(benchmarkAllowed),
      portyHapticsServiceProvider.overrideWithValue(
        PortyHapticsService(
          enabled: true,
          performer: (p) async => haptics?.add(p),
        ),
      ),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      theme: theme,
      localizationsDelegates: localizationsDelegates,
      supportedLocales: supportedLocales ?? const [Locale('en', 'US')],
      locale: locale,
      builder:
          (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: reduceMotion),
            child: child!,
          ),
    ),
  );
}

WeeklyReportState ready(
  WeeklyReport r, {
  bool seen = false,
  bool fresh = false,
}) => WeeklyReportState(
  status: WeeklyReportStatus.ready,
  report: r,
  seen: seen,
  freshlyGenerated: fresh,
);

void main() {
  group('Home card', () {
    testWidgets('while Porty writes, it says so; then shows the headline and '
        'the three figures', (tester) async {
      final controller = FixedWeeklyReportController(
        const WeeklyReportState(
          status: WeeklyReportStatus.loading,
          generating: true,
        ),
      );
      final haptics = <PortyHapticPattern>[];
      await tester.pumpWidget(reportApp(controller, haptics: haptics));
      await tester.pump();
      expect(find.text('weekly_report_preparing'), findsOneWidget);

      controller.emit(ready(fullReport(), fresh: true));
      await tester.pumpAndSettle();
      expect(
        find.text('Apple empujó tu cartera en una semana tranquila'),
        findsOneWidget,
      );
      expect(find.text('+2.5%'), findsOneWidget); // cartera
      expect(find.text('AAPL +10.0%'), findsOneWidget); // lo que más movió
      // Porty terminó con la Home en pantalla: un toque.
      expect(haptics, [PortyHapticPattern.light]);
    });

    testWidgets('Free with the tasting used: numbers, no S&P, Gold line', (
      tester,
    ) async {
      await tester.pumpWidget(
        reportApp(
          FixedWeeklyReportController(
            ready(numbersReport(WeeklyReportVariant.numbersLocked)),
          ),
          benchmarkAllowed: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('weekly_report_fallback_up'), findsOneWidget);
      expect(find.text('weekly_report_vs_sp500'), findsNothing);
      expect(find.text('weekly_report_locked_title'), findsOneWidget);
    });

    testWidgets('no positions: no card at all', (tester) async {
      await tester.pumpWidget(
        reportApp(FixedWeeklyReportController(const WeeklyReportState())),
      );
      await tester.pumpAndSettle();
      expect(find.text('weekly_report_title'), findsNothing);
    });

    testWidgets('tapping opens the report', (tester) async {
      await tester.pumpWidget(
        reportApp(FixedWeeklyReportController(ready(fullReport()))),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('weekly_report_title'));
      await tester.pumpAndSettle();
      expect(find.text('weekly_report_screen_title'), findsOneWidget);
      expect(find.text('weekly_report_numbers_section'), findsOneWidget);
    });
  });

  group('Report screen', () {
    testWidgets('full report: every section, source links and disclaimer', (
      tester,
    ) async {
      await tester.pumpWidget(
        reportApp(
          FixedWeeklyReportController(ready(fullReport(courtesy: true))),
          openScreen: true,
        ),
      );
      await tester.pumpAndSettle();
      for (final key in [
        'weekly_report_courtesy', // en el encabezado: primero
        'weekly_report_numbers_section',
        'weekly_report_news_section',
        'weekly_report_investors_section',
        'weekly_report_upcoming_section',
        'weekly_report_learn_section',
        'weekly_report_ask_porty',
      ]) {
        await tester.scrollUntilVisible(
          find.text(key),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text(key), findsOneWidget, reason: key);
      }
      await tester.scrollUntilVisible(
        find.text('weekly_report_disclaimer'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('weekly_report_locked_title'), findsNothing);
      // Links tocables de 44 px como mínimo.
      for (final link in tester.widgetList<Semantics>(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.link == true,
        ),
      )) {
        expect(
          tester.getSize(find.byWidget(link)).height,
          greaterThanOrEqualTo(44),
        );
      }
    });

    testWidgets('numbers only: Gold teaser instead of Porty sections; Free '
        'sees the S&P comparison locked', (tester) async {
      await tester.pumpWidget(
        reportApp(
          FixedWeeklyReportController(
            ready(numbersReport(WeeklyReportVariant.numbersLocked)),
          ),
          benchmarkAllowed: false,
          openScreen: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('weekly_report_locked_title'), findsOneWidget);
      expect(find.text('weekly_report_sp500_locked'), findsOneWidget);
      expect(find.text('weekly_report_news_section'), findsNothing);
      expect(find.text('weekly_report_investors_section'), findsNothing);
    });

    testWidgets('generation failed (has access): a note, no teaser', (
      tester,
    ) async {
      await tester.pumpWidget(
        reportApp(
          FixedWeeklyReportController(
            ready(numbersReport(WeeklyReportVariant.numbersUnavailable)),
          ),
          openScreen: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('weekly_report_unavailable'), findsOneWidget);
      expect(find.text('weekly_report_locked_title'), findsNothing);
    });

    testWidgets('first open animates in; once seen (or reduce motion) it is '
        'final on the first frame', (tester) async {
      double firstSectionOpacity() {
        final fade = find.byType(FadeSlideIn).first;
        final opacities = tester.widgetList<Opacity>(
          find.descendant(of: fade, matching: find.byType(Opacity)),
        );
        final fades = tester.widgetList<FadeTransition>(
          find.descendant(of: fade, matching: find.byType(FadeTransition)),
        );
        return [
          for (final o in opacities) o.opacity,
          for (final f in fades) f.opacity.value,
        ].fold(1.0, (a, b) => a * b);
      }

      await tester.pumpWidget(
        reportApp(
          FixedWeeklyReportController(ready(fullReport())),
          openScreen: true,
        ),
      );
      await tester.pump();
      expect(firstSectionOpacity(), lessThan(1));
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        reportApp(
          FixedWeeklyReportController(ready(fullReport(), seen: true)),
          openScreen: true,
        ),
      );
      await tester.pump();
      expect(firstSectionOpacity(), 1);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        reportApp(
          FixedWeeklyReportController(ready(fullReport())),
          openScreen: true,
          reduceMotion: true,
        ),
      );
      await tester.pump();
      expect(firstSectionOpacity(), 1);
      await tester.pumpAndSettle();
    });
  });
}
