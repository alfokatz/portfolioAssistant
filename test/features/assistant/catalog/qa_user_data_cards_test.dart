import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/catalog/assistant_catalog.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_evidence_scope.dart';
import 'package:portfolio_assistant/features/assistant/utils/assistant_answer_review.dart';
import 'package:portfolio_assistant/features/assistant/utils/assistant_grounding_check.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/shared/widgets/genui_error_card.dart';

import '../../../helpers/genui_test_helpers.dart';

const _watchlist = ToolCallRecord(
  name: 'get_watchlist',
  args: {},
  result: {
    'status': 'ok',
    'items': [
      {
        'ticker': 'TSLA',
        'price': 373.25,
        'day_change_pct': -0.36,
        'since_added_pct': -0.36,
        'alerts_on': true,
      },
      {
        'ticker': 'NFLX',
        'price': 66.64,
        'day_change_pct': -0.61,
        'since_added_pct': -0.57,
        'alerts_on': false,
      },
    ],
  },
);

const _report = ToolCallRecord(
  name: 'get_weekly_report',
  args: {},
  result: {
    'status': 'ok',
    'report': {
      'week': '2026-10-19',
      'change_pct': 2.4,
      'change_abs': 312.5,
      'sp500_pct': 1.1,
      'movers': [
        {'ticker': 'NVDA', 'move_pct': 6.1, 'why': 'Subió por sus chips.'},
        {'ticker': 'AAPL', 'move_pct': -1.2},
      ],
      'reading': 'Semana buena, empujada por NVDA.',
    },
  },
);

Future<void> _pump(
  WidgetTester tester,
  Map<String, Object?> component,
  List<ToolCallRecord> calls,
) async {
  final catalog = AssistantCatalog.build();
  final item = catalog.items.firstWhere(
    (i) => i.name == component['component'],
  );
  await tester.binding.setSurfaceSize(const Size(390, 2000));
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(extensions: const [CustomColors.light]),
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: QaEvidenceScope(
          lookup: (_) => ValueNotifier(TurnEvidence(calls: calls)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: Builder(
                builder:
                    (context) => item.widgetBuilder(
                      catalogContextFor(
                        buildContext: context,
                        component: component,
                        catalog: catalog,
                        surfaceId: 's1',
                      ),
                    ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  expect(find.byType(GenUiErrorCard), findsNothing);
}

void main() {
  testWidgets('QaWatchlist: every ticker and number from the tool', (
    tester,
  ) async {
    await _pump(tester, {'id': 'w', 'component': 'QaWatchlist'}, [_watchlist]);
    expect(find.text('Tu lista de seguimiento'), findsOneWidget);
    expect(find.text('2 tickers'), findsOneWidget);
    expect(find.text('TSLA'), findsOneWidget);
    expect(find.text('\$373.25'), findsOneWidget);
    expect(find.textContaining('desde que la agregaste'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('QaWeeklyReport: the week, movers and the reading', (
    tester,
  ) async {
    await _pump(tester, {'id': 'r', 'component': 'QaWeeklyReport'}, [_report]);
    expect(find.text('Tu informe semanal'), findsOneWidget);
    expect(find.text('Semana del 19 de octubre'), findsOneWidget);
    expect(find.text('NVDA'), findsOneWidget);
    expect(find.text('Subió por sus chips.'), findsOneWidget);
    expect(find.text('Semana buena, empujada por NVDA.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('without the tool result the cards draw nothing', (tester) async {
    await _pump(tester, {'id': 'w', 'component': 'QaWatchlist'}, const []);
    expect(find.text('Tu lista de seguimiento'), findsNothing);
  });

  testWidgets('QaInfoList: title, rows with value and ticker', (tester) async {
    await _pump(tester, {
      'id': 'l',
      'component': 'QaInfoList',
      'title': 'Tus alertas',
      'icon': 'alert',
      'rows': [
        {
          'title': 'VOO sube a \$750',
          'detail': 'Una vez',
          'value': 'Activa',
          'tone': 'positive',
          'ticker': 'VOO',
        },
      ],
    }, const []);
    expect(find.text('Tus alertas'), findsOneWidget);
    expect(find.text('VOO sube a \$750'), findsOneWidget);
    expect(find.text('Activa'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('QaInfoList numbers must come from the tools', () {
    const alerts = ToolCallRecord(
      name: 'list_price_alerts',
      args: {},
      result: {
        'status': 'ok',
        'alerts': [
          {'symbol': 'VOO', 'condition': 'above', 'target': 750},
        ],
      },
    );
    String answer(String row) =>
        '{"version":"v0.9","updateComponents":{"surfaceId":"s","components":['
        '{"id":"root","component":"Column","children":["a","l"]},'
        '{"id":"a","component":"QaAnswerText","text":"Tus alertas."},'
        '{"id":"l","component":"QaInfoList","title":"Alertas","rows":[$row]}'
        ']}}';
    const evidence = TurnEvidence(calls: [alerts], turnCalls: [alerts]);

    test('a backed number passes; an invented one asks to fix it', () {
      expect(
        AssistantAnswerReview.check(
          answer('{"title":"VOO sube a \$750"}'),
          evidence,
        ),
        isNull,
      );
      final fix = AssistantAnswerReview.check(
        answer('{"title":"VOO sube a \$800"}'),
        evidence,
      );
      expect(fix?.message, contains('QaInfoList'));
    });

    test('if not fixed, the invented row is dropped', () {
      final out = AssistantAnswerReview.postProcess(
        answer('{"title":"VOO sube a \$750"},{"title":"NVDA baja a \$90"}'),
        evidence,
      );
      expect(out, contains('VOO sube a'));
      expect(out, isNot(contains('NVDA baja')));
    });
  });

  test('the custom cards need their tool', () {
    const raw =
        '{"updateComponents":{"components":['
        '{"id":"root","component":"Column","children":["w"]},'
        '{"id":"w","component":"QaWatchlist"}]}}';
    expect(AssistantGroundingCheck.check(raw, const []), isNotNull);
    expect(AssistantGroundingCheck.check(raw, [_watchlist]), isNull);
  });
}
