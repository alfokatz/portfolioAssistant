// Screenshots de los loaders (Home en skeleton y con datos, PortyLoader y el
// primer frame del arranque) con fuentes y textos reales. No corre en la
// suite normal (escribe PNGs):
//
//   RUN_SCREENSHOTS=1 SCREENSHOTS_OUT=/tmp/shots \
//     flutter test test/screenshots/loaders_screenshots_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
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
import 'package:portfolio_assistant/domain/entities/portfolio_history_point.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/position_valuation.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:portfolio_assistant/presentation/shared/loading/app_bootstrap.dart';
import 'package:portfolio_assistant/presentation/shared/loading/porty_loader.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../presentation/flows/home/home_loading_test.dart' show HomeTestHarness;

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

PositionValuation _valuation(String ticker, double qty, double buy, double now) {
  final value = qty * now;
  return PositionValuation(
    position: Position(
      id: ticker,
      ticker: ticker,
      quantity: qty,
      purchasePrice: buy,
      purchaseDate: DateTime(2026, 3, 2),
    ),
    currentPrice: now,
    marketValue: value,
    pnlAbsolute: value - qty * buy,
    pnlPercent: (now - buy) / buy * 100,
  );
}

PortfolioSummary _portfolio() {
  final valuations = [
    _valuation('NVDA', 12, 96, 131.4),
    _valuation('AAPL', 8, 189, 226.1),
    _valuation('MSFT', 4, 402, 418.7),
    _valuation('KO', 20, 64, 61.9),
    _valuation('VOO', 3, 480, 512.3),
  ];
  final total = valuations.fold(0.0, (s, v) => s + v.marketValue);
  final cost = valuations.fold(
    0.0,
    (s, v) => s + v.position.quantity * v.position.purchasePrice,
  );
  return PortfolioSummary(
    totalValue: total,
    totalCostBasis: cost,
    totalPnlAbsolute: total - cost,
    totalPnlPercent: (total - cost) / cost * 100,
    valuations: valuations,
    lots: valuations,
  );
}

List<PortfolioHistoryPoint> _history(PortfolioSummary s) => [
  for (var d = 0; d < 32; d++)
    PortfolioHistoryPoint(
      date: DateTime(2026, 9, 3).add(Duration(days: d)),
      totalValue:
          s.totalValue * (0.93 + 0.07 * d / 31 + 0.012 * ((d * 7) % 5 - 2) / 2),
      totalCostBasis: s.totalCostBasis,
    ),
];

Widget _themed(Brightness brightness, Widget home) {
  final container = ProviderContainer();
  final theme = container.read(
    brightness == Brightness.light
        ? themeDataLightProvider
        : themeDataDarkProvider,
  );
  container.dispose();
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: theme,
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    supportedLocales: const [Locale('es', 'ES')],
    locale: const Locale('es', 'ES'),
    home: home,
  );
}

Future<void> _capture(WidgetTester tester, GlobalKey boundary, String name) async {
  final render =
      boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = (await tester.runAsync(() => render.toImage(pixelRatio: _dpr)))!;
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
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    final es =
        jsonDecode(File('assets/translations/es-ES.json').readAsStringSync())
            as Map<String, dynamic>;
    Localization.load(const Locale('es', 'ES'), translations: Translations(es));
    await initializeDateFormatting('es_ES');
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

  Future<void> fonts(WidgetTester tester) => tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 300)),
  );

  for (final brightness in Brightness.values) {
    final b = brightness.name;

    testWidgets('home_skeleton_$b', (tester) async {
      await setUp(tester, brightness);
      final boundary = GlobalKey();
      final h = HomeTestHarness();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: h.app(
            brightness: brightness,
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            supportedLocales: const [Locale('es', 'ES')],
            locale: const Locale('es', 'ES'),
          ),
        ),
      );
      await fonts(tester);
      await tester.pump();
      // Pasada la espera de 300 ms, en el punto del pulso de opacidad 1.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 2800));
      await _capture(tester, boundary, 'home_skeleton_$b');
      h.summary.complete(_portfolio());
      await tester.pump(const Duration(seconds: 1));
    }, skip: !_enabled);

    testWidgets('home_data_$b', (tester) async {
      await setUp(tester, brightness);
      final boundary = GlobalKey();
      final summary = _portfolio();
      final h = HomeTestHarness(history: _history(summary));
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: h.app(
            brightness: brightness,
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            supportedLocales: const [Locale('es', 'ES')],
            locale: const Locale('es', 'ES'),
          ),
        ),
      );
      await fonts(tester);
      await tester.pump();
      h.summary.complete(summary);
      await tester.pump();
      await tester.pumpAndSettle();
      await _capture(tester, boundary, 'home_data_$b');
    }, skip: !_enabled);

    testWidgets('porty_loader_$b', (tester) async {
      await setUp(tester, brightness);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: _themed(
            brightness,
            Scaffold(
              body: PortyLoader(message: 'loader_preparing_portfolio'.tr()),
            ),
          ),
        ),
      );
      await fonts(tester);
      await tester.pump();
      // Con la línea ya visible (pasaron 2 s).
      await tester.pump(const Duration(milliseconds: 2100));
      await tester.pump(const Duration(milliseconds: 500)); // fade de la línea
      await _capture(tester, boundary, 'porty_loader_$b');
    }, skip: !_enabled);

    testWidgets('boot_first_frame_$b', (tester) async {
      await setUp(tester, brightness);
      final boundary = GlobalKey();
      final never = Completer<Widget>();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: AppBootstrap(initialize: () => never.future),
        ),
      );
      await fonts(tester);
      // El primer frame: Porty en reposo, igual que el splash nativo.
      await _capture(tester, boundary, 'boot_first_frame_$b');
    }, skip: !_enabled);

    testWidgets('boot_loading_$b', (tester) async {
      await setUp(tester, brightness);
      final boundary = GlobalKey();
      final never = Completer<Widget>();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: AppBootstrap(initialize: () => never.future),
        ),
      );
      await fonts(tester);
      // Ya pensando con el pulso y con la primera frase de carga.
      for (var i = 0; i < 90; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await _capture(tester, boundary, 'boot_loading_$b');
      // Desmontar cancela los timers de las frases.
      await tester.pumpWidget(const SizedBox());
    }, skip: !_enabled);
  }
}
