// El botón de perfil de la Home (con Noticias prendida Ajustes sale de la
// barra) y cómo se abre Ajustes según el interruptor. Correr:
// flutter test test/presentation/flows/home/home_profile_button_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/daily_brief/providers/daily_brief_provider.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/home_app_bar.dart';
import 'package:portfolio_assistant/presentation/flows/settings/nav/settings_router.dart';

ThemeData _theme(Brightness b) {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  return c.read(
    b == Brightness.dark ? themeDataDarkProvider : themeDataLightProvider,
  );
}

Future<void> _pumpBar(
  WidgetTester tester, {
  String? name,
  VoidCallback? onProfile,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = const Size(375, 667);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: _theme(brightness),
      home: Scaffold(
        body: HomeAppBar(
          firstName: name,
          onOpenPorty: () {},
          onOpenProfile: onProfile,
        ),
      ),
    ),
  );
}

void main() {
  final button = find.byKey(const Key('home_profile_button'));

  testWidgets('no profile button when the switch is off', (tester) async {
    await _pumpBar(tester, name: 'Ana');
    expect(button, findsNothing);
  });

  for (final b in Brightness.values) {
    testWidgets('profile button: initial, 44x44, tappable (${b.name})', (
      tester,
    ) async {
      var taps = 0;
      await _pumpBar(
        tester,
        name: 'ana',
        onProfile: () => taps++,
        brightness: b,
      );
      expect(find.text('A'), findsOneWidget);
      final size = tester.getSize(button);
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
      await tester.tap(button);
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('profile button without a name shows a person icon', (
    tester,
  ) async {
    await _pumpBar(tester, onProfile: () {});
    expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);
  });

  group('SettingsRouter.open', () {
    Future<List<String>> run(WidgetTester tester, {required bool on}) async {
      final seen = <String>[];
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder:
                (context, _) => Scaffold(
                  body: TextButton(
                    onPressed: () => SettingsRouter.open(context),
                    child: const Text('open'),
                  ),
                ),
          ),
          GoRoute(
            name: SettingsRouter.settingsRouteName,
            path: '/settings',
            builder: (_, __) {
              seen.add('tab');
              return const Text('tab');
            },
          ),
          GoRoute(
            name: SettingsRouter.pushedRouteName,
            path: '/profile-settings',
            builder: (_, __) {
              seen.add('pushed');
              return const Text('pushed');
            },
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [newsFeedAvailableProvider.overrideWithValue(on)],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return seen;
    }

    testWidgets('switch on: pushed route', (tester) async {
      expect(await run(tester, on: true), ['pushed']);
    });

    testWidgets('switch off: tab route', (tester) async {
      expect(await run(tester, on: false), ['tab']);
    });
  });
}
