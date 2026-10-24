// Screenshots de "Mi plan de cartera" (intro, los cuatro pasos del armado,
// el tablero dentro y fuera del plan y la hoja del próximo aporte), en
// claro y oscuro, con fuentes y textos reales. No corre en la suite normal
// (escribe PNGs):
//
//   RUN_SCREENSHOTS=1 SCREENSHOTS_OUT=/tmp/shots \
//     flutter test test/screenshots/allocation_screenshots_test.dart
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
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/allocation/data/allocation_repository.dart';
import 'package:portfolio_assistant/features/allocation/domain/allocation_plan.dart';
import 'package:portfolio_assistant/features/allocation/view/allocation_screen.dart';
import 'package:portfolio_assistant/features/allocation/view/allocation_wizard_screen.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/goals/providers/goals_provider.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/app_background_gradient.dart';

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

const _holdings = {'VOO': 5000.0, 'QQQ': 2200.0, 'BND': 1400.0, 'NVDA': 600.0};

const _plan = AllocationPlan(targets: {'VOO': 50, 'QQQ': 20, 'BND': 30});

/// El mismo plan con recordatorio de aporte (fase 6).
const _planReminder = AllocationPlan(
  targets: {'VOO': 50, 'QQQ': 20, 'BND': 30},
  contributionDay: 5,
  contributionAmount: 500,
);

/// Un plan que la cartera de [_holdings] cumple (dentro de ±10).
const _planOk = AllocationPlan(
  targets: {'VOO': 50, 'QQQ': 25, 'BND': 15, 'NVDA': 10},
  driftThreshold: 10,
  frequency: AllocationAlertFrequency.monthly,
);

class _Repo implements AllocationRepository {
  _Repo(this.stored);

  final AllocationPlan? stored;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<AllocationPlan?> load() async => stored;
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

Widget _app(Brightness brightness, Widget home, {AllocationPlan? stored}) {
  final container = ProviderContainer();
  final theme = container.read(
    brightness == Brightness.light
        ? themeDataLightProvider
        : themeDataDarkProvider,
  );
  container.dispose();
  return ProviderScope(
    overrides: [
      allocationRepositoryProvider.overrideWithValue(_Repo(stored)),
      goalHoldingsProvider.overrideWithValue(_holdings),
      subscriptionProvider.overrideWith((ref) => _Subscription()),
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
      home: home,
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

  final scenarios = <String, (Widget, AllocationPlan?, String?)>{
    'intro': (const AllocationScreen(), null, null),
    'step1_pick': (const AllocationWizardScreen(), null, null),
    'step2_split': (
      const AllocationWizardScreen(
        initial: _plan,
        startAt: AllocationStep.split,
      ),
      null,
      null,
    ),
    'step3_alerts': (
      const AllocationWizardScreen(
        initial: _plan,
        startAt: AllocationStep.alerts,
      ),
      null,
      null,
    ),
    'step3_alerts_reminder': (
      const AllocationWizardScreen(
        initial: _planReminder,
        startAt: AllocationStep.alerts,
      ),
      null,
      null,
    ),
    'step4_review_reminder': (
      const AllocationWizardScreen(
        initial: _planReminder,
        startAt: AllocationStep.review,
      ),
      null,
      null,
    ),
    'step4_review': (
      const AllocationWizardScreen(
        initial: _plan,
        startAt: AllocationStep.review,
      ),
      null,
      null,
    ),
    'dashboard_off': (const AllocationScreen(), _plan, null),
    'dashboard_ok': (const AllocationScreen(), _planOk, null),
    'contribution': (const AllocationScreen(), _plan, 'Calcular dónde ponerla'),
  };

  for (final brightness in Brightness.values) {
    for (final MapEntry(key: name, value: (home, stored, tap))
        in scenarios.entries) {
      final id = 'allocation_${name}_${brightness.name}';
      testWidgets(id, (tester) async {
        await setUp(tester, brightness);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: _app(brightness, home, stored: stored),
          ),
        );
        await settle(tester);
        // El recordatorio de aporte queda al final del paso de avisos.
        if (name == 'step3_alerts_reminder') {
          await tester.scrollUntilVisible(
            find.text('Monto (opcional)'),
            300,
            scrollable: find.byType(Scrollable).last,
          );
          await tester.drag(find.byType(Scrollable).last, const Offset(0, -150));
          await settle(tester);
        }
        if (tap != null) {
          await tester.tap(find.text(tap));
          await settle(tester);
          await tester.enterText(find.byType(TextField), '1000');
          await settle(tester);
        }
        await _capture(tester, boundary, id);
      }, skip: !_enabled);
    }
  }
}
