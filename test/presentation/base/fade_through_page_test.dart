import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/presentation/base/theme/fade_through_page.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/app_background_gradient.dart';

/// Navigator declarativo como el de go_router: login → home reemplaza la
/// página, igual que el redirect al iniciar sesión.
class _Flow extends StatefulWidget {
  const _Flow();

  @override
  State<_Flow> createState() => _FlowState();
}

class _FlowState extends State<_Flow> {
  bool signedIn = false;

  void signIn() => setState(() => signedIn = true);

  @override
  Widget build(BuildContext context) {
    return Navigator(
      pages: [
        if (!signedIn)
          const FadeThroughPage<void>(
            key: ValueKey('login'),
            child: Scaffold(body: Center(child: Text('Login'))),
          )
        else
          const FadeThroughPage<void>(
            key: ValueKey('home'),
            child: Scaffold(body: Center(child: Text('Home'))),
          ),
      ],
      onDidRemovePage: (_) {},
    );
  }
}

double _opacity(WidgetTester tester, Finder of) {
  var opacity = 1.0;
  for (final f in tester.widgetList<FadeTransition>(
    find.ancestor(of: of, matching: find.byType(FadeTransition)),
  )) {
    opacity *= f.opacity.value;
  }
  return opacity;
}

/// Opacidad del fondo propio de la ruta de [text] (la capa que tapa a la
/// pantalla saliente).
double _coverOpacity(WidgetTester tester, String text) {
  final route = find.ancestor(
    of: find.text(text),
    matching: find.byType(Stack),
  );
  final cover = find.descendant(
    of: route.last,
    matching: find.byType(AppBackgroundGradient),
  );
  return _opacity(tester, cover.first);
}

Widget _app({bool reduceMotion = false}) => MaterialApp(
  theme: ProviderContainer().read(themeDataLightProvider),
  builder:
      (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: child!,
      ),
  home: const _Flow(),
);

void main() {
  testWidgets('login → home: home content only shows once its background '
      'fully covers the login, and the login never slides', (tester) async {
    await tester.pumpWidget(_app());
    final loginOrigin = tester.getTopLeft(find.byType(Scaffold).first);

    tester.state<_FlowState>(find.byType(_Flow)).signIn();
    await tester.pump();

    var sawHome = false;
    for (var ms = 0; ms <= 450; ms += 16) {
      final home = _opacity(tester, find.text('Home'));
      if (home > 0) {
        sawHome = true;
        expect(_coverOpacity(tester, 'Home'), 1, reason: 'overlap at ${ms}ms');
      }
      if (find.text('Login').evaluate().isNotEmpty) {
        expect(
          tester.getTopLeft(find.byType(Scaffold).first),
          loginOrigin,
          reason: 'login moved at ${ms}ms',
        );
      }
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();
    expect(sawHome, isTrue);
    expect(_opacity(tester, find.text('Home')), 1);
    expect(find.text('Login'), findsNothing);
  });

  testWidgets('with reduce motion the new screen appears at once', (
    tester,
  ) async {
    await tester.pumpWidget(_app(reduceMotion: true));
    tester.state<_FlowState>(find.byType(_Flow)).signIn();
    await tester.pump();
    await tester.pump();
    expect(_opacity(tester, find.text('Home')), 1);
  });
}
