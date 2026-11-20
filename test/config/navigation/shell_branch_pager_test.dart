// Pestañas del shell que se pasan deslizando (ShellBranchPager) con un
// GoRouter real y tres ramas de prueba.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:portfolio_assistant/config/navigation/shell_branch_pager.dart';

class _Tab extends StatefulWidget {
  const _Tab(this.name);

  final String name;

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  int taps = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.name),
          Text('${widget.name} taps $taps'),
          TextButton(
            onPressed: () => setState(() => taps++),
            child: Text('tap ${widget.name}'),
          ),
        ],
      ),
    ),
  );
}

late StatefulNavigationShell _shell;

GoRouter _router() => GoRouter(
  initialLocation: '/a',
  routes: [
    StatefulShellRoute(
      builder: (context, state, shell) {
        _shell = shell;
        return shell;
      },
      navigatorContainerBuilder:
          (context, shell, children) => ShellBranchPager(
            currentIndex: shell.currentIndex,
            onPageSwiped: shell.goBranch,
            children: children,
          ),
      branches: [
        for (final name in ['a', 'b', 'c'])
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/$name', builder: (_, __) => _Tab(name)),
            ],
          ),
      ],
    ),
  ],
);

Future<GoRouter> _pump(WidgetTester tester) async {
  final router = _router();
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
  return router;
}

String _location(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.toString();

void main() {
  testWidgets('a left swipe moves to the next tab and changes the branch', (
    tester,
  ) async {
    final router = await _pump(tester);

    await tester.fling(find.text('a'), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();

    expect(_shell.currentIndex, 1);
    expect(_location(router), '/b');
    expect(find.text('b'), findsOneWidget);
  });

  testWidgets('a right swipe goes back, and the first tab does not bounce', (
    tester,
  ) async {
    await _pump(tester);

    await tester.fling(find.text('a'), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(_shell.currentIndex, 0);

    await tester.fling(find.text('a'), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    await tester.fling(find.text('b'), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(_shell.currentIndex, 0);
  });

  testWidgets('a short drag that does not pass halfway stays on the tab', (
    tester,
  ) async {
    await _pump(tester);

    await tester.drag(find.text('a'), const Offset(-60, 0));
    await tester.pumpAndSettle();

    expect(_shell.currentIndex, 0);
    expect(find.text('a'), findsOneWidget);
  });

  testWidgets('switching from the bar jumps straight to the tab', (
    tester,
  ) async {
    final router = await _pump(tester);

    _shell.goBranch(2);
    await tester.pumpAndSettle();

    expect(_location(router), '/c');
    expect(find.text('c'), findsOneWidget);
    // Saltó: la pestaña del medio nunca se cargó.
    expect(find.text('b', skipOffstage: false), findsNothing);
  });

  testWidgets('each tab keeps its state when you swipe away and back', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(find.text('tap a'));
    await tester.tap(find.text('tap a'));
    await tester.pump();
    expect(find.text('a taps 2'), findsOneWidget);

    await tester.fling(find.text('a'), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    await tester.fling(find.text('b'), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();

    expect(find.text('a taps 2'), findsOneWidget);
  });

  testWidgets('swiping closes the keyboard', (tester) async {
    final router = GoRouter(
      initialLocation: '/a',
      routes: [
        StatefulShellRoute(
          builder: (context, state, shell) => shell,
          navigatorContainerBuilder:
              (context, shell, children) => ShellBranchPager(
                currentIndex: shell.currentIndex,
                onPageSwiped: shell.goBranch,
                children: children,
              ),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/a',
                  builder:
                      (_, __) => const Scaffold(
                        body: Center(child: SizedBox(width: 200, child: TextField())),
                      ),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [GoRoute(path: '/b', builder: (_, __) => const _Tab('b'))],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextField));
    await tester.pump();
    final field = tester.widget<EditableText>(find.byType(EditableText));
    expect(field.focusNode.hasPrimaryFocus, isTrue);

    await tester.flingFrom(const Offset(380, 100), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();

    expect(find.text('b'), findsOneWidget);
    expect(field.focusNode.hasFocus, isFalse);
  });
}
