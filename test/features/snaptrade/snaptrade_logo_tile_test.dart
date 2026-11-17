import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/etoro/view/widgets/etoro_brand.dart';
import 'package:portfolio_assistant/features/snaptrade/view/widgets/snaptrade_brand.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';

import '../../helpers/load_spanish_translations.dart';

/// El chip "Tu bróker" de la pantalla de conectar bróker no se corta: antes
/// tenía un tope fijo de ancho y quedaba "Your bro…" aun con lugar de sobra.
void main() {
  setUpAll(loadSpanishTranslations);

  Future<void> pump(WidgetTester tester, {double textScale = 1}) async {
    tester.view.physicalSize = const Size(375, 812); // iPhone SE
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final theme = ProviderContainer().read(themeDataLightProvider);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(375, 812),
            textScaler: TextScaler.linear(textScale),
          ),
          child: const Scaffold(
            body: Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: PortyPartnerLockup(
                  state: EtoroLinkState.idle,
                  partner: SnaptradeLogoTile(),
                  animated: false,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  bool truncated(WidgetTester tester) {
    final paragraph = tester.renderObject<RenderParagraph>(
      find.text('Tu bróker'),
    );
    return paragraph.didExceedMaxLines;
  }

  testWidgets('"Tu bróker" entra entero en un iPhone SE', (tester) async {
    await pump(tester);
    expect(truncated(tester), isFalse);
    expect(tester.takeException(), isNull);
    // La card mide lo que su contenido: no se estira hasta el borde.
    expect(
      tester.getSize(find.byType(PortyPartnerLockup)).width,
      lessThan(335),
    );
  });

  testWidgets('con la letra agrandada (130 %) entra en la pantalla sin '
      'desbordar', (tester) async {
    // La fuente de los tests (Ahem) dibuja cada letra como un cuadrado del
    // tamaño de la fuente: a 130 % exagera tanto el ancho que no sirve para
    // decidir si "Tu bróker" se corta. Lo que sí se comprueba es que el
    // encabezado se acomoda al ancho y no desborda.
    await pump(tester, textScale: 1.3);
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(PortyPartnerLockup)).width,
      lessThanOrEqualTo(335),
    );
  });
}
