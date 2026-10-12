import 'dart:io';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/investor_profile.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/goal_status_widgets.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/savings_plan_calculator.dart';
import 'package:portfolio_assistant/features/goals/domain/goal_progress.dart';
import 'package:portfolio_assistant/features/goals/domain/user_goal.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';

import '../../goals/goal_detail_screen_test.dart' show loadSpanish;

/// "Viaje a Japón": 18.000 $ para febrero de 2028, con 4.500 $ juntados
/// (el caso del bug: Porty contestaba con el plan inicial desde 0 $).
UserGoal _trip(DateTime now) => UserGoal(
  id: 'trip',
  label: 'Viaje a Japón',
  type: GoalType.purchase,
  targetAmount: 18000,
  targetDate: DateTime(now.year + 1, now.month + 4, now.day),
  snapshot: GoalPlanSnapshot(
    inputs: SavingsPlanInputs(
      targetAmount: 18000,
      months: 16,
      currentAmount: 4500,
      risk: RiskTolerance.conservative,
      startDate: DateTime(now.year, now.month, now.day),
      shortTerm: true,
    ),
  ),
  status: GoalStatus.active,
  createdAt: now,
  externalSavings: 4500,
);

Future<void> _fonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(File(f).readAsBytes().then((b) => ByteData.view(b.buffer)));
    }
    await loader.load();
  }

  final sdk = Platform.environment['FLUTTER_ROOT']!;
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

void main() {
  setUpAll(loadSpanish);

  for (final b in Brightness.values) {
    testWidgets('the saved goal as it is today (${b.name}): what it has, '
        'the monthly amount and a way to open it', (tester) async {
      final shots = Platform.environment['SCREENSHOTS_OUT'];
      if (shots != null) await tester.runAsync(_fonts);
      await tester.binding.setSurfaceSize(const Size(390, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      QaColors.resolve(b);
      addTearDown(() => QaColors.resolve(Brightness.light));
      final now = DateTime.now();
      final goal = _trip(now);
      final progress = GoalProgress.of(goal, now);
      var opened = false;
      final key = GlobalKey();
      final theme = ProviderContainer().read(
        b == Brightness.dark ? themeDataDarkProvider : themeDataLightProvider,
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme,
            home: Scaffold(
              backgroundColor: theme.colorScheme.surface,
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: QaGoalStatusCard(
                  goal: goal,
                  progress: progress,
                  onOpen: () => opened = true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Viaje a Japón'), findsOneWidget);
      expect(find.text(QaFormat.money(4500)), findsOneWidget);
      expect(find.text('25%'), findsOneWidget);
      expect(
        find.text('goal_status_${progress.status.key}'.tr()),
        findsOneWidget,
      );
      await tester.tap(find.text('Ver meta'));
      expect(opened, isTrue);

      if (shots != null) {
        final render =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image =
            (await tester.runAsync(() => render.toImage(pixelRatio: 2)))!;
        final bytes =
            (await tester.runAsync(
              () => image.toByteData(format: ui.ImageByteFormat.png),
            ))!;
        File('$shots/goal_status_${b.name}.png')
          ..createSync(recursive: true)
          ..writeAsBytesSync(bytes.buffer.asUint8List());
      }
    });
  }
}
