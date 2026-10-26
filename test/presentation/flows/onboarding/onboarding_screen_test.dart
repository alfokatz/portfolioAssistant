import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/onboarding_screen.dart';

/// Sin easy_localization cargado, `.tr()` devuelve la key: los textos se
/// buscan por key.
const _start = 'onboarding_start';

/// iPhone SE (2.ª/3.ª gen.) en puntos.
const _seSize = Size(375, 667);

Widget _app({double textScale = 1}) {
  final container = ProviderContainer();
  final theme = container.read(themeDataLightProvider);
  container.dispose();
  return ProviderScope(
    child: MaterialApp(
      theme: theme,
      builder:
          (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
      home: const OnboardingScreen(),
    ),
  );
}

void main() {
  setUpAll(() => PortyAvatar.ambientMotion = false);

  void setSize(WidgetTester tester) {
    tester.view.physicalSize = _seSize * tester.view.devicePixelRatio;
    addTearDown(tester.view.reset);
  }

  testWidgets('dos pasos: quién es Porty y traer la cartera, con cuatro '
      'caminos y "Ahora no"', (tester) async {
    setSize(tester);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(OnboardingScreen.pageCount, 2);
    expect(find.text('onboarding_welcome_title'), findsOneWidget);
    // Lo que Porty hace con la cartera, desde la primera pantalla.
    expect(find.text('onboarding_welcome_prompt_portfolio'), findsOneWidget);

    await tester.tap(find.text(_start));
    await tester.pumpAndSettle();

    expect(find.text('onboarding_bring_title'), findsOneWidget);
    for (final way in [
      'onboarding_bring_file_title',
      'onboarding_bring_etoro_title',
      'onboarding_bring_write_title',
      'onboarding_bring_manual_title',
    ]) {
      expect(find.text(way), findsOneWidget);
    }
    // Las filas son la acción: abajo, solo "Ahora no".
    expect(find.text(_start), findsNothing);
    expect(find.text('onboarding_skip_for_now'), findsOneWidget);
  });

  testWidgets('entra en un SE con texto grande sin desbordar', (tester) async {
    setSize(tester);
    await tester.pumpWidget(_app(textScale: 1.3));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_start));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
