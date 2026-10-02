// Screenshots del informe semanal con fuentes y textos reales. No corre en la
// suite normal (escribe PNGs):
//
//   RUN_SCREENSHOTS=1 SCREENSHOTS_OUT=/tmp/shots \
//     flutter test test/screenshots/weekly_report_screenshots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'dart:convert';

// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart';
// Viene con el SDK (y con easy_localization); solo para estos screenshots.
// ignore: depend_on_referenced_packages
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/weekly_report/weekly_report_ui_test.dart' as ui_test;
import 'package:portfolio_assistant/features/weekly_report/domain/weekly_report.dart';
import 'package:portfolio_assistant/features/weekly_report/providers/weekly_report_controller.dart';

final _out = Platform.environment['SCREENSHOTS_OUT'] ?? 'build/screenshots';
final _enabled = Platform.environment['RUN_SCREENSHOTS'] == '1';

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
    // google_fonts registra una familia por peso ("PlusJakartaSans_500").
    await load('PlusJakartaSans_${w == 400 ? 'regular' : w}', [file]);
    await load('Plus Jakarta Sans', [file]);
  }
}

/// Escena → widget a capturar.
typedef _Scene =
    ({
      String name,
      WeeklyReportState state,
      bool screen,
      bool benchmark,
      bool fullPage,
    });

final List<_Scene> _scenes = [
  (
    name: 'card_loading',
    state: const WeeklyReportState(
      status: WeeklyReportStatus.loading,
      generating: true,
    ),
    screen: false,
    benchmark: true,
    fullPage: false,
  ),
  (
    name: 'card_ready',
    state: ui_test.ready(ui_test.fullReport(), seen: true),
    screen: false,
    benchmark: true,
    fullPage: false,
  ),
  (
    name: 'card_free',
    state: ui_test.ready(
      ui_test.numbersReport(WeeklyReportVariant.numbersLocked),
      seen: true,
    ),
    screen: false,
    benchmark: false,
    fullPage: false,
  ),
  (
    name: 'screen_full',
    state: ui_test.ready(ui_test.fullReport(courtesy: true), seen: true),
    screen: true,
    benchmark: true,
    fullPage: false,
  ),
  (
    name: 'screen_full_page',
    state: ui_test.ready(ui_test.fullReport(), seen: true),
    screen: true,
    benchmark: true,
    fullPage: true,
  ),
  (
    name: 'screen_free_page',
    state: ui_test.ready(
      ui_test.numbersReport(WeeklyReportVariant.numbersLocked),
      seen: true,
    ),
    screen: true,
    benchmark: false,
    fullPage: true,
  ),
];

const _devices = {'se': (Size(375, 667), 2.0), 'pro': (Size(402, 874), 3.0)};

void main() {
  setUpAll(() async {
    if (!_enabled) return;
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    // Textos reales en español, cargados una vez (lo que lee `.tr()`).
    final es =
        jsonDecode(File('assets/translations/es-ES.json').readAsStringSync())
            as Map<String, dynamic>;
    Localization.load(const Locale('es', 'ES'), translations: Translations(es));
    await initializeDateFormatting('es_ES');
    await _loadFonts();
  });

  for (final scene in _scenes) {
    for (final brightness in Brightness.values) {
      for (final MapEntry(key: device, value: (size, dpr))
          in _devices.entries) {
        if (scene.fullPage && device == 'pro') continue;
        final name = '${scene.name}_${brightness.name}_$device';
        testWidgets(name, (tester) async {
          final logical = scene.fullPage ? Size(size.width, 2200) : size;
          tester.view.physicalSize = logical * dpr;
          tester.view.devicePixelRatio = dpr;
          tester.view.padding = FakeViewPadding(top: 47 * dpr);
          tester.view.viewPadding = FakeViewPadding(top: 47 * dpr);
          addTearDown(tester.view.reset);

          final boundary = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: ui_test.reportApp(
                ui_test.FixedWeeklyReportController(scene.state),
                benchmarkAllowed: scene.benchmark,
                openScreen: scene.screen,
                brightness: brightness,
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                supportedLocales: const [Locale('es', 'ES')],
                locale: const Locale('es', 'ES'),
              ),
            ),
          );
          // google_fonts resuelve sus familias de forma asíncrona.
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 300)),
          );
          await tester.pumpAndSettle();
          await tester.pump(const Duration(milliseconds: 500));

          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image =
              (await tester.runAsync(() => render.toImage(pixelRatio: dpr)))!;
          final bytes =
              (await tester.runAsync(
                () => image.toByteData(format: ui.ImageByteFormat.png),
              ))!;
          File('$_out/$name.png')
            ..createSync(recursive: true)
            ..writeAsBytesSync(bytes.buffer.asUint8List());
        }, skip: !_enabled);
      }
    }
  }
}
