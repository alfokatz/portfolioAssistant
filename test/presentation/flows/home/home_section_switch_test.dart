import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/home_section_tabs.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/fade_through_switcher.dart';

import '../../../helpers/genui_test_helpers.dart';

/// Home en miniatura: selector + contenido de las dos pestañas, de alturas
/// distintas, con algo debajo para ver que no salta.
class _Sections extends StatefulWidget {
  const _Sections({this.onBuild});

  final void Function(HomeSection)? onBuild;

  @override
  State<_Sections> createState() => _SectionsState();
}

class _SectionsState extends State<_Sections> {
  var _section = HomeSection.assets;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        HomeSectionTabs(
          selected: _section,
          onSelected: (s) => setState(() => _section = s),
        ),
        FadeThroughSwitcher(
          index: _section.index,
          builders: [
            (_) {
              widget.onBuild?.call(HomeSection.assets);
              return const SizedBox(height: 300, child: Text('Mis posiciones'));
            },
            (_) {
              widget.onBuild?.call(HomeSection.insights);
              return const SizedBox(height: 120, child: Text('Benchmark'));
            },
          ],
        ),
        const Text('below'),
      ],
    );
  }
}

double _opacityOf(WidgetTester tester, String text) {
  final finder = find.text(text); // solo lo que está en escena (onstage)
  if (finder.evaluate().isEmpty) return 0;
  var opacity = 1.0;
  for (final o in tester.widgetList<Opacity>(
    find.ancestor(of: finder, matching: find.byType(Opacity)),
  )) {
    opacity *= o.opacity;
  }
  return opacity;
}

Finder _tab(String key) =>
    find.descendant(of: find.byType(HomeSectionTabs), matching: find.text(key));

void main() {
  testWidgets('never shows both sections at the same time, in either '
      'direction', (tester) async {
    await tester.pumpWidget(genuiTestApp(child: const _Sections()));
    await tester.pump(); // prebuild de la otra sección

    for (final target in ['home_tab_insights', 'home_tab_assets']) {
      await tester.tap(_tab(target));
      for (var ms = 0; ms <= 400; ms += 16) {
        final a = _opacityOf(tester, 'Mis posiciones');
        final b = _opacityOf(tester, 'Benchmark');
        expect(a > 0 && b > 0, isFalse, reason: 'both visible at ${ms}ms');
        await tester.pump(const Duration(milliseconds: 16));
      }
    }
    expect(_opacityOf(tester, 'Mis posiciones'), 1);
  });

  testWidgets('the height change is animated, so content below never jumps', (
    tester,
  ) async {
    await tester.pumpWidget(genuiTestApp(child: const _Sections()));
    await tester.pump();
    final start = tester.getTopLeft(find.text('below')).dy;

    await tester.tap(_tab('home_tab_insights'));
    final ys = <double>[];
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      ys.add(tester.getTopLeft(find.text('below')).dy);
    }
    final end = ys.last;
    expect(end, closeTo(start - 180, 0.5));
    // Varios pasos intermedios, sin un salto de golpe.
    final steps = <double>[start, ...ys];
    for (var i = 1; i < steps.length; i++) {
      expect((steps[i] - steps[i - 1]).abs(), lessThan(60));
    }
  });

  testWidgets('both sections are built ahead of time and never rebuilt by '
      'switching', (tester) async {
    final builds = <HomeSection>[];
    await tester.pumpWidget(
      genuiTestApp(child: _Sections(onBuild: builds.add)),
    );
    await tester.pump();
    expect(builds.toSet(), {HomeSection.assets, HomeSection.insights});

    // Cambiar de pestaña no construye ninguna desde cero: la entrante ya
    // estaba montada fuera de escena (el rebuild del padre es lo único).
    final insightsElement = tester.element(
      find.text('Benchmark', skipOffstage: false),
    );
    await tester.tap(_tab('home_tab_insights'));
    await tester.pumpAndSettle();
    expect(tester.element(find.text('Benchmark')), same(insightsElement));
  });

  testWidgets('the indicator slides between options and the labels never '
      'go gray at the same time', (tester) async {
    await tester.pumpWidget(genuiTestApp(child: const _Sections()));
    await tester.pump();
    final indicator = find.byKey(const ValueKey('home_section_indicator'));
    final from = tester.getCenter(indicator).dx;

    await tester.tap(_tab('home_tab_insights'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 110));
    final mid = tester.getCenter(indicator).dx;
    await tester.pumpAndSettle();
    final to = tester.getCenter(indicator).dx;

    expect(mid, greaterThan(from));
    expect(mid, lessThan(to));
    // Un solo indicador (no un fondo por opción que se apaga y otro que se
    // prende).
    expect(indicator, findsOneWidget);
  });

  testWidgets('with disableAnimations the switch is instant', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: genuiTestApp(child: const _Sections()),
      ),
    );
    await tester.pump();

    await tester.tap(_tab('home_tab_insights'));
    await tester.pump();
    expect(_opacityOf(tester, 'Benchmark'), 1);
    expect(_opacityOf(tester, 'Mis posiciones'), 0);
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
