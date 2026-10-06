import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/presentation/shared/loading/app_bootstrap.dart';
import 'package:portfolio_assistant/presentation/shared/loading/button_spinner.dart';
import 'package:portfolio_assistant/presentation/shared/loading/loader_timing.dart';
import 'package:portfolio_assistant/presentation/shared/loading/porty_loader.dart';
import 'package:portfolio_assistant/presentation/shared/loading/skeleton.dart';

import '../../../helpers/genui_test_helpers.dart';

Widget _app(Widget child, {bool reduceMotion = false}) => MediaQuery(
  data: MediaQueryData(
    size: const Size(390, 844),
    disableAnimations: reduceMotion,
  ),
  child: genuiTestApp(child: child),
);

/// Cambia [loading] desde el test.
class _Toggle extends StatefulWidget {
  const _Toggle({required this.controller});

  final ValueNotifier<bool> controller;

  @override
  State<_Toggle> createState() => _ToggleState();
}

class _ToggleState extends State<_Toggle> {
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: widget.controller,
    builder:
        (_, loading, _) => LoadingSwitcher(
          loading: loading,
          placeholder: (_) => const Text('loader'),
          child: (_) => const Text('content'),
        ),
  );
}

void main() {
  group('300 ms delay and 400 ms minimum', () {
    testWidgets('a wait under 300 ms never shows the loader', (tester) async {
      final loading = ValueNotifier(true);
      addTearDown(loading.dispose);
      await tester.pumpWidget(_app(_Toggle(controller: loading)));
      await tester.pump(const Duration(milliseconds: 290));
      expect(find.text('loader'), findsNothing);
      loading.value = false;
      await tester.pump(); // a los 290 ms, antes de que venza la espera
      await tester.pumpAndSettle();
      expect(find.text('loader'), findsNothing);
      expect(find.text('content'), findsOneWidget);
    });

    testWidgets('once visible, the loader stays at least 400 ms', (
      tester,
    ) async {
      final loading = ValueNotifier(true);
      addTearDown(loading.dispose);
      await tester.pumpWidget(_app(_Toggle(controller: loading)));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.text('loader'), findsOneWidget);

      // Termina 50 ms después de aparecer: igual se queda hasta los 400.
      await tester.pump(const Duration(milliseconds: 50));
      loading.value = false;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300)); // 350 visible
      expect(find.text('loader'), findsOneWidget);
      expect(find.text('content'), findsNothing);

      await tester.pump(const Duration(milliseconds: 60)); // 410
      await tester.pump(LoaderTiming.swap ~/ 2);
      // Crossfade de 200 ms: conviven.
      expect(find.text('loader'), findsOneWidget);
      expect(find.text('content'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('loader'), findsNothing);
    });

    testWidgets('a long wait keeps the loader until it ends', (tester) async {
      final loading = ValueNotifier(true);
      addTearDown(loading.dispose);
      await tester.pumpWidget(_app(_Toggle(controller: loading)));
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('loader'), findsOneWidget);
      loading.value = false;
      await tester.pumpAndSettle();
      expect(find.text('content'), findsOneWidget);
    });

    testWidgets('with reduce motion the swap is instant', (tester) async {
      final loading = ValueNotifier(true);
      addTearDown(loading.dispose);
      await tester.pumpWidget(
        _app(_Toggle(controller: loading), reduceMotion: true),
      );
      await tester.pump(const Duration(seconds: 1));
      loading.value = false;
      await tester.pump();
      expect(find.text('loader'), findsNothing);
      expect(find.text('content'), findsOneWidget);
    });
  });

  group('PortyLoader', () {
    testWidgets('Porty thinks, exactly centered; the line fades in after '
        '2 s without moving it', (tester) async {
      await tester.pumpWidget(
        _app(const PortyLoader(message: 'Preparando tu cartera…')),
      );
      await tester.pump();
      final avatar = find.byType(PortyAvatar);
      expect(tester.getSize(avatar), const Size.square(64));
      final center = tester.getCenter(avatar);
      final screen = tester.getCenter(find.byType(PortyLoader));
      expect(center, screen);

      double opacity() =>
          tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;
      expect(opacity(), 0);
      expect(
        tester.getSemantics(find.byType(PortyLoader)).label,
        isNot(contains('Preparando')),
      );

      // Al pensar: crossfade de la cara desde reposo (como el splash).
      await tester.pump(const Duration(milliseconds: 300));
      final paint = tester.widget<CustomPaint>(
        find.descendant(of: avatar, matching: find.byType(CustomPaint)),
      );
      expect(
        (paint.painter! as PortyAvatarPainter).frame.state,
        PortyAvatarState.thinking,
      );

      await tester.pump(const Duration(seconds: 2));
      expect(opacity(), 1);
      expect(tester.getCenter(avatar), center);
      expect(
        tester.getSemantics(find.byType(PortyLoader)).label,
        contains('Preparando tu cartera…'),
      );
    });

    testWidgets('with reduce motion Porty does not move', (tester) async {
      await tester.pumpWidget(
        _app(const PortyLoader(message: 'x'), reduceMotion: true),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(SchedulerBinding.instance.transientCallbackCount, 0);
    });
  });

  group('skeleton', () {
    testWidgets('one slow pulse for the whole skeleton, announced once as '
        'loading; static with reduce motion', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          const SkeletonScope(
            semanticsLabel: 'Cargando',
            child: Column(
              children: [
                SkeletonBlock.line(width: 100),
                SkeletonBlock.circle(size: 24),
                SkeletonBlock(width: 200, height: 40),
              ],
            ),
          ),
        ),
      );
      expect(find.bySemanticsLabel('Cargando'), findsOneWidget);
      final fades = tester.widgetList<FadeTransition>(
        find.descendant(
          of: find.byType(SkeletonScope),
          matching: find.byType(FadeTransition),
        ),
      );
      expect(fades.map((f) => f.opacity).toSet(), hasLength(1));
      final pulse = fades.first.opacity;
      await tester.pump(const Duration(milliseconds: 800));
      expect(pulse.value, lessThan(1));
      expect(pulse.value, greaterThanOrEqualTo(SkeletonMotion.minOpacity));

      await tester.pumpWidget(
        _app(
          const SkeletonScope(child: SkeletonBlock(width: 10, height: 10)),
          reduceMotion: true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 800));
      expect(SchedulerBinding.instance.transientCallbackCount, 0);
      handle.dispose();
    });
  });

  group('button spinner', () {
    testWidgets('the spinner replaces the label after 300 ms without '
        'changing the button size', (tester) async {
      final loading = ValueNotifier(false);
      addTearDown(loading.dispose);
      await tester.pumpWidget(
        _app(
          Center(
            child: ValueListenableBuilder<bool>(
              valueListenable: loading,
              builder:
                  (_, value, _) => LoadingButtonContent(
                    loading: value,
                    spinnerColor: Colors.white,
                    label: const Text('Guardar'),
                  ),
            ),
          ),
        ),
      );
      final idle = tester.getSize(find.byType(LoadingButtonContent));
      loading.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(ButtonSpinner), findsNothing);
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.byType(ButtonSpinner), findsOneWidget);
      expect(tester.getSize(find.byType(LoadingButtonContent)), idle);
      final spinner = tester.getSize(find.byType(ButtonSpinner));
      expect(spinner, const Size.square(20));
    });
  });

  group('app bootstrap', () {
    testWidgets('the first frame is Porty on the splash background, then a '
        'crossfade to the app', (tester) async {
      final ready = Completer<Widget>();
      await tester.pumpWidget(AppBootstrap(initialize: () => ready.future));
      expect(find.byType(PortyLoader), findsOneWidget);
      final background = tester.widget<ColoredBox>(
        find.ancestor(
          of: find.byType(PortyLoader),
          matching: find.byType(ColoredBox),
        ),
      );
      expect(background.color, AppBootstrap.lightBackground);

      ready.complete(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Text('app'),
        ),
      );
      await tester.pump();
      await tester.pump(LoaderTiming.swap ~/ 2);
      expect(find.text('app'), findsOneWidget);
      expect(find.byType(PortyLoader), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byType(PortyLoader), findsNothing);
    });
  });
}
