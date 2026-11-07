// Disparadores del sync del widget (§3.3 de la spec) con store, scheduler y
// eventos falsos. Correr: flutter test test/features/home_widget/providers
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_history_point.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_calculator.dart';
import 'package:portfolio_assistant/features/home_widget/data/home_widget_store.dart';
import 'package:portfolio_assistant/features/home_widget/providers/home_widget_sync_provider.dart';
import 'package:portfolio_assistant/features/home_widget/providers/widget_settings_provider.dart';
import 'package:portfolio_assistant/features/product_events/data/product_events.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';
import 'package:portfolio_assistant/presentation/flows/home/states/home_state.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_insight_copy.dart';
import 'package:portfolio_assistant/features/home_widget/data/widget_feed_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Session, User;

import '../home_widget_test_helpers.dart';

class _Home extends StateNotifier<HomeState> implements HomeProvider {
  _Home(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Events extends ProductEvents {
  _Events() : super(client: () => null, prefs: () => null);
  final logged = <(ProductEvent, Map<String, Object?>)>[];

  @override
  void log(ProductEvent event, [Map<String, Object?> props = const {}]) =>
      logged.add((event, props));
}

final _now = DateTime(2026, 11, 5, 12);

User _user() => const User(
  id: 'uid-1',
  appMetadata: {},
  userMetadata: {},
  aud: 'authenticated',
  createdAt: '2026-01-01',
);

PortfolioSummary _summary({bool empty = false}) {
  if (empty) return PortfolioCalculator.summarize(const []);
  final p = Position(
    id: '1',
    ticker: 'NVDA',
    quantity: 10,
    purchasePrice: 100,
    purchaseDate: DateTime(2026, 10, 1),
  );
  return PortfolioCalculator.summarize([
    PortfolioCalculator.valuate(position: p, currentPrice: 120),
  ]);
}

List<PortfolioHistoryPoint> _history() => [
  PortfolioHistoryPoint(
    date: DateTime(2026, 11, 4),
    totalValue: 1100,
    totalCostBasis: 1000,
  ),
  PortfolioHistoryPoint(
    date: DateTime(2026, 11, 5),
    totalValue: 1200,
    totalCostBasis: 1000,
  ),
];

HomeState _good({bool empty = false}) => HomeState(
  loading: false,
  summary: _summary(empty: empty),
  history: _history(),
);

Future<List<PriceCandle>> _candles(String t) async => [
  PriceCandle(date: DateTime(2026, 11, 4), close: 110),
  PriceCandle(date: DateTime(2026, 11, 5), close: 120),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeHomeWidgetStore store;
  late FakeScheduler scheduler;
  late _Events events;
  late SharedPreferences prefs;
  late bool hidden;
  late HomeWidgetSyncController c;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    store = FakeHomeWidgetStore();
    scheduler = FakeScheduler();
    events = _Events();
    hidden = false;
    c = HomeWidgetSyncController(
      store: store,
      prefs: prefs,
      events: events,
      scheduler: scheduler,
      loadTexts: loadRealTexts,
      loadCandles: _candles,
      currentUserId: () => 'uid-1',
      amountsHidden: () => hidden,
      initialLang: 'es',
      now: () => _now,
    );
  });

  tearDown(() => c.dispose());

  group('Home changes', () {
    test(
      'writes ready with the top contributor and registers the refresh',
      () async {
        c.onHome(null, _good());
        await c.flush();

        expect(store.writes, hasLength(1));
        expect(store.last['state'], 'ready');
        expect(store.last.containsKey('total_text'), isFalse);
        expect(store.last['phrase'], 'Tu cartera sube hoy.');
        expect(prefs.getString(WidgetPrefsKeys.ownerUid), 'uid-1');
        expect(prefs.getString(WidgetPrefsKeys.lang), 'es');
        expect(scheduler.registered, 1);
      },
    );

    test('debounces bursts into one write', () async {
      c.onHome(null, _good());
      c.onHome(_good(), _good());
      await c.flush();
      expect(store.writes, hasLength(1));
    });

    test('the cache fills the widget until this session wrote a portfolio', () async {
      HomeState cached() => HomeState(
        loading: false,
        fromCache: true,
        summary: _summary(),
        history: _history(),
      );
      // Arranque: todavía no se escribió la cartera en esta sesión, el
      // caché es mejor que "cargá tu cartera".
      c.onHome(null, cached());
      await c.flush();
      expect(store.writes, hasLength(1));
      expect(store.last['state'], 'ready');

      // Ya hay una buena: ni el caché ni una carga fallida la pisan.
      c.onHome(null, cached());
      c.onHome(
        null,
        HomeState(
          loading: false,
          quoteError: 'x',
          summary: _summary(),
          history: _history(),
        ),
      );
      c.onHome(null, HomeState());
      await c.flush();
      expect(store.writes, hasLength(1));
    });

    test('a non-finite number in a Home insight still writes the portfolio', () async {
      final withNaN = HomeWidgetSyncController(
        store: store,
        prefs: prefs,
        events: events,
        scheduler: scheduler,
        loadTexts: loadRealTexts,
        loadCandles: _candles,
        currentUserId: () => 'uid-1',
        amountsHidden: () => hidden,
        initialLang: 'es',
        now: () => _now,
        feedExtras: () => const WidgetFeedExtras(
          insights: [
            WidgetInsightInput(
              id: 'goal_overdue:Casa',
              kind: WidgetInsightKind.goalOverdue,
              score: 70,
              goalLabel: 'Casa',
              numbers: {'required': double.infinity, 'pct': double.nan},
            ),
          ],
        ),
      );
      addTearDown(withNaN.dispose);
      withNaN.onHome(null, _good(empty: true));
      await withNaN.flush();
      withNaN.onHome(null, _good());
      await withNaN.flush();
      expect(store.last['state'], 'ready');
      // Y el refresco de fondo puede leer la caché de avisos.
      expect(WidgetFeedCache(prefs).read(uid: 'uid-1'), isNotNull);
    });

    test('an empty cache never writes no_portfolio', () async {
      c.onHome(
        null,
        HomeState(
          loading: false,
          fromCache: true,
          summary: _summary(empty: true),
        ),
      );
      await c.flush();
      expect(store.writes, isEmpty);
    });

    test('same summary and history: no rewrite', () async {
      final s = _good();
      c.onHome(null, s);
      await c.flush();
      c.onHome(s, s.copyWith(showAllPositions: true));
      await c.flush();
      expect(store.writes, hasLength(1));
    });

    test('empty portfolio writes no_portfolio and clears the owner', () async {
      await prefs.setString(WidgetPrefsKeys.ownerUid, 'uid-1');
      c.onHome(null, _good(empty: true));
      await c.flush();
      expect(store.last['state'], 'no_portfolio');
      expect(prefs.getString(WidgetPrefsKeys.ownerUid), isNull);
    });

    test('adding the first positions turns no_portfolio into ready', () async {
      final empty = _good(empty: true);
      c.onHome(null, empty);
      await c.flush();
      expect(store.last['state'], 'no_portfolio');
      c.onHome(empty, _good());
      await c.flush();
      expect(store.last['state'], 'ready');
    });

    test('going to background writes the pending change right away', () async {
      final empty = _good(empty: true);
      c.onHome(null, empty);
      await c.flush();
      c.onHome(empty, _good());
      // Sin esperar el debounce: la app se fue a segundo plano.
      c.onAppBackground();
      await Future<void>.delayed(Duration.zero);
      await c.flush();
      expect(store.last['state'], 'ready');
    });

    test('coming back rewrites the last known snapshot', () async {
      c.onHome(null, _good());
      await c.flush();
      final before = store.writes.length;
      c.onAppResumed();
      await c.flush();
      expect(store.writes.length, before + 1);
      expect(store.last['state'], 'ready');
    });

    test('coming back before any data writes nothing', () async {
      c.onAppResumed();
      await c.flush();
      expect(store.writes, isEmpty);
    });

    test(
      'without installed widgets it cancels instead of registering',
      () async {
        store.installed = [];
        c.onHome(null, _good());
        await c.flush();
        expect(scheduler.registered, 0);
        expect(scheduler.cancelled, 1);
      },
    );

    test('a failing store never throws', () async {
      store.failWrites = true;
      c.onHome(null, _good());
      await c.flush();
      expect(store.writes, isEmpty);
    });
  });

  group('settings and language', () {
    test('hiding amounts rewrites at once without ticker or totals', () async {
      c.onHome(null, _good());
      await c.flush();
      hidden = true;
      c.onHiddenChanged();
      await c.flush();

      expect(store.writes, hasLength(2));
      expect((store.last['v2'] as Map)['positions_hidden'], true);
      expect(store.last.containsKey('total_text'), isFalse);
      expect(store.last['phrase'], 'Tu cartera sube hoy.');
    });

    test(
      'language change rewrites in the new language; same language does not',
      () async {
        c.onHome(null, _good());
        await c.flush();
        c.onLanguage('es');
        c.onLanguage('en_US');
        await c.flush();
        expect(store.writes, hasLength(2));
        expect(store.last['lang'], 'en');
        expect(
          store.last['phrase'],
          // v2: la frase nunca lleva ticker (spec §6.1).
          'Your portfolio is up today.',
        );
      },
    );

    test('toggle before any data writes nothing', () async {
      c.onHiddenChanged();
      await c.flush();
      expect(store.writes, isEmpty);
      expect(store.scrubs, 0);
    });

    test(
      'hiding without fresh data scrubs the stored snapshot (offline start)',
      () async {
        // Snapshot de una sesión anterior, con montos y ticker.
        c.onHome(null, _good());
        await c.flush();
        final fresh = HomeWidgetSyncController(
          store: store,
          prefs: prefs,
          events: events,
          scheduler: scheduler,
          loadTexts: loadRealTexts,
          loadCandles: _candles,
          currentUserId: () => 'uid-1',
          amountsHidden: () => hidden,
          initialLang: 'es',
          now: () => _now,
        );
        addTearDown(fresh.dispose);
        hidden = true;
        fresh.onHiddenChanged();
        await fresh.flush();

        expect(store.scrubs, 1);
        expect(store.last['state'], 'ready');
        expect((store.last['v2'] as Map)['positions_hidden'], true);
        // La frase de v2 nunca lleva ticker: puede quedar.
        for (final k in ['total_text', 'change_text']) {
          expect(store.last.containsKey(k), isFalse, reason: k);
        }
        expect(store.last['a11y_value'], isNot(contains(r'$')));
        expect(store.last['change_pct_text'], isNotNull);
      },
    );
  });

  group('sign out', () {
    test(
      'clears the owner uid, writes signed_out and cancels the refresh',
      () async {
        c.onHome(null, _good());
        await c.flush();
        c.onSignedOut();
        await c.flush();

        expect(prefs.getString(WidgetPrefsKeys.ownerUid), isNull);
        expect(store.last['state'], 'signed_out');
        expect(store.last.containsKey('phrase'), isFalse);
        expect(store.last.containsKey('total_text'), isFalse);
        expect(scheduler.cancelled, 1);
      },
    );

    test('clears the widget offer state (opens, count, date)', () async {
      await prefs.setInt(WidgetPrefsKeys.promptOpens, 5);
      await prefs.setInt(WidgetPrefsKeys.promptShown, 1);
      await prefs.setInt(WidgetPrefsKeys.promptLastAt, 123);
      c.onSignedOut();
      await c.flush();
      for (final key in WidgetPrefsKeys.promptKeys) {
        expect(prefs.containsKey(key), isFalse, reason: key);
      }
    });

    test(
      'a Home write in flight before sign out does not resurrect data',
      () async {
        c.onHome(null, _good());
        c.onSignedOut();
        await c.flush();
        expect(store.writes.map((w) => w['state']), ['signed_out']);
      },
    );

    test(
      'after sign out a toggle does not bring back the old portfolio',
      () async {
        c.onHome(null, _good());
        await c.flush();
        c.onSignedOut();
        c.onHiddenChanged();
        await c.flush();
        expect(store.writes.map((w) => w['state']), ['ready', 'signed_out']);
      },
    );
  });

  group('widget_presence', () {
    test('logs only when the installed sizes changed', () async {
      await c.reportPresence();
      expect(events.logged, hasLength(1));
      expect(events.logged.single.$2, {
        'platform': 'ios',
        'sizes': ['small', 'medium'],
      });

      await c.reportPresence();
      expect(events.logged, hasLength(1));

      store.installed = [];
      await c.reportPresence();
      expect(events.logged, hasLength(2));
      expect(events.logged.last.$2['sizes'], isEmpty);
      expect(scheduler.cancelled, 1);
    });

    test('nothing installed and nothing stored: no event', () async {
      store.installed = [];
      await c.reportPresence();
      expect(events.logged, isEmpty);
    });
  });

  group('provider wiring', () {
    test('auth session going to null writes signed_out', () async {
      final auth = StreamController<Session?>();
      final home = _Home(_good());
      final container = ProviderContainer(
        overrides: [
          homeProvider.overrideWith((ref) => home),
          sharedPreferencesProvider.overrideWithValue(prefs),
          homeWidgetStoreProvider.overrideWithValue(store),
          widgetBackgroundSchedulerProvider.overrideWithValue(scheduler),
          widgetTextsLoaderProvider.overrideWithValue(loadRealTexts),
          widgetCandleLoaderProvider.overrideWithValue(_candles),
          widgetIntradayLoaderProvider.overrideWithValue(null),
          productEventsProvider.overrideWithValue(events),
          authSessionProvider.overrideWith((ref) => auth.stream),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(auth.close);

      final controller = container.read(homeWidgetSyncProvider);
      await controller.flush();
      expect(store.last['state'], 'ready');

      container.listen(authSessionProvider, (_, __) {});
      auth.add(Session(accessToken: 'a', tokenType: 'bearer', user: _user()));
      await Future<void>.delayed(Duration.zero);
      auth.add(null);
      await Future<void>.delayed(Duration.zero);
      await controller.flush();
      expect(store.last['state'], 'signed_out');
    });
  });
}
