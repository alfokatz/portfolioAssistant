// Screenshots del paywall (Ajustes con precios mensuales, tope de
// posiciones con el selector en Anual y consultas agotadas con el
// medidor), en claro y oscuro, iPhone SE, Pro y la hoja entera a 375 de
// ancho, con fuentes y textos reales. No corre en la suite normal:
//
//   RUN_SCREENSHOTS=1 SCREENSHOTS_OUT=/tmp/shots \
//     flutter test test/screenshots/paywall_screenshots_test.dart
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
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/ui/subscription_paywall_sheet.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/app_background_gradient.dart';

import '../features/subscription/paywall_test_harness.dart';

final _out = Platform.environment['SCREENSHOTS_OUT'] ?? 'build/screenshots';
final _enabled = Platform.environment['RUN_SCREENSHOTS'] == '1';

/// SE y Pro como el resto; `full` es la hoja entera (sin scroll) a 375.
const _devices = {
  'se': (Size(375, 667), 2.0),
  'pro': (Size(402, 874), 3.0),
  'full': (Size(375, 1720), 2.0),
};

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

typedef _Scenario =
    ({
      PaywallHarness Function() harness,
      PaywallReason reason,
      String source,
      bool annual,
    });

final _scenarios = <String, _Scenario>{
  'plans_monthly': (
    harness: () => PaywallHarness(offer: monthlyOffer),
    reason: PaywallReason.plans,
    source: 'settings',
    annual: false,
  ),
  'position_limit_annual': (
    harness: () => PaywallHarness(offer: fullOffer, annualEnabled: true),
    reason: PaywallReason.positionLimit,
    source: 'add_position_limit',
    annual: true,
  ),
  'quota_no_prices': (
    harness: () => PaywallHarness(used: 20, limit: 20),
    reason: PaywallReason.quotaExceeded,
    source: 'quota_zero',
    annual: false,
  ),
};

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundary,
  String name,
  double dpr,
) async {
  final render =
      boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image =
      (await tester.runAsync(() => render.toImage(pixelRatio: dpr)))!;
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
    await _loadFonts();
  });

  for (final MapEntry(key: device, value: (size, dpr)) in _devices.entries) {
    for (final brightness in Brightness.values) {
      for (final MapEntry(key: name, value: s) in _scenarios.entries) {
        final id = 'paywall_${name}_${device}_${brightness.name}';
        testWidgets(id, (tester) async {
          tester.view.physicalSize = size * dpr;
          tester.view.devicePixelRatio = dpr;
          tester.view.padding = FakeViewPadding(top: 47 * dpr);
          tester.view.viewPadding = FakeViewPadding(top: 47 * dpr);
          tester.platformDispatcher.platformBrightnessTestValue = brightness;
          addTearDown(tester.view.reset);
          addTearDown(
            tester.platformDispatcher.clearPlatformBrightnessTestValue,
          );

          final themes = ProviderContainer();
          addTearDown(themes.dispose);
          final theme = themes.read(
            brightness == Brightness.light
                ? themeDataLightProvider
                : themeDataDarkProvider,
          );
          final h = s.harness();
          final boundary = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: ProviderScope(
                overrides: h.overrides,
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: theme,
                  localizationsDelegates:
                      GlobalMaterialLocalizations.delegates,
                  supportedLocales: const [Locale('es', 'ES')],
                  locale: const Locale('es', 'ES'),
                  builder:
                      (context, child) => Stack(
                        children: [
                          const Positioned.fill(
                            child: AppBackgroundGradient(),
                          ),
                          child!,
                        ],
                      ),
                  home: Consumer(
                    builder:
                        (context, ref, _) => Scaffold(
                          backgroundColor: Colors.transparent,
                          body: Center(
                            child: TextButton(
                              onPressed:
                                  () => SubscriptionPaywallSheet.show(
                                    context,
                                    ref,
                                    reason: s.reason,
                                    source: s.source,
                                  ),
                              child: const Text('open'),
                            ),
                          ),
                        ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump();
          await h.open(tester);
          if (s.annual) {
            await tester.tap(find.text('Anual'));
            await tester.pump(const Duration(milliseconds: 400));
          }
          await tester.pump(const Duration(seconds: 1));
          await _capture(tester, boundary, id, dpr);
        }, skip: !_enabled);
      }
    }
  }
}
