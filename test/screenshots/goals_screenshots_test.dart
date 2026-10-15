// Screenshots de la pestaña Metas (con metas en camino, con una atrasada y
// una cumplida, sin metas y cargando), en claro y oscuro, con fuentes y
// textos reales. No corre en la suite normal (escribe PNGs):
//
//   RUN_SCREENSHOTS=1 SCREENSHOTS_OUT=/tmp/shots \
//     flutter test test/screenshots/goals_screenshots_test.dart
import 'dart:async';
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
import 'package:portfolio_assistant/domain/entities/investor_profile.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/savings_plan_calculator.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/goals/data/goals_repository.dart';
import 'package:portfolio_assistant/features/goals/domain/user_goal.dart';
import 'package:portfolio_assistant/features/goals/providers/goals_provider.dart';
import 'package:portfolio_assistant/features/goals/view/goals_screen.dart';
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

/// Una meta de ejemplo: [monthsAgo] = cuándo se guardó; [saved] = lo que
/// lleva (como ahorro de afuera, sin inversiones asignadas).
UserGoal _goal(
  String id,
  String label,
  double target, {
  required int months,
  int monthsAgo = 0,
  double saved = 0,
  GoalType type = GoalType.purchase,
  GoalStatus status = GoalStatus.active,
  bool savedAtStart = false,
}) {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month - monthsAgo, now.day);
  return UserGoal(
    id: id,
    label: label,
    type: type,
    targetAmount: target,
    targetDate: DateTime(start.year, start.month + months, start.day),
    snapshot: GoalPlanSnapshot(
      inputs: SavingsPlanInputs(
        targetAmount: target,
        months: months,
        // Lo que ya tenía al guardarla cuenta en el plan (como al guardar
        // una meta con ahorros previos): queda "en camino".
        currentAmount: savedAtStart ? saved : 0,
        risk: RiskTolerance.moderate,
        startDate: start,
      ),
    ),
    status: status,
    createdAt: start,
    externalSavings: saved,
  );
}

/// Las metas de la captura del usuario (tres en camino, una recién
/// guardada).
List<UserGoal> _onTrack() => [
  _goal(
    'a',
    'Juntar 10.000 USD',
    10000,
    months: 24,
    saved: 202,
    savedAtStart: true,
  ),
  _goal('b', 'Auto', 20000, months: 36, saved: 271, savedAtStart: true),
  _goal(
    'c',
    'Viaje a Japón',
    18000,
    months: 16,
    saved: 1027,
    savedAtStart: true,
  ),
  _goal('d', 'MacBook M5 Pro', 2300, months: 12),
];

/// Una atrasada, una adelantada y una cumplida.
List<UserGoal> _mixed() => [
  _goal('a', 'Viaje a Japón', 18000, months: 16, monthsAgo: 4, saved: 1500),
  _goal(
    'b',
    'Fondo de emergencia',
    6000,
    months: 12,
    monthsAgo: 3,
    saved: 2400,
  ),
  _goal(
    'c',
    'Jubilación',
    300000,
    months: 300,
    monthsAgo: 2,
    saved: 900,
    type: GoalType.retirement,
  ),
  _goal(
    'd',
    'MacBook M5 Pro',
    2300,
    months: 12,
    monthsAgo: 10,
    saved: 2300,
    status: GoalStatus.achieved,
  ),
];

class _Repo extends GoalsRepository {
  _Repo(this.goals, {this.hang = false}) : super(client: () => null);

  final List<UserGoal> goals;
  final bool hang;

  @override
  Future<List<UserGoal>> list() =>
      hang ? Completer<List<UserGoal>>().future : Future.value([...goals]);
}

Widget _app(Brightness brightness, _Repo repo) {
  final container = ProviderContainer();
  final theme = container.read(
    brightness == Brightness.light
        ? themeDataLightProvider
        : themeDataDarkProvider,
  );
  container.dispose();
  return ProviderScope(
    overrides: [
      goalsProvider.overrideWith((ref) => GoalsNotifier(repo)),
      goalHoldingsProvider.overrideWithValue(const {}),
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
      home: const GoalsScreen(),
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
    // Como la app en español: "18.000 \$".
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

  final scenarios = <String, _Repo Function()>{
    'on_track': () => _Repo(_onTrack()),
    'mixed': () => _Repo(_mixed()),
    'empty': () => _Repo(const []),
    'loading': () => _Repo(const [], hang: true),
  };

  for (final brightness in Brightness.values) {
    for (final MapEntry(key: name, value: repo) in scenarios.entries) {
      final id = 'goals_${name}_${brightness.name}';
      testWidgets(id, (tester) async {
        await setUp(tester, brightness);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(key: boundary, child: _app(brightness, repo())),
        );
        await settle(tester);
        await _capture(tester, boundary, id);
      }, skip: !_enabled);
    }
  }
}
