// Screenshots de las pantallas Flutter del widget de inicio (hoja de alta en
// sus tres variantes, filas de Ajustes, hoja de novedades y la línea "Hoy"),
// claro/oscuro x SE/Pro, con fuentes y textos reales. Correr:
//
//   RUN_SCREENSHOTS=1 SCREENSHOTS_OUT=/tmp/shots \
//     flutter test test/screenshots/home_widget_screenshots_test.dart
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
// ignore: depend_on_referenced_packages
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_history_point.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_day_move.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/home_widget/data/home_widget_store.dart';
import 'package:portfolio_assistant/features/home_widget/data/widget_items_cache.dart';
import 'package:portfolio_assistant/features/home_widget/view/widget_add_sheet.dart';
import 'package:portfolio_assistant/features/home_widget/view/widget_add_tile.dart';
import 'package:portfolio_assistant/features/home_widget/view/widget_positions_tile.dart';
import 'package:portfolio_assistant/features/home_widget/view/widget_news_sheet.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:portfolio_assistant/presentation/flows/home/models/chart_time_range.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/portfolio_hero_section.dart';
import 'package:portfolio_assistant/presentation/flows/settings/ui/widgets/settings_section_card.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/app_background_gradient.dart';

import '../features/home_widget/home_widget_test_helpers.dart';

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

final _now = DateTime(2026, 11, 5, 12);

final _items = [
  WidgetCachedItem(
    id: 'a1',
    kind: 'news',
    ticker: 'AAPL',
    headline: 'Apple presenta nuevos chips y mejora sus previsiones de ventas',
    source: 'Reuters',
    url: 'https://example.com/a',
    publishedAt: _now.subtract(const Duration(hours: 3)),
    expiresAt: _now.add(const Duration(hours: 45)),
  ),
  WidgetCachedItem(
    id: 'e1',
    kind: 'earnings',
    ticker: 'MSFT',
    date: DateTime(2026, 11, 9),
    expiresAt: DateTime(2026, 11, 9, 23, 59, 59),
  ),
  WidgetCachedItem(
    id: 'a2',
    kind: 'news',
    ticker: 'NVDA',
    headline: 'Nvidia amplía su acuerdo con proveedores de memoria',
    source: 'Bloomberg',
    url: 'https://example.com/b',
    publishedAt: _now.subtract(const Duration(hours: 9)),
    expiresAt: _now.add(const Duration(hours: 39)),
  ),
];

Map<String, Object?> _snapshot() => {
  'state': 'ready',
  'total_text': r'$12,480.00',
  'change_text': r'+$125.30',
  'change_pct_text': '+1.0%',
  'direction': 'up',
  'phrase': 'Tu cartera sube hoy; NVDA sumó más.',
  'period': 'today',
  'labels': {'period_today': 'Hoy', 'hidden_amount': '••••'},
};

ThemeData _theme(Brightness b) {
  final c = ProviderContainer();
  final t = c.read(
    b == Brightness.light ? themeDataLightProvider : themeDataDarkProvider,
  );
  c.dispose();
  return t;
}

Widget _app(
  Brightness b,
  Widget home, {
  List<Override> overrides = const [],
}) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: _theme(b),
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
    home: home,
  ),
);

Future<void> _capture(WidgetTester tester, GlobalKey k, String name) async {
  final render = k.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final dpr = tester.view.devicePixelRatio;
  final image = (await tester.runAsync(() => render.toImage(pixelRatio: dpr)))!;
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

  Future<void> setUpView(
    WidgetTester t,
    Size size,
    double dpr,
    Brightness b,
  ) async {
    t.view.physicalSize = size * dpr;
    t.view.devicePixelRatio = dpr;
    t.view.padding = FakeViewPadding(top: 47 * dpr);
    t.view.viewPadding = FakeViewPadding(top: 47 * dpr);
    t.platformDispatcher.platformBrightnessTestValue = b;
    addTearDown(t.view.reset);
    addTearDown(t.platformDispatcher.clearPlatformBrightnessTestValue);
  }

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 3; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await t.pump(const Duration(seconds: 1));
    }
  }

  for (final b in Brightness.values) {
    for (final MapEntry(key: dev, value: (size, dpr)) in _devices.entries) {
      final suffix = '${b.name}_$dev';

      // Hoja de alta: se abre con showModalBottomSheet; con [tapAdd] toca
      // "Agregar" para ver los pasos.
      for (final platform in ['ios', 'android_pin', 'android_manual']) {
        for (final tapAdd in [false, true]) {
          if (tapAdd && platform == 'android_pin') continue;
          final id = 'add_${tapAdd ? 'steps' : 'offer'}_${platform}_$suffix';
          testWidgets(id, (t) async {
            final store =
                FakeHomeWidgetStore(installed: const [])
                  ..platformName = platform == 'ios' ? 'ios' : 'android'
                  ..pinSupported = platform == 'android_pin'
                  ..snapshotJson = _snapshot();
            await setUpView(t, size, dpr, b);
            final key = GlobalKey();
            await t.pumpWidget(
              RepaintBoundary(
                key: key,
                child: _app(
                  b,
                  Consumer(
                    builder:
                        (context, ref, _) => Scaffold(
                          body: TextButton(
                            onPressed:
                                () => WidgetAddSheet.show(
                                  context,
                                  ref,
                                  source: WidgetPromptSource.auto,
                                ),
                            child: const Text('abrir'),
                          ),
                        ),
                  ),
                  overrides: [homeWidgetStoreProvider.overrideWithValue(store)],
                ),
              ),
            );
            await t.tap(find.text('abrir'));
            await settle(t);
            if (tapAdd) {
              await t.tap(find.text('Agregar'));
              await settle(t);
            }
            await _capture(t, key, id);
          }, skip: !_enabled);
        }
      }

      for (final installed in [false, true]) {
        final id = 'settings_${installed ? 'installed' : 'idle'}_$suffix';
        testWidgets(id, (t) async {
          await setUpView(t, size, dpr, b);
          SharedPreferences.setMockInitialValues({});
          final prefs = await SharedPreferences.getInstance();
          final key = GlobalKey();
          await t.pumpWidget(
            RepaintBoundary(
              key: key,
              child: _app(
                b,
                const Scaffold(
                  body: SafeArea(
                    child: Column(
                      children: [
                        SettingsDivider(),
                        WidgetAddTile(),
                        SettingsDivider(),
                        WidgetPositionsTile(),
                        SettingsDivider(),
                      ],
                    ),
                  ),
                ),
                overrides: [
                  sharedPreferencesProvider.overrideWithValue(prefs),
                  homeWidgetStoreProvider.overrideWithValue(
                    FakeHomeWidgetStore(
                      installed: installed ? const ['medium'] : const [],
                    ),
                  ),
                ],
              ),
            ),
          );
          await settle(t);
          await _capture(t, key, id);
        }, skip: !_enabled);
      }

      for (final locked in <WidgetLockedKind?>[
        null,
        WidgetLockedKind.news,
        WidgetLockedKind.earnings,
      ]) {
        final id = 'news_sheet_${locked?.name ?? 'items'}_$suffix';
        testWidgets(id, (t) async {
          await setUpView(t, size, dpr, b);
          final key = GlobalKey();
          await t.pumpWidget(
            RepaintBoundary(
              key: key,
              child: _app(
                b,
                Scaffold(
                  body: Align(
                    alignment: Alignment.bottomCenter,
                    child: Material(
                      color: _theme(b).colorScheme.surface,
                      child: WidgetNewsSheet(
                        items: _items,
                        now: _now,
                        locked: locked,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await settle(t);
          await _capture(t, key, id);
        }, skip: !_enabled);
      }

      testWidgets('day_move_$suffix', (t) async {
        await setUpView(t, size, dpr, b);
        final key = GlobalKey();
        final history = [
          for (var i = 0; i < 20; i++)
            PortfolioHistoryPoint(
              date: DateTime(2026, 10, 15 + i),
              totalValue: 12000 + i * 25.0,
              totalCostBasis: 11000,
            ),
        ];
        await t.pumpWidget(
          RepaintBoundary(
            key: key,
            child: _app(
              b,
              Scaffold(
                body: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: PortfolioHeroSection(
                      summary: const PortfolioSummary(
                        totalValue: 12480,
                        totalCostBasis: 11000,
                        totalPnlAbsolute: 1480,
                        totalPnlPercent: 13.4,
                        valuations: [],
                      ),
                      history: history,
                      periodPnlAbsolute: 480,
                      periodPnlPercent: 4.0,
                      selectedRange: ChartTimeRange.m1,
                      onRangeSelected: (_) {},
                      dayMove: const PortfolioDayMove(
                        absolute: 125.3,
                        percent: 1.0,
                        period: DayMovePeriod.today,
                        asOfDay: null,
                        topContributor: null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await settle(t);
        await _capture(t, key, 'day_move_$suffix');
      }, skip: !_enabled);
    }
  }
}
