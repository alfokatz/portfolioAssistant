// Screenshots de lo que la Home ofrece sola: volver a ver los hallazgos de
// Porty y las dos hojas de notificaciones (ofrecerlas y, si se rechazaron,
// cómo prenderlas). Claro y oscuro, iPhone SE y Pro. No corre en la suite
// normal (escribe PNGs):
//
//   RUN_SCREENSHOTS=1 SCREENSHOTS_OUT=/tmp/shots \
//     flutter test test/screenshots/home_prompts_screenshots_test.dart
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
import 'package:portfolio_assistant/domain/utils/portfolio_calculator.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/notifications/view/push_permission_sheet.dart';
import 'package:portfolio_assistant/features/notifications/view/push_settings_sheet.dart';
import 'package:portfolio_assistant/features/portfolio_diagnosis/view/widgets/diagnosis_revisit_card.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';
import 'package:portfolio_assistant/presentation/flows/home/states/home_state.dart';
import 'package:portfolio_assistant/features/portfolio_diagnosis/providers/portfolio_diagnosis_provider.dart';
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

class _Home extends StateNotifier<HomeState> implements HomeProvider {
  _Home(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Seen extends DiagnosisSeenNotifier {
  _Seen() : super(null, null) {
    state = true;
  }
}

final _home = HomeState(
  loading: false,
  summary: PortfolioSummary(
    totalValue: 1000,
    totalCostBasis: 900,
    totalPnlAbsolute: 100,
    totalPnlPercent: 11,
    valuations: [
      PortfolioCalculator.valuate(
        position: Position(
          id: 'a',
          ticker: 'AAPL',
          quantity: 1,
          purchasePrice: 900,
          purchaseDate: DateTime(2025),
        ),
        currentPrice: 1000,
      ),
    ],
  ),
);

/// Una hoja como la muestra showModalBottomSheet: abajo, con la superficie y
/// el radio del tema, sobre la Home oscurecida.
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final sheet = Theme.of(context).bottomSheetTheme;
    return ColoredBox(
      color: Colors.black54,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Material(
          color: sheet.backgroundColor ?? context.customColors.surfaceCard,
          shape: sheet.shape,
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 22),
              Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: context.customColors.textSecondary.withValues(
                    alpha: 0.4,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

Widget _screen(String scenario) => switch (scenario) {
  'revisit' => const Scaffold(
    backgroundColor: Colors.transparent,
    body: SafeArea(
      child: Column(
        children: [SizedBox(height: 24), DiagnosisRevisitCard()],
      ),
    ),
  ),
  'welcome' => const _SheetFrame(
    child: PushPermissionSheet(reason: PushPromptReason.welcome),
  ),
  _ => const _SheetFrame(child: PushSettingsSheet()),
};

Widget _app(Brightness brightness, String scenario) {
  final container = ProviderContainer();
  final theme = container.read(
    brightness == Brightness.light
        ? themeDataLightProvider
        : themeDataDarkProvider,
  );
  container.dispose();
  return ProviderScope(
    overrides: [
      homeProvider.overrideWith((ref) => _Home(_home)),
      diagnosisSeenProvider.overrideWith((ref) => _Seen()),
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
      home: _screen(scenario),
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
      for (final scenario in ['revisit', 'welcome', 'settings']) {
        final id = 'home_prompt_${scenario}_${device}_${brightness.name}';
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
              child: _app(brightness, scenario),
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
