// Screenshots de la lista de seguimiento (vacía, con tickers, las acciones
// de uno y la búsqueda para agregar), en claro y oscuro, con fuentes y
// textos reales. No corre en la suite normal (escribe PNGs):
//
//   RUN_SCREENSHOTS=1 SCREENSHOTS_OUT=/tmp/shots \
//     flutter test test/screenshots/watchlist_screenshots_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dartz/dartz.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
// Viene con el SDK (y con easy_localization); solo para estos screenshots.
// ignore: depend_on_referenced_packages
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/company_brand.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/entities/symbol_search_result.dart';
import 'package:portfolio_assistant/domain/repositories/company_brand_repository.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/domain/repositories/symbol_search_repository.dart';
import 'package:portfolio_assistant/features/assistant/services/company_brand_loader.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/goals/providers/goals_provider.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/watchlist/data/watchlist_repository.dart';
import 'package:portfolio_assistant/features/watchlist/domain/watchlist_item.dart';
import 'package:portfolio_assistant/features/watchlist/view/watchlist_screen.dart';
import 'package:portfolio_assistant/infraestructure/repositories/quote_repository_impl.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/app_background_gradient.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/ticker_search_sheet.dart';

final _out = Platform.environment['SCREENSHOTS_OUT'] ?? 'build/screenshots';
final _enabled = Platform.environment['RUN_SCREENSHOTS'] == '1';

const _size = Size(402, 874);
const _dpr = 3.0;

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(
        File(f).readAsBytes().then((b) => ByteData.view(b.buffer)),
      );
    }
    await loader.load();
  }

  final sdk =
      Platform.environment['FLUTTER_ROOT'] ??
      '${Platform.environment['HOME']}/Development/flutter';
  await load('MaterialIcons', [
    '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ]);
  const weights = {'Regular': 400, 'Medium': 500, 'SemiBold': 600, 'Bold': 700};
  for (final MapEntry(key: name, value: w) in weights.entries) {
    final file = 'assets/fonts/PlusJakartaSans-$name.ttf';
    await load('PlusJakartaSans_${w == 400 ? 'regular' : w}', [file]);
    await load('Plus Jakarta Sans', [file]);
  }
}

/// Precio de hoy y cierre de ayer por ticker.
const _prices = {
  'NVDA': (182.4, 174.1),
  'AMZN': (221.3, 223.0),
  'MELI': (2140.0, 2118.5),
  'KO': (69.9, 69.7),
};

class _Quotes implements QuoteRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<Either<HttpError, double>> getCurrentPrice(String ticker) async {
    final p = _prices[ticker];
    return p == null ? Left(HttpError(code: 'x')) : Right(p.$1);
  }

  @override
  Future<Either<HttpError, List<PriceCandle>>> getHistoricalDaily(
    String ticker,
  ) async {
    final p = _prices[ticker];
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    return Right([if (p != null) PriceCandle(date: yesterday, close: p.$2)]);
  }
}

class _Repo implements WatchlistRepository {
  _Repo(this.items);

  final List<WatchlistItem> items;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<List<WatchlistItem>> list() async => items;
}

class _Search implements SymbolSearchRepository {
  @override
  Future<Either<HttpError, List<SymbolSearchResult>>> search(String q) async =>
      const Right([
        SymbolSearchResult(
          symbol: 'MSFT',
          description: 'MICROSOFT CORP',
          type: 'Common Stock',
        ),
        SymbolSearchResult(
          symbol: 'MSTR',
          description: 'MICROSTRATEGY INC',
          type: 'Common Stock',
        ),
        SymbolSearchResult(
          symbol: 'MCHI',
          description: 'ISHARES MSCI CHINA ETF',
          type: 'ETP',
        ),
      ]);
}

class _Brands implements CompanyBrandRepository {
  static const _names = {
    'NVDA': 'NVIDIA',
    'AMZN': 'Amazon',
    'MELI': 'MercadoLibre',
    'KO': 'Coca-Cola',
  };

  @override
  Future<CompanyBrand?> getBrand(String ticker) async =>
      CompanyBrand(ticker: ticker, name: _names[ticker]);
}

class _Subscription extends StateNotifier<SubscriptionState>
    implements SubscriptionNotifier {
  _Subscription()
    : super(
        const SubscriptionState(
          tier: SubscriptionTier.premium,
          queriesUsed: 0,
          queriesLimit: 100,
        ),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<WatchlistItem> _items() {
  final now = DateTime.now();
  WatchlistItem item(String id, String s, double added, {bool notify = true}) =>
      WatchlistItem(
        id: id,
        symbol: s,
        addedPrice: added,
        createdAt: now.subtract(const Duration(days: 20)),
        notify: notify,
      );
  return [
    item('1', 'NVDA', 160),
    item('2', 'AMZN', 230),
    item('3', 'MELI', 1980),
    item('4', 'KO', 70.5, notify: false),
  ];
}

Widget _app(Brightness brightness, List<WatchlistItem> items) {
  final container = ProviderContainer();
  final theme = container.read(
    brightness == Brightness.light
        ? themeDataLightProvider
        : themeDataDarkProvider,
  );
  container.dispose();
  return ProviderScope(
    overrides: [
      watchlistRepositoryProvider.overrideWithValue(_Repo(items)),
      quoteRepositoryProvider.overrideWithValue(_Quotes()),
      subscriptionProvider.overrideWith((ref) => _Subscription()),
      goalHoldingsProvider.overrideWithValue(const {'MSFT': 3000}),
      symbolSearchRepositoryProvider.overrideWithValue(_Search()),
      companyBrandLoaderProvider.overrideWithValue(
        CompanyBrandLoader(_Brands()),
      ),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('es', 'ES')],
      locale: const Locale('es', 'ES'),
      builder:
          (context, child) => Stack(
            children: [
              const Positioned.fill(child: AppBackgroundGradient()),
              child!,
            ],
          ),
      home: const WatchlistScreen(),
    ),
  );
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundary,
  String name,
) async {
  final render =
      boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image =
      (await tester.runAsync(() => render.toImage(pixelRatio: _dpr)))!;
  final bytes =
      (await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.png),
      ))!;
  File('$_out/$name.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes.buffer.asUint8List());
}

void main() {
  setUpAll(() async {
    if (!_enabled) return;
    PortyAvatar.ambientMotion = false;
    GoogleFonts.config.allowRuntimeFetching = false;
    final es =
        jsonDecode(File('assets/translations/es-ES.json').readAsStringSync())
            as Map<String, dynamic>;
    Localization.load(const Locale('es', 'ES'), translations: Translations(es));
    await initializeDateFormatting('es_ES');
    Intl.defaultLocale = 'es_ES';
    await _loadFonts();
  });

  Future<void> setUp(WidgetTester tester, Brightness brightness) async {
    tester.view.physicalSize = _size * _dpr;
    tester.view.devicePixelRatio = _dpr;
    tester.view.padding = const FakeViewPadding(top: 47 * _dpr);
    tester.view.viewPadding = const FakeViewPadding(top: 47 * _dpr);
    tester.platformDispatcher.platformBrightnessTestValue = brightness;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump(const Duration(seconds: 2));
    }
  }

  final scenarios = <
    String,
    (List<WatchlistItem> Function(), Future<void> Function(WidgetTester)?)
  >{
    'empty': (() => [], null),
    'list': (_items, null),
    'actions': (
      _items,
      (t) async {
        await t.tap(find.textContaining('NVIDIA', findRichText: true).first);
      },
    ),
    'search': (
      _items,
      (t) async {
        await t.tap(find.byIcon(Icons.add_rounded).first);
        await t.pump(const Duration(seconds: 1));
        await t.enterText(find.byType(TextField), 'micro');
        await t.pump(const Duration(milliseconds: 400));
      },
    ),
  };

  for (final brightness in Brightness.values) {
    for (final MapEntry(key: name, value: (items, act)) in scenarios.entries) {
      final id = 'watchlist_${name}_${brightness.name}';
      testWidgets(id, (tester) async {
        await setUp(tester, brightness);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(key: boundary, child: _app(brightness, items())),
        );
        await settle(tester);
        if (act != null) {
          await act(tester);
          await settle(tester);
        }
        await _capture(tester, boundary, id);
      }, skip: !_enabled);
    }
  }
}
