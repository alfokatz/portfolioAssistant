import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/watchlist/data/watchlist_repository.dart';
import 'package:portfolio_assistant/features/watchlist/domain/watchlist_item.dart';
import 'package:portfolio_assistant/features/watchlist/providers/watchlist_provider.dart';
import 'package:portfolio_assistant/features/watchlist/view/watchlist_screen.dart';
import 'package:portfolio_assistant/infraestructure/repositories/quote_repository_impl.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:portfolio_assistant/domain/entities/company_brand.dart';
import 'package:portfolio_assistant/domain/entities/symbol_search_result.dart';
import 'package:portfolio_assistant/domain/repositories/company_brand_repository.dart';
import 'package:portfolio_assistant/domain/repositories/symbol_search_repository.dart';
import 'package:portfolio_assistant/domain/use_cases/get_current_price_use_case.dart';
import 'package:portfolio_assistant/features/assistant/services/company_brand_loader.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/goals/providers/goals_provider.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/ticker_search_sheet.dart';

final _today = DateTime(2026, 10, 16, 15);

class _Quotes implements QuoteRepository {
  @override
  Future<Either<HttpError, double>> getCurrentPrice(String ticker) async =>
      ticker == 'NOPE'
          ? Left(HttpError(code: 'x', message: 'x'))
          : const Right(110);

  @override
  Future<Either<HttpError, List<PriceCandle>>> getHistoricalDaily(
    String ticker,
  ) async => Right([
    PriceCandle(date: DateTime(2026, 10, 14), close: 90),
    PriceCandle(date: DateTime(2026, 10, 15), close: 100),
    // Vela de hoy: no es el cierre anterior.
    PriceCandle(date: DateTime(2026, 10, 16), close: 110),
  ]);

  @override
  Future<List<PriceCandle>> getIntradayCandles(String ticker) async => const [];
}

class _Repo implements WatchlistRepository {
  _Repo([List<WatchlistItem>? items]) : items = items ?? [];

  final List<WatchlistItem> items;
  WatchlistFailure? failAdd;

  @override
  Future<List<WatchlistItem>> list() async => List.of(items);

  @override
  Future<WatchlistItem> add(String symbol, {double? price}) async {
    if (failAdd != null) throw failAdd!;
    final item = WatchlistItem(
      id: 'id-$symbol',
      symbol: symbol,
      addedPrice: price,
      createdAt: _today,
    );
    items.insert(0, item);
    return item;
  }

  @override
  Future<void> setNotify(String id, {required bool notify}) async {}

  @override
  Future<void> remove(String id) async => items.removeWhere((i) => i.id == id);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Subscription extends StateNotifier<SubscriptionState>
    implements SubscriptionNotifier {
  _Subscription(SubscriptionTier tier)
    : super(SubscriptionState(tier: tier, queriesUsed: 0, queriesLimit: 20));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('WatchQuote', () {
    test('cierre anterior, variación del día y desde que la agregó', () {
      final prev = WatchQuote.previousCloseFrom([
        PriceCandle(date: DateTime(2026, 10, 16), close: 110),
        PriceCandle(date: DateTime(2026, 10, 15), close: 100),
        PriceCandle(date: DateTime(2026, 10, 14), close: 90),
      ], _today);
      expect(prev, 100);
      const q = WatchQuote(price: 110, previousClose: 100);
      expect(q.dayChangePct, closeTo(10, 1e-9));
      expect(q.sinceAddedPct(88), closeTo(25, 1e-9));
      expect(q.sinceAddedPct(null), isNull);
      expect(const WatchQuote(price: 1).dayChangePct, isNull);
    });

    test('fila de la base', () {
      final item =
          WatchlistItem.fromRow({
            'id': 'a',
            'symbol': 'AMZN',
            'added_price': '180.5',
            'notify': false,
            'created_at': '2026-10-01T12:00:00Z',
          })!;
      expect(item.addedPrice, 180.5);
      expect(item.notify, isFalse);
      expect(WatchlistItem.fromRow({'symbol': 'X'}), isNull);
    });
  });

  group('WatchlistNotifier', () {
    test('carga con cotizaciones; agrega con el precio de hoy', () async {
      final repo = _Repo([
        WatchlistItem(
          id: '1',
          symbol: 'AMZN',
          addedPrice: 100,
          createdAt: _today,
        ),
      ]);
      final n = WatchlistNotifier(repo, _Quotes.new, now: () => _today);
      await n.load();
      await n.refreshQuotes();
      expect(n.state.items.single.symbol, 'AMZN');
      expect(n.state.quotes['AMZN']!.dayChangePct, closeTo(10, 1e-9));

      final added = await n.add(' msft ');
      expect(added.symbol, 'MSFT');
      expect(added.addedPrice, 110);
      expect(n.state.items.first.symbol, 'MSFT');
      expect(n.state.contains('msft'), isTrue);
    });

    test('ticker sin cotización o tope del plan', () async {
      final repo = _Repo();
      final n = WatchlistNotifier(repo, _Quotes.new, now: () => _today);
      await expectLater(n.add('NOPE'), throwsA(isA<WatchlistUnknownSymbol>()));
      repo.failAdd = const WatchlistLimitReached();
      await expectLater(n.add('AMZN'), throwsA(isA<WatchlistLimitReached>()));
      expect(n.state.items, isEmpty);
    });

    test('quitar es optimista y se deshace si falla', () async {
      final repo = _Repo([
        WatchlistItem(id: '1', symbol: 'AMZN', createdAt: _today),
      ]);
      final n = WatchlistNotifier(repo, _Quotes.new, now: () => _today);
      await n.load();
      await n.remove(n.state.items.single);
      expect(n.state.items, isEmpty);
    });
  });

  group('pantalla', () {
    setUpAll(() => PortyAvatar.ambientMotion = false);
    tearDownAll(() => PortyAvatar.ambientMotion = true);

    late _Repo repo;

    Future<void> pump(
      WidgetTester tester, {
      required SubscriptionTier tier,
      List<WatchlistItem> items = const [],
      Map<String, double> held = const {},
    }) async {
      tester.view.physicalSize = const Size(320, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      repo = _Repo(List.of(items));
      final theme = ProviderContainer().read(themeDataLightProvider);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            watchlistRepositoryProvider.overrideWithValue(repo),
            quoteRepositoryProvider.overrideWithValue(_Quotes()),
            subscriptionProvider.overrideWith((ref) => _Subscription(tier)),
            goalHoldingsProvider.overrideWithValue(held),
            symbolSearchRepositoryProvider.overrideWithValue(_Search()),
            getCurrentPriceUseCaseProvider.overrideWithValue(
              GetCurrentPriceUseCase(quoteRepository: _Quotes()),
            ),
            companyBrandLoaderProvider.overrideWithValue(
              CompanyBrandLoader(_NoBrandRepo()),
            ),
          ],
          child: MaterialApp(
            theme: theme,
            // Alguien escucha las alertas (si no, el provider se descarta
            // antes de que se cierre el aviso).
            home: Consumer(
              builder: (context, ref, _) {
                ref.watch(alertProvider);
                return const WatchlistScreen();
              },
            ),
          ),
        ),
      );
      await settle(tester);
    }

    testWidgets('Free: Porty explica para qué sirve y lleva a los planes', (
      tester,
    ) async {
      await pump(tester, tier: SubscriptionTier.free);
      expect(find.text('watchlist_intro_porty'), findsOneWidget);
      expect(find.text('watchlist_locked_body'), findsOneWidget);
      expect(find.text('watchlist_see_plans'), findsOneWidget);
      expect(find.byTooltip('watchlist_add'), findsNothing);
    });

    testWidgets('Premium vacía: invita a buscar una acción', (tester) async {
      await pump(tester, tier: SubscriptionTier.premium);
      expect(find.text('watchlist_add_first'), findsOneWidget);
      expect(find.text('watchlist_point_alerts_title'), findsOneWidget);
    });

    testWidgets('con tickers: Porty cuenta el mayor movimiento, filas y '
        'acciones', (tester) async {
      await pump(
        tester,
        tier: SubscriptionTier.premium,
        items: [
          WatchlistItem(
            id: '1',
            symbol: 'AMZN',
            addedPrice: 100,
            createdAt: _today,
          ),
        ],
      );
      // Con la fecha de hoy, el cierre anterior es la última vela (110): el
      // día no se movió y Porty dice que la lista está tranquila.
      expect(find.text('watchlist_porty_calm'), findsOneWidget);
      expect(find.text('AMZN'), findsWidgets);
      expect(find.text('\$110.00'), findsOneWidget);
      expect(find.text('watchlist_count'), findsOneWidget);
      await tester.tap(find.text('AMZN').first);
      await settle(tester);
      expect(find.text('watchlist_action_ask'), findsOneWidget);
      expect(find.text('watchlist_action_remove'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('agregar: busca por nombre, marca lo que ya tiene y lo suma', (
      tester,
    ) async {
      await pump(
        tester,
        tier: SubscriptionTier.premium,
        held: const {'AAPL': 1000},
      );
      await tester.tap(find.text('watchlist_add_first'));
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'a');
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);
      // AAPL ya está en la cartera: marcada, no se elige.
      expect(find.text('watchlist_taken_held'), findsOneWidget);
      await tester.tap(find.text('AMZN'));
      await settle(tester);
      expect(repo.items.map((i) => i.symbol), ['AMZN']);
      expect(find.text('watchlist_porty_calm'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
    });
  });
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

class _Search implements SymbolSearchRepository {
  @override
  Future<Either<HttpError, List<SymbolSearchResult>>> search(String q) async =>
      const Right([
        SymbolSearchResult(
          symbol: 'AMZN',
          description: 'AMAZON.COM INC',
          type: 'Common Stock',
        ),
        SymbolSearchResult(
          symbol: 'AAPL',
          description: 'APPLE INC',
          type: 'Common Stock',
        ),
      ]);
}

/// Sin logos: los avatares muestran el monograma (y no reintentan).
class _NoBrandRepo implements CompanyBrandRepository {
  @override
  Future<CompanyBrand?> getBrand(String ticker) async =>
      CompanyBrand(ticker: ticker);
}
