// QaSourceComparison: la card sale del resultado de compare_sources (medio y
// link en cada fila) y el chequeo de grounding de los medios nombrados.
// Correr: flutter test test/features/assistant/catalog/qa_source_comparison_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/catalog/assistant_catalog.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_evidence_scope.dart';
import 'package:portfolio_assistant/features/assistant/data/web/source_compare_fetcher.dart';
import 'package:portfolio_assistant/features/assistant/utils/assistant_answer_review.dart';
import 'package:portfolio_assistant/features/assistant/utils/assistant_grounding_check.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/shared/widgets/genui_error_card.dart';

import '../../../helpers/genui_test_helpers.dart';

/// Lo que devuelve el servidor (fixture compare_ok), ya validado por la app.
final _compare = ToolCallRecord(
  name: 'compare_sources',
  args: const {'ticker': 'NVDA'},
  result: SourceCompareFetcher.parse({
    'status': 'ok',
    'subject': 'NVIDIA (NVDA)',
    'points': [
      {
        'kind': 'agree',
        'text': 'Reuters y CNBC informan que los ingresos superaron las '
            'previsiones.',
        'source_ids': ['s1', 's2'],
      },
      {
        'kind': 'differ',
        'text': 'Según Bloomberg Línea, el foco está en los centros de datos.',
        'source_ids': ['s3'],
      },
      {
        'kind': 'only',
        'text': 'Según Expansión, la compañía anticipó mayores costos.',
        'source_ids': ['s4'],
      },
    ],
    'outlets': ['Reuters', 'CNBC', 'Bloomberg Línea', 'Expansión'],
    'sources': {
      's1': {'title': 'a', 'source': 'Reuters', 'url': 'https://reuters.com/a'},
      's2': {'title': 'b', 'source': 'CNBC', 'url': 'https://cnbc.com/b'},
      's3': {
        'title': 'c',
        'source': 'Bloomberg Línea',
        'url': 'https://bloomberglinea.com/c',
      },
      's4': {
        'title': 'd',
        'source': 'Expansión',
        'url': 'https://expansion.com/d',
      },
    },
    'as_of': '2026-12-02T08:05:00Z',
  }),
);

Future<void> _pump(WidgetTester tester, List<ToolCallRecord> calls) async {
  final catalog = AssistantCatalog.build(dailyBrief: true);
  final item = catalog.items.firstWhere((i) => i.name == 'QaSourceComparison');
  await tester.binding.setSurfaceSize(const Size(375, 2000));
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
                        component: {'id': 'c', 'component': 'QaSourceComparison'},
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

String _answer(String text, {bool card = true}) =>
    '{"version":"v0.9","updateComponents":{"surfaceId":"s","components":['
    '{"id":"root","component":"Column","children":["a"${card ? ',"c"' : ''}]},'
    '{"id":"a","component":"QaAnswerText","text":"$text"}'
    '${card ? ',{"id":"c","component":"QaSourceComparison"}' : ''}'
    ']}}';

void main() {
  testWidgets('every row has its text and its outlet link', (tester) async {
    await _pump(tester, [_compare]);
    expect(find.text('Qué dice cada medio'), findsOneWidget);
    expect(find.text('Coinciden'), findsOneWidget);
    expect(find.text('Difieren'), findsOneWidget);
    expect(find.text('Solo un medio'), findsOneWidget);
    for (final outlet in ['Reuters', 'CNBC', 'Bloomberg Línea', 'Expansión']) {
      expect(find.text(outlet), findsOneWidget, reason: outlet);
    }
    expect(find.textContaining('superaron las previsiones'), findsOneWidget);
    expect(find.textContaining('Medios:'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('without the tool result it draws nothing', (tester) async {
    await _pump(tester, const []);
    expect(find.text('Qué dice cada medio'), findsNothing);
  });

  group('grounding', () {
    test('the card needs an ok compare_sources', () {
      expect(AssistantGroundingCheck.check(_answer('Hola.'), const []),
          isNotNull);
      expect(AssistantGroundingCheck.check(_answer('Hola.'), [_compare]),
          isNull);
    });

    final evidence = TurnEvidence(calls: [_compare], turnCalls: [_compare]);

    test('an outlet named in the prose must be in the results (es and en)', () {
      expect(
        AssistantAnswerReview.check(
          _answer('Según Reuters, superaron lo previsto.'),
          evidence,
        ),
        isNull,
      );
      expect(
        AssistantAnswerReview.check(
          _answer('According to Bloomberg Línea, demand leads.'),
          evidence,
        ),
        isNull,
      );
      final es = AssistantAnswerReview.check(
        _answer('Según Financial Times, la acción cae.'),
        evidence,
      );
      expect(es?.message, contains('Financial Times'));
      expect(es?.requiresTools, isFalse);
      final en = AssistantAnswerReview.check(
        _answer('According to Forbes, it fell.'),
        evidence,
      );
      expect(en?.message, contains('Forbes'));
      final subject = AssistantAnswerReview.check(
        _answer('The Wall Street Journal says it fell.'),
        evidence,
      );
      expect(subject?.message, contains('Wall Street Journal'));
    });

    test('not an outlet: Porty, pronouns and lowercase attributions', () {
      for (final text in [
        'Según Porty, tu peso es bajo.',
        'Según tu cartera, es poco.',
        'Esto dice que casi no te toca.',
        'It says nothing about your holdings.',
      ]) {
        expect(
          AssistantAnswerReview.check(_answer(text, card: false), evidence),
          isNull,
          reason: text,
        );
      }
    });

    test('an outlet of the tapped headline (pinned context) is allowed', () {
      final pinned = TurnEvidence(
        calls: const [],
        pinnedContext: '{"screen_context":{"news":{"source":"Forbes"}}}',
      );
      expect(
        AssistantAnswerReview.check(
          _answer('Según Forbes, el titular dice eso.', card: false),
          pinned,
        ),
        isNull,
      );
    });
  });
}
