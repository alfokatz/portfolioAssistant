import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/domain/entities/benchmark_point.dart';
import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_history_point.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/position_valuation.dart';
import 'package:portfolio_assistant/domain/subscription/ai_usage_tracker.dart';
import 'package:portfolio_assistant/domain/use_cases/delete_positions_by_ticker_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_benchmark_comparison_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_closed_positions_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_portfolio_history_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_portfolio_summary_use_case.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/services/revenue_cat_service.dart';
import 'package:portfolio_assistant/features/weekly_report/providers/weekly_report_controller.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:portfolio_assistant/presentation/flows/home/data/home_portfolio_cache.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/home_screen.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/home_skeleton.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/portfolio_hero_section.dart';
import 'package:portfolio_assistant/presentation/shared/loading/loader_timing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../features/weekly_report/weekly_report_ui_test.dart'
    show FixedWeeklyReportController;

PortfolioSummary sampleSummary(double price) {
  final valuation = PositionValuation(
    position: Position(
      id: 'p1',
      ticker: 'AAPL',
      quantity: 2,
      purchasePrice: 100,
      purchaseDate: DateTime(2026, 1, 5),
    ),
    currentPrice: price,
    marketValue: 2 * price,
    pnlAbsolute: 2 * price - 200,
    pnlPercent: (price - 100),
  );
  return PortfolioSummary(
    totalValue: 2 * price,
    totalCostBasis: 200,
    totalPnlAbsolute: 2 * price - 200,
    totalPnlPercent: price - 100,
    valuations: [valuation],
    lots: [valuation],
  );
}

/// La `HomeScreen` real con casos de uso falsos (también la usan las
/// capturas de test/screenshots/loaders_screenshots_test.dart).
class HomeTestHarness {
  HomeTestHarness({HomeSnapshot? cached, this.history = const []})
    : cache = _FakeCache(cached);

  final List<PortfolioHistoryPoint> history;

  final summary = Completer<PortfolioSummary>();
  final _FakeCache cache;

  Widget app({
    bool reduceMotion = false,
    Brightness brightness = Brightness.light,
    List<LocalizationsDelegate<Object?>>? localizationsDelegates,
    List<Locale>? supportedLocales,
    Locale? locale,
  }) {
    final container = ProviderContainer();
    final theme = container.read(
      brightness == Brightness.light
          ? themeDataLightProvider
          : themeDataDarkProvider,
    );
    container.dispose();
    return ProviderScope(
      overrides: [
        homeProvider.overrideWith(
          (ref) => HomeProvider(
            ref: ref,
            getPortfolioSummaryUseCase: _SummaryUseCase(summary.future),
            getPortfolioHistoryUseCase: _HistoryUseCase(history),
            getBenchmarkComparisonUseCase: _BenchmarkUseCase(),
            deletePositionsByTickerUseCase: _UnusedDelete(),
            getClosedPositionsUseCase: _ClosedUseCase(),
            cache: cache,
          ),
        ),
        subscriptionProvider.overrideWith(
          (ref) => SubscriptionNotifier(
            tracker: _UnusedTracker(),
            authService: _NoSession(),
            revenueCat: _UnusedRevenueCat(),
          ),
        ),
        weeklyReportControllerProvider.overrideWith(
          (ref) => FixedWeeklyReportController(const WeeklyReportState()),
        ),
      ],
      child: MaterialApp(
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
        home: const HomeScreen(),
      ),
    );
  }
}

Finder get _spinner => find.byType(CircularProgressIndicator);
Finder get _skeleton => find.byType(HomeSkeleton);
/// El contenido real (el skeleton usa "AAPL" como placeholder invisible).
Finder get _positionRow => find.byWidgetPredicate(
  (w) => w is PortfolioHeroSection && w.summary != null,
);

void main() {
  group('without anything cached', () {
    testWidgets('waits 300 ms, then the Home skeleton (never a spinner); '
        'once visible it stays 400 ms, then the content crossfades in', (
      tester,
    ) async {
      final h = HomeTestHarness();
      await tester.pumpWidget(h.app());
      await tester.pump(); // post-frame: init → carga

      await tester.pump(const Duration(milliseconds: 250));
      expect(_skeleton, findsNothing);
      expect(_spinner, findsNothing);

      await tester.pump(const Duration(milliseconds: 60)); // 310 ms
      expect(_skeleton, findsOneWidget);
      expect(_spinner, findsNothing);

      // La carga termina enseguida (≈ 360 ms): el skeleton se queda hasta
      // cumplir sus 400 ms visibles (≈ 710 ms).
      await tester.pump(const Duration(milliseconds: 50));
      h.summary.complete(sampleSummary(150));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300)); // ≈ 660 ms
      expect(_skeleton, findsOneWidget);
      expect(_positionRow, findsNothing);

      await tester.pump(const Duration(milliseconds: 60)); // ≈ 720 ms
      await tester.pump(LoaderTiming.swap ~/ 2);
      // A mitad del crossfade conviven los dos.
      expect(_skeleton, findsOneWidget);
      expect(_positionRow, findsOneWidget);

      await tester.pumpAndSettle();
      expect(_skeleton, findsNothing);
      expect(_positionRow, findsOneWidget);
      expect(_spinner, findsNothing);
      // Y quedó guardado para la próxima vez.
      expect(h.cache.written?.summary.totalValue, 300);
    });

    testWidgets('a load under 300 ms never shows the skeleton', (tester) async {
      final h = HomeTestHarness();
      await tester.pumpWidget(h.app());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      h.summary.complete(sampleSummary(150));

      var sawSkeleton = false;
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (_skeleton.evaluate().isNotEmpty) sawSkeleton = true;
      }
      expect(sawSkeleton, isFalse);
      expect(_positionRow, findsOneWidget);
    });

    testWidgets('never a blank screen: past 300 ms there is always the '
        'skeleton or the content', (tester) async {
      final h = HomeTestHarness();
      await tester.pumpWidget(h.app());
      await tester.pump();
      final blankFrames = <int>[];
      for (var ms = 0; ms <= 2000; ms += 16) {
        if (ms == 1200) h.summary.complete(sampleSummary(150));
        await tester.pump(const Duration(milliseconds: 16));
        final past = ms + 16 > LoaderTiming.showDelay.inMilliseconds;
        final visible =
            _skeleton.evaluate().isNotEmpty ||
            _positionRow.evaluate().isNotEmpty;
        if (past && !visible) blankFrames.add(ms);
      }
      expect(blankFrames, isEmpty);
      expect(_spinner, findsNothing);
    });

    testWidgets('with reduce motion the skeleton is static', (tester) async {
      final h = HomeTestHarness();
      await tester.pumpWidget(h.app(reduceMotion: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(_skeleton, findsOneWidget);
      expect(SchedulerBinding.instance.transientCallbackCount, 0);
      await tester.pump(const Duration(seconds: 1));
      expect(SchedulerBinding.instance.transientCallbackCount, 0);
    });
  });

  group('with a cached Home', () {
    testWidgets('shows the cached data on the first frame (no skeleton) and '
        'updates the values in place when the new ones arrive', (tester) async {
      final h = HomeTestHarness(cached: HomeSnapshot(summary: sampleSummary(120)));
      await tester.pumpWidget(h.app());

      expect(_positionRow, findsOneWidget);
      expect(find.text(r'$240.00'), findsWidgets);
      expect(_skeleton, findsNothing);

      var sawSkeleton = false;
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (_skeleton.evaluate().isNotEmpty) sawSkeleton = true;
      }
      h.summary.complete(sampleSummary(150));
      await tester.pump();
      await tester.pump(LoaderTiming.swap ~/ 2);
      // Crossfade en el lugar: el valor viejo y el nuevo, a la vez.
      expect(find.text(r'$240.00'), findsWidgets);
      expect(find.text(r'$300.00'), findsWidgets);

      await tester.pumpAndSettle();
      expect(find.text(r'$240.00'), findsNothing);
      expect(find.text(r'$300.00'), findsWidgets);
      expect(sawSkeleton, isFalse);
    });
  });

  group('HomePortfolioCache', () {
    test('round-trips a snapshot and is scoped to the signed-in user', () {
      final prefs = _MemoryPrefs();
      var user = 'user-a';
      final cache = HomePortfolioCache(prefs: prefs, userId: () => user);
      final snapshot = HomeSnapshot(
        summary: sampleSummary(150),
        history: [
          PortfolioHistoryPoint(
            date: DateTime(2026, 9, 1),
            totalValue: 280,
            totalCostBasis: 200,
          ),
        ],
        benchmark: [
          BenchmarkPoint(
            date: DateTime(2026, 9, 1),
            portfolioNormalized: 100,
            sp500Normalized: 101,
          ),
        ],
        closedPositionsCount: 3,
      );
      cache.write(snapshot);

      final read = cache.read()!;
      expect(read.summary.totalValue, 300);
      expect(read.summary.valuations.single.position.ticker, 'AAPL');
      expect(
        read.summary.lots.single.position.purchaseDate,
        DateTime(2026, 1, 5),
      );
      expect(read.history.single.totalValue, 280);
      expect(read.benchmark.single.sp500Normalized, 101);
      expect(read.closedPositionsCount, 3);

      user = 'user-b';
      expect(cache.read(), isNull);
      user = '';
      expect(cache.read(), isNull);
    });
  });
}

class _FakeCache implements HomePortfolioCache {
  _FakeCache(this.snapshot);

  final HomeSnapshot? snapshot;
  HomeSnapshot? written;

  @override
  HomeSnapshot? read() => snapshot;

  @override
  Future<void> write(HomeSnapshot snapshot) async => written = snapshot;
}

class _Unused {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _SummaryUseCase extends _Unused implements GetPortfolioSummaryUseCase {
  _SummaryUseCase(this._summary);

  final Future<PortfolioSummary> _summary;

  @override
  Future<Either<HttpError, PortfolioSummary>> call({void params}) =>
      _summary.then(Right.new);
}

class _HistoryUseCase extends _Unused implements GetPortfolioHistoryUseCase {
  _HistoryUseCase(this._history);

  final List<PortfolioHistoryPoint> _history;

  @override
  Future<Either<HttpError, List<PortfolioHistoryPoint>>> call({
    void params,
  }) async => Right(_history);
}

class _BenchmarkUseCase extends _Unused
    implements GetBenchmarkComparisonUseCase {
  @override
  Future<Either<HttpError, List<BenchmarkPoint>>> call({void params}) async =>
      const Right([]);
}

class _ClosedUseCase extends _Unused implements GetClosedPositionsUseCase {
  @override
  Future<Either<HttpError, List<ClosedPosition>>> call({void params}) async =>
      const Right([]);
}

class _UnusedDelete extends _Unused implements DeletePositionsByTickerUseCase {}

class _UnusedTracker extends _Unused implements AiUsageTracker {}

class _UnusedRevenueCat extends _Unused implements RevenueCatService {}

class _NoSession extends _Unused implements SupabaseAuthService {
  @override
  Session? get currentSession => null;
}

class _MemoryPrefs extends _Unused implements SharedPreferences {
  final _values = <String, String>{};

  @override
  String? getString(String key) => _values[key];

  @override
  Future<bool> setString(String key, String value) async {
    _values[key] = value;
    return true;
  }
}
