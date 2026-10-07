import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_data.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_type.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/porty_toast.dart';

late BuildContext _ctx;

Widget _app() => MaterialApp(
  theme: ProviderContainer().read(themeDataLightProvider),
  home: Scaffold(
    body: Builder(
      builder: (context) {
        _ctx = context;
        return const SizedBox.expand();
      },
    ),
  ),
);

PortyAvatarState _mood(WidgetTester tester) =>
    tester.widget<PortyAvatar>(find.byType(PortyAvatar)).state;

void main() {
  testWidgets('success: Porty happy, then it fades out on its own', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    PortyToast.show(
      _ctx,
      AlertData(alertType: AlertType.success, message: 'Perfil guardado'),
    );
    await tester.pump();
    await tester.pump(PortyToast.enter);
    expect(find.text('Perfil guardado'), findsOneWidget);
    expect(_mood(tester), PortyAvatarState.answered);

    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Perfil guardado'), findsNothing);
  });

  testWidgets('error: Porty barely sad; tapping closes it early', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    PortyToast.show(
      _ctx,
      AlertData(alertType: AlertType.error, message: 'No se pudo guardar'),
    );
    await tester.pump(PortyToast.enter);
    expect(_mood(tester), PortyAvatarState.concerned);

    await tester.tap(find.text('No se pudo guardar'));
    await tester.pump();
    await tester.pump(PortyToast.exit);
    await tester.pump();
    expect(find.text('No se pudo guardar'), findsNothing);
  });

  testWidgets('a new one replaces the previous one', (tester) async {
    await tester.pumpWidget(_app());
    PortyToast.show(_ctx, AlertData(alertType: AlertType.success, message: 'A'));
    await tester.pump(PortyToast.enter);
    PortyToast.show(_ctx, AlertData(alertType: AlertType.warning, message: 'B'));
    await tester.pump(PortyToast.enter);
    expect(find.text('A'), findsNothing);
    expect(find.text('B'), findsOneWidget);
    await tester.pump(PortyToast.visibleFor + PortyToast.exit);
    await tester.pump();
  });
}
