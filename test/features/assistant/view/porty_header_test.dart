import 'dart:convert';
import 'dart:io';

// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/utils/porty_activity_copy.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_header.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/turn_activity.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

import '../../../helpers/genui_test_helpers.dart';

void _loadSpanish() {
  final map =
      jsonDecode(File('assets/translations/es-ES.json').readAsStringSync())
          as Map<String, dynamic>;
  Localization.load(const Locale('es', 'ES'), translations: Translations(map));
}

/// Deja terminar el crossfade de la línea de estado (el avatar sigue en loop
/// mientras Porty trabaja, así que no hay `pumpAndSettle`).
Future<void> settleStatus(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

TurnActivity _tools(List<(String, Map<String, Object?>)> calls) =>
    TurnActivity.tools([for (final (n, a) in calls) PendingToolCall(n, a)]);

// `genuiTestApp` usa el tema dark (colores de `CustomColors.dark`).
void main() {
  setUpAll(() {
    _loadSpanish();
    // Sin respiración en reposo, para poder usar `pumpAndSettle`; el
    // movimiento del avatar se prueba en porty_avatar_test.
    PortyAvatar.ambientMotion = false;
  });
  tearDownAll(() => PortyAvatar.ambientMotion = true);

  late ValueNotifier<TurnActivity> activity;
  setUp(() => activity = ValueNotifier(TurnActivity.idle));
  tearDown(() => activity.dispose());

  Future<void> pumpHeader(
    WidgetTester tester, {
    PortyQuota? quota = const PortyQuota(remaining: 18, limit: 20),
    VoidCallback? onQuotaTap,
    bool disableAnimations = false,
    bool accessibleNavigation = false,
  }) async {
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: genuiTestViewportSize,
          disableAnimations: disableAnimations,
          accessibleNavigation: accessibleNavigation,
        ),
        child: genuiTestApp(
          child: PortyHeader(
            activity: activity,
            quota: quota,
            onQuotaTap: onQuotaTap,
          ),
        ),
      ),
    );
  }

  /// Lo que pinta el avatar del header en este frame.
  PortyFrame avatarFrame(WidgetTester tester) {
    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(PortyAvatar),
        matching: find.byType(CustomPaint),
      ),
    );
    return (paint.painter! as PortyAvatarPainter).frame;
  }

  group('status line', () {
    testWidgets('shows the name and the idle status at rest', (tester) async {
      await pumpHeader(tester);

      expect(find.text('Porty'), findsOneWidget);
      expect(find.text('Listo para ayudarte'), findsOneWidget);
    });

    testWidgets('names the tool and its ticker while it runs', (tester) async {
      await pumpHeader(tester);

      activity.value = TurnActivity.thinking;
      await settleStatus(tester);
      expect(find.text('Pensando…'), findsOneWidget);

      activity.value = _tools([
        (
          'get_quote',
          {
            'tickers': ['nvda'],
          },
        ),
      ]);
      await settleStatus(tester);
      expect(find.text('Buscando el precio de NVDA…'), findsOneWidget);
      expect(find.text('Pensando…'), findsNothing);
    });

    testWidgets('summarizes parallel tools in a single sentence', (
      tester,
    ) async {
      await pumpHeader(tester);

      activity.value = _tools([
        (
          'get_quote',
          {
            'tickers': ['AAPL'],
          },
        ),
        (
          'get_news',
          {
            'tickers': ['AAPL'],
          },
        ),
      ]);
      await settleStatus(tester);
      expect(find.text('Analizando AAPL…'), findsOneWidget);

      activity.value = _tools([
        (
          'get_portfolio_details',
          {
            'include': ['positions'],
          },
        ),
        (
          'get_news',
          {
            'tickers': ['AAPL'],
          },
        ),
      ]);
      await settleStatus(tester);
      expect(find.text('Reuniendo los datos…'), findsOneWidget);
    });

    testWidgets('crossfades between statuses in ~200 ms', (tester) async {
      await pumpHeader(tester);

      activity.value = TurnActivity.thinking;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // A mitad del crossfade conviven las dos frases.
      expect(find.text('Pensando…'), findsOneWidget);
      expect(find.text('Listo para ayudarte'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text('Listo para ayudarte'), findsNothing);
    });

    testWidgets('goes back to idle when the turn ends', (tester) async {
      await pumpHeader(tester);

      activity.value = TurnActivity.composing;
      await settleStatus(tester);
      expect(find.text('Armando tu respuesta…'), findsOneWidget);

      // Fin del turno — sea con respuesta o con error, el provider vuelve a
      // `idle` en su `finally` (ver assistant_submit_e2e_test).
      activity.value = TurnActivity.idle;
      await tester.pumpAndSettle();
      expect(find.text('Listo para ayudarte'), findsOneWidget);
      expect(find.text('Armando tu respuesta…'), findsNothing);
      expect(avatarFrame(tester).state, PortyAvatarState.idle);
      expect(avatarFrame(tester).bodyAtRest, isTrue);
    });

    testWidgets('during a turn the header avatar stays idle: only the '
        'status line changes (the message avatar is the one that acts)', (
      tester,
    ) async {
      await pumpHeader(tester);
      expect(avatarFrame(tester).state, PortyAvatarState.idle);

      for (final next in [
        TurnActivity.thinking,
        _tools([
          (
            'get_quote',
            {
              'tickers': ['NVDA'],
            },
          ),
        ]),
        TurnActivity.composing,
      ]) {
        activity.value = next;
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          expect(avatarFrame(tester).state, PortyAvatarState.idle);
          expect(avatarFrame(tester).bodyAtRest, isTrue);
        }
      }
      expect(find.text('Armando tu respuesta…'), findsOneWidget);
    });

    testWidgets('with disableAnimations nothing animates, the text swaps', (
      tester,
    ) async {
      await pumpHeader(tester, disableAnimations: true);

      activity.value = _tools([
        (
          'get_news',
          {
            'tickers': ['AAPL'],
          },
        ),
      ]);
      await tester.pump();
      expect(find.text('Revisando noticias de AAPL…'), findsOneWidget);
      expect(find.text('Listo para ayudarte'), findsNothing);
      expect(avatarFrame(tester), const PortyFrame.still(PortyAvatarState.idle));
      expect(tester.binding.hasScheduledFrame, isFalse);

      await tester.pump(const Duration(seconds: 1));
      expect(avatarFrame(tester), const PortyFrame.still(PortyAvatarState.idle));
    });
  });

  group('semantics', () {
    testWidgets('exposes name and status as a single header label', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpHeader(tester);

      expect(
        find.bySemanticsLabel('Porty, Listo para ayudarte'),
        findsOneWidget,
      );

      activity.value = _tools([
        (
          'get_quote',
          {
            'tickers': ['NVDA'],
          },
        ),
      ]);
      await settleStatus(tester);
      expect(
        find.bySemanticsLabel('Porty, Buscando el precio de NVDA…'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('announces once per turn, not on every tool', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpHeader(tester, accessibleNavigation: true);

      activity.value = TurnActivity.thinking;
      await tester.pump();
      activity.value = _tools([
        (
          'get_quote',
          {
            'tickers': ['NVDA'],
          },
        ),
      ]);
      await tester.pump();
      activity.value = TurnActivity.composing;
      await tester.pump();
      activity.value = TurnActivity.idle;
      await tester.pumpAndSettle();

      final announcements = tester.takeAnnouncements();
      expect(announcements, hasLength(1));
      expect(announcements.single.message, 'Porty está respondiendo');
      handle.dispose();
    });
  });

  group('quota chip', () {
    Color chipColor(WidgetTester tester) {
      final container = tester.widget<AnimatedContainer>(
        find.ancestor(
          of: find.textContaining('restantes'),
          matching: find.byType(AnimatedContainer),
        ),
      );
      return (container.decoration! as BoxDecoration).color!;
    }

    testWidgets('shows remaining queries in a neutral tone', (tester) async {
      await pumpHeader(
        tester,
        quota: const PortyQuota(remaining: 18, limit: 20),
      );

      expect(find.text('18 restantes'), findsOneWidget);
      expect(chipColor(tester), CustomColors.dark.surfaceElevated);
    });

    testWidgets('turns into a warning at 10% of the quota or less', (
      tester,
    ) async {
      await pumpHeader(
        tester,
        quota: const PortyQuota(remaining: 2, limit: 20),
      );
      await tester.pumpAndSettle();

      expect(find.text('2 restantes'), findsOneWidget);
      expect(chipColor(tester), CustomColors.dark.lossContainer);
    });

    test('threshold is 10% of the plan quota, rounded up', () {
      expect(const PortyQuota(remaining: 2, limit: 20).isLow, isTrue);
      expect(const PortyQuota(remaining: 3, limit: 20).isLow, isFalse);
      expect(const PortyQuota(remaining: 50, limit: 500).isLow, isTrue);
      expect(const PortyQuota(remaining: 51, limit: 500).isLow, isFalse);
      expect(const PortyQuota(remaining: 0, limit: 1000).isLow, isTrue);
    });

    testWidgets('is tappable with a 44 px target only when given onTap', (
      tester,
    ) async {
      var taps = 0;
      await pumpHeader(
        tester,
        quota: const PortyQuota(remaining: 0, limit: 20),
        onQuotaTap: () => taps++,
      );

      final target = find.ancestor(
        of: find.text('0 restantes'),
        matching: find.byType(GestureDetector),
      );
      final size = tester.getSize(target.first);
      expect(size.height, greaterThanOrEqualTo(44));
      expect(size.width, greaterThanOrEqualTo(44));

      await tester.tap(target.first);
      expect(taps, 1);
    });

    testWidgets('hidden when there is no quota', (tester) async {
      await pumpHeader(tester, quota: null);
      expect(find.textContaining('restantes'), findsNothing);
    });
  });

  group('PortyActivityCopy', () {
    String of(List<(String, Map<String, Object?>)> calls) =>
        PortyActivityCopy.describe(_tools(calls));

    test('one sentence per tool, never the technical name', () {
      final byTool = {
        'get_quote': of([
          (
            'get_quote',
            {
              'tickers': ['NVDA'],
            },
          ),
        ]),
        'search_symbol': of([
          ('search_symbol', {'query': 'nvidia'}),
        ]),
        'get_fundamentals': of([
          (
            'get_fundamentals',
            {
              'tickers': ['MSFT'],
            },
          ),
        ]),
        'get_earnings': of([
          (
            'get_earnings',
            {
              'tickers': ['AAPL'],
            },
          ),
        ]),
        'get_news': of([
          (
            'get_news',
            {
              'tickers': ['AAPL'],
            },
          ),
        ]),
        'get_portfolio_details': of([
          (
            'get_portfolio_details',
            {
              'include': ['positions'],
            },
          ),
        ]),
        'get_invest_candidates': of([
          (
            'get_invest_candidates',
            {
              'theme': 'x',
              'tickers': ['SPY'],
            },
          ),
        ]),
        'get_goal_projection': of([('get_goal_projection', {})]),
        'save_goal': of([
          ('save_goal', {'target_amount': 1}),
        ]),
        'propose_buy': of([
          ('propose_buy', {'ticker': 'AAPL', 'shares': 10}),
        ]),
      };
      expect(byTool, {
        'get_quote': 'Buscando el precio de NVDA…',
        'search_symbol': 'Buscando la empresa…',
        'get_fundamentals': 'Revisando los números de MSFT…',
        'get_earnings': 'Revisando los resultados de AAPL…',
        'get_news': 'Revisando noticias de AAPL…',
        'get_portfolio_details': 'Revisando tu portfolio…',
        'get_invest_candidates': 'Evaluando opciones para invertir…',
        'get_goal_projection': 'Calculando tu proyección…',
        'save_goal': 'Guardando tu meta…',
        'propose_buy': 'Preparando la operación…',
      });
      for (final text in byTool.values) {
        expect(text, isNot(contains('_')));
        expect(text, isNot(contains('{')));
      }
    });

    test('same tool on several tickers stays one sentence', () {
      expect(
        of([
          (
            'get_quote',
            {
              'tickers': ['NVDA', 'AMD'],
            },
          ),
        ]),
        'Buscando precios de NVDA y AMD…',
      );
      expect(
        of([
          (
            'get_quote',
            {
              'tickers': ['NVDA'],
            },
          ),
          (
            'get_quote',
            {
              'tickers': ['AMD', 'INTC'],
            },
          ),
        ]),
        'Buscando precios…',
      );
      expect(
        of([
          (
            'get_news',
            {
              'tickers': ['NVDA', 'AMD'],
            },
          ),
        ]),
        'Revisando noticias…',
      );
    });

    test('garbage or unknown arguments fall back to generic copy', () {
      expect(
        of([
          ('get_quote', {'tickers': 'NVDA'}),
        ]),
        'Buscando precios…',
      );
      expect(of([('something_new', {})]), 'Reuniendo los datos…');
    });
  });
}
