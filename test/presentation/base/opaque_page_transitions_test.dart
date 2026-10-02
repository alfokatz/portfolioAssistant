import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/presentation/base/theme/opaque_page_transitions.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';

/// La ruta de abajo pinta azul puro (la paleta de la app es cálida: ningún
/// píxel propio tiene más azul que rojo); la de arriba es un Scaffold
/// transparente, como todas las pantallas de la app. Si algún píxel con tinte azul
/// aparece (aunque sea mezclado por un fade) en la zona que ya cubre la ruta de arriba, se está viendo una
/// pantalla a través de la otra.
const _below = Color(0xFF0000FF);

final _boundaryKey = GlobalKey();
final _navigatorKey = GlobalKey<NavigatorState>();

ThemeData _appTheme(TargetPlatform platform) => ProviderContainer()
    .read(themeDataLightProvider)
    .copyWith(platform: platform);

Widget _app(TargetPlatform platform) => RepaintBoundary(
  key: _boundaryKey,
  child: MaterialApp(
    navigatorKey: _navigatorKey,
    theme: _appTheme(platform),
    home: const Scaffold(
      body: SizedBox.expand(child: ColoredBox(color: _below)),
    ),
  ),
);

Route<void> _transparentRoute() => MaterialPageRoute<void>(
  builder:
      (_) => Scaffold(
        appBar: AppBar(title: const Text('AMZN')),
        body: const Center(child: Text('Compras')),
      ),
);

/// Borde izquierdo (ya trasladado por la transición) de la ruta de arriba:
/// todo lo que está a su derecha lo tiene que tapar esa ruta.
double _leftEdge(WidgetTester tester, double width) {
  final dx = tester.getTopLeft(find.byType(Scaffold).last).dx;
  return (dx + 1).clamp(0, width).toDouble();
}

Future<ui.Image> _capture(WidgetTester tester) async {
  final boundary =
      _boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await tester.runAsync(() => boundary.toImage()))!;
}

Future<int> _belowPixelsRightOf(
  WidgetTester tester,
  ui.Image image,
  double fromX,
) async {
  final bytes =
      (await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      ))!;
  var red = 0;
  for (var y = 0; y < image.height; y += 7) {
    for (var x = fromX.ceil(); x < image.width; x += 7) {
      final i = (y * image.width + x) * 4;
      final r = bytes.getUint8(i), g = bytes.getUint8(i + 1);
      final b = bytes.getUint8(i + 2);
      if (b - r > 20) red++;
    }
  }
  return red;
}

void main() {
  test('every platform the app targets uses the opaque builder', () {
    final builders =
        ProviderContainer()
            .read(themeDataLightProvider)
            .pageTransitionsTheme
            .builders;
    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      expect(builders[platform], isA<OpaquePageTransitionsBuilder>());
    }
  });

  for (final platform in [TargetPlatform.iOS]) {
    group('${platform.name} (slide: pixel check)', () {
      testWidgets('push: the screen below never shows through the new one', (
        tester,
      ) async {
        await tester.pumpWidget(_app(platform));
        _navigatorKey.currentState!.push(_transparentRoute());
        await tester.pump();

        final width =
            tester.view.physicalSize.width / tester.view.devicePixelRatio;
        // Muestreo en varios puntos de la transición.
        for (final ms in [60, 120, 180, 240]) {
          await tester.pump(const Duration(milliseconds: 60));
          final image = await _capture(tester);
          // iOS: la ruta nueva entra desde la derecha; a los `ms` ya cubre
          // la franja derecha. Android: entra en toda la pantalla.
          expect(
            await _belowPixelsRightOf(tester, image, _leftEdge(tester, width)),
            0,
            reason: 'route below visible at ${ms}ms',
          );
        }
        await tester.pumpAndSettle();
        expect(await _belowPixelsRightOf(tester, await _capture(tester), 0), 0);
      });

      testWidgets('pop: the screen below never shows through the leaving one', (
        tester,
      ) async {
        await tester.pumpWidget(_app(platform));
        _navigatorKey.currentState!.push(_transparentRoute());
        await tester.pumpAndSettle();

        _navigatorKey.currentState!.pop();
        await tester.pump();
        final width =
            tester.view.physicalSize.width / tester.view.devicePixelRatio;
        for (var i = 0; i < 3; i++) {
          await tester.pump(const Duration(milliseconds: 60));
          if (find.text('Compras').evaluate().isEmpty) break;
          final image = await _capture(tester);
          expect(
            await _belowPixelsRightOf(tester, image, _leftEdge(tester, width)),
            0,
          );
        }
        await tester.pumpAndSettle();
      });
    });
  }

  // Android: fade through. La ruta saliente se apaga del todo antes de que
  // aparezca la entrante, así que el criterio es por opacidad: en ningún
  // frame las dos rutas son visibles a la vez.
  group('android (fade through: opacity check)', () {
    double opacityOf(WidgetTester tester, Finder finder) {
      if (finder.evaluate().isEmpty) return 0;
      var opacity = 1.0;
      for (final f in tester.widgetList<FadeTransition>(
        find.ancestor(of: finder, matching: find.byType(FadeTransition)),
      )) {
        opacity *= f.opacity.value;
      }
      return opacity;
    }

    Future<void> expectNeverBoth(WidgetTester tester) async {
      for (var ms = 0; ms <= 500; ms += 16) {
        final below = opacityOf(
          tester,
          find.byWidgetPredicate((w) => w is ColoredBox && w.color == _below),
        );
        final above = opacityOf(tester, find.text('Compras'));
        expect(
          below > 0.001 && above > 0.001,
          isFalse,
          reason: 'both routes visible at ${ms}ms ($below / $above)',
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    testWidgets('push and pop never show both routes at once', (tester) async {
      await tester.pumpWidget(_app(TargetPlatform.android));
      _navigatorKey.currentState!.push(_transparentRoute());
      await tester.pump();
      await expectNeverBoth(tester);
      await tester.pumpAndSettle();
      expect(await _belowPixelsRightOf(tester, await _capture(tester), 0), 0);

      _navigatorKey.currentState!.pop();
      await tester.pump();
      await expectNeverBoth(tester);
      await tester.pumpAndSettle();
    });
  });

  testWidgets('RouteBackground fills the route with an opaque layer', (
    tester,
  ) async {
    await tester.pumpWidget(_app(TargetPlatform.iOS));
    _navigatorKey.currentState!.push(_transparentRoute());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final background = find.byType(RouteBackground).last;
    expect(
      tester.getSize(background),
      tester.view.physicalSize / tester.view.devicePixelRatio,
    );
    expect(
      find.descendant(of: background, matching: find.byType(RepaintBoundary)),
      findsWidgets,
    );
    await tester.pumpAndSettle();
  });
}
