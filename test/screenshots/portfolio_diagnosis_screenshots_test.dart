// Screenshots del primer diagnóstico de la cartera ("Lo que vi en tu
// cartera"): con cosas para marcar, una cartera que viene bien y una de 2
// posiciones (invita a sumar el resto). Claro y oscuro, iPhone SE y Pro,
// con fuentes y textos reales. No corre en la suite normal (escribe PNGs):
//
//   RUN_SCREENSHOTS=1 SCREENSHOTS_OUT=/tmp/shots \
//     flutter test test/screenshots/portfolio_diagnosis_screenshots_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

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
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/position_valuation.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_calculator.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/portfolio_diagnosis/domain/portfolio_diagnosis.dart';
import 'package:portfolio_assistant/features/portfolio_diagnosis/providers/portfolio_diagnosis_provider.dart';
import 'package:portfolio_assistant/features/portfolio_diagnosis/view/portfolio_diagnosis_screen.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/app_background_gradient.dart';

final _out = Platform.environment['SCREENSHOTS_OUT'] ?? 'build/screenshots';
final _enabled = Platform.environment['RUN_SCREENSHOTS'] == '1';

const _devices = {'se': (Size(375, 667), 2.0), 'pro': (Size(402, 874), 3.0)};

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

final _now = DateTime(2026, 10, 26);

PositionValuation _pos(
  String ticker,
  double value, {
  double gain = 1,
  DateTime? bought,
}) => PortfolioCalculator.valuate(
  position: Position(
    id: ticker,
    ticker: ticker,
    quantity: 1,
    purchasePrice: value / gain,
    purchaseDate: bought ?? DateTime(2025, 2, 3),
  ),
  currentPrice: value,
);

List<PriceCandle> _sp(double start, double end) {
  final from = DateTime(2025, 1, 1);
  final days = _now.difference(from).inDays;
  return [
    for (var i = 0; i <= days; i++)
      PriceCandle(
        date: from.add(Duration(days: i)),
        close: start + (end - start) * i / days,
      ),
  ];
}

const _voo = FundLook(
  holdings: {'NVDA': 7.2, 'AAPL': 6.6, 'MSFT': 6.1},
  sectors: {'Tecnología': 33, 'Finanzas': 13, 'Salud': 10},
  expenseRatioPct: 0.03,
  stockPct: 99.5,
);
const _qqq = FundLook(
  holdings: {'NVDA': 9.1, 'AAPL': 8.2, 'MSFT': 7.9},
  sectors: {'Tecnología': 61, 'Consumo cíclico': 18},
  expenseRatioPct: 0.2,
  stockPct: 100,
);

PortfolioDiagnosis _diagnosis(String scenario) {
  final positions = switch (scenario) {
    'attention' => [
      _pos('NVDA', 3200, gain: 2.4),
      _pos('QQQ', 4100, gain: 1.05),
      _pos('VOO', 2600, gain: 1.04),
      _pos('ARKK', 1500, gain: 0.7),
    ],
    'good' => [
      _pos('VOO', 3000, gain: 1.3),
      _pos('VXUS', 2000, gain: 1.25),
      _pos('BND', 1500, gain: 1.1),
      _pos('KO', 1000, gain: 1.2),
      _pos('JNJ', 1000, gain: 1.15),
    ],
    _ => [_pos('TSLA', 3800, gain: 1.6), _pos('KO', 900)],
  };
  return PortfolioDiagnosisBuilder.build(
    DiagnosisInputs(
      valuations: positions,
      lots: positions,
      sectorByTicker: const {
        'NVDA': 'Tecnología',
        'KO': 'Consumo defensivo',
        'JNJ': 'Salud',
        'TSLA': 'Consumo cíclico',
      },
      funds: {
        'QQQ': _qqq,
        'VOO': _voo,
        'ARKK': const FundLook(expenseRatioPct: 0.75, stockPct: 100),
        'VXUS': const FundLook(expenseRatioPct: 0.05, stockPct: 99),
        'BND': const FundLook(expenseRatioPct: 0.03, stockPct: 0),
      },
      sp500: scenario == 'good' ? _sp(100, 112) : _sp(100, 140),
      now: _now,
    ),
  );
}

Widget _app(Brightness brightness, PortfolioDiagnosis diagnosis) {
  final container = ProviderContainer();
  final theme = container.read(
    brightness == Brightness.light
        ? themeDataLightProvider
        : themeDataDarkProvider,
  );
  container.dispose();
  return ProviderScope(
    overrides: [
      portfolioDiagnosisProvider.overrideWith((ref) async => diagnosis),
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
      home: const PortfolioDiagnosisScreen(),
    ),
  );
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
    await _loadFonts();
  });

  for (final MapEntry(key: device, value: (size, dpr)) in _devices.entries) {
    for (final brightness in Brightness.values) {
      for (final scenario in ['attention', 'good', 'few']) {
        final id = 'diagnosis_${scenario}_${device}_${brightness.name}';
        testWidgets(id, (tester) async {
          tester.view.physicalSize = size * dpr;
          tester.view.devicePixelRatio = dpr;
          tester.view.padding = FakeViewPadding(
            top: 47 * dpr,
            bottom: 34 * dpr,
          );
          tester.view.viewPadding = FakeViewPadding(
            top: 47 * dpr,
            bottom: 34 * dpr,
          );
          tester.platformDispatcher.platformBrightnessTestValue = brightness;
          addTearDown(tester.view.reset);
          addTearDown(
            tester.platformDispatcher.clearPlatformBrightnessTestValue,
          );
          final boundary = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: _app(brightness, _diagnosis(scenario)),
            ),
          );
          for (var i = 0; i < 3; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 200)),
            );
            await tester.pump(const Duration(seconds: 1));
          }
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image =
              (await tester.runAsync(() => render.toImage(pixelRatio: dpr)))!;
          final bytes =
              (await tester.runAsync(
                () => image.toByteData(format: ui.ImageByteFormat.png),
              ))!;
          File('$_out/$id.png')
            ..createSync(recursive: true)
            ..writeAsBytesSync(bytes.buffer.asUint8List());
        }, skip: !_enabled);
      }
    }
  }
}
