import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/assistant/catalog/assistant_catalog.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_evidence_scope.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_follow_up_scope.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_gold_lock.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_identity.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_plan_scope.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_skeleton.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

import '../../../helpers/genui_test_helpers.dart';

ToolCallRecord _call(String name, Map<String, Object?> result) =>
    ToolCallRecord(
      name: name,
      args: const {
        'tickers': ['BAC'],
      },
      result: result,
    );

final _quote = _call('get_quote', {
  'status': 'ok',
  'tickers': {
    'BAC': {
      'fetch_ok': true,
      'current_price': 47.31,
      'periods': {
        'month': {
          'change_pct': 4.2,
          'label_es': 'Último mes',
          'has_sufficient_history': true,
        },
      },
    },
  },
});

ToolCallRecord _locked(String name) =>
    _call(name, {'status': 'locked', 'required_plan': 'gold'});

List<ToolCallRecord> _gold({bool courtesy = false}) => [
  _call('get_fundamentals', {
    'status': 'ok',
    if (courtesy) 'courtesy': 'weekly_free_analysis',
    'fundamentals': {
      'BAC': {
        'pe_ttm': 11.63,
        'net_margin_ttm': 30.16,
        'roe_ttm': 11.13,
        'beta': 1.2,
        'week_52_high': 52.4,
        'week_52_low': 33.1,
      },
    },
  }),
  _call('get_earnings', {
    'status': 'ok',
    'earnings': {
      'BAC': {
        'latest_result': {
          'eps_actual': 0.89,
          'eps_estimate': 0.86,
          'beat': true,
        },
      },
    },
  }),
  _call('get_news', {
    'status': 'ok',
    'news': [
      {
        'ticker': 'BAC',
        'title': 'Bank of America raises dividend',
        'url': 'https://example.com/a',
        'source': 'Reuters',
        'published_at': '2026-09-28T10:00:00Z',
      },
    ],
  }),
];

final _premiumLocked = TurnEvidence(
  calls: [
    _quote,
    _locked('get_fundamentals'),
    _locked('get_earnings'),
    _locked('get_news'),
  ],
);

const _prose = {
  'id': 'analysis',
  'component': 'QaCompanyAnalysis',
  'ticker': 'BAC',
  'summary': 'Es uno de los bancos más grandes de Estados Unidos.',
};

class _Harness {
  final requests = <QaPaywallRequest>[];
  final haptics = <PortyHapticPattern>[];
  final sent = <String>[];
}

Future<_Harness> _pump(
  WidgetTester tester, {
  required ValueNotifier<TurnEvidence> evidence,
  SubscriptionTier tier = SubscriptionTier.premium,
  bool? weeklyFree = false,
  bool reduceMotion = true,
  Widget Function(BuildContext)? body,
  _Harness? reuse,
}) async {
  final h = reuse ?? _Harness();
  final catalog = AssistantCatalog.build();
  final item = catalog.items.firstWhere((i) => i.name == 'QaCompanyAnalysis');
  await tester.binding.setSurfaceSize(const Size(390, 2200));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        portyHapticsServiceProvider.overrideWithValue(
          PortyHapticsService(
            enabled: true,
            performer: (p) async => h.haptics.add(p),
          ),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData(extensions: const [CustomColors.light]),
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: QaPlanScope(
            tier: tier,
            weeklyFreeAnalysisAvailable: weeklyFree,
            heldTickers: const {'AAPL'},
            openPaywall: h.requests.add,
            child: QaFollowUpScope(
              onFollowUp: h.sent.add,
              child: QaEvidenceScope(
                lookup: (_) => evidence,
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: Builder(
                      builder:
                          body ??
                          (context) => item.widgetBuilder(
                            catalogContextFor(
                              buildContext: context,
                              component: Map<String, dynamic>.from(_prose),
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
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  return h;
}

void main() {
  testWidgets('tapping the locked block: selection haptic at once, then the '
      'Gold paywall with its source', (tester) async {
    final h = await _pump(tester, evidence: ValueNotifier(_premiumLocked));

    final lock = find.text('Valuación, resultados y noticias');
    final gesture = await tester.startGesture(tester.getCenter(lock));
    expect(h.haptics, [PortyHapticPattern.selection], reason: 'en el tap-down');
    expect(h.requests, isEmpty);
    await gesture.up();
    await tester.pump();

    expect(h.requests, hasLength(1));
    expect(h.requests.single.source, 'analysis_locked_group');
    expect(h.requests.single.ticker, 'BAC');
    expect(h.requests.single.surfaceId, 's1');
    expect(
      find.bySemanticsLabel(RegExp('Desbloquear con Gold')),
      findsOneWidget,
    );
  });

  testWidgets('at most ONE locked block per card, and no locked chip on top',
      (tester) async {
    await _pump(tester, evidence: ValueNotifier(_premiumLocked));
    expect(find.byType(QaGoldLock), findsOneWidget);
    // Los chips de Noticias/Earnings no aparecen con candado.
    expect(find.text('Gold'), findsOneWidget); // solo el del bloque
  });

  testWidgets('the paywall preview shows real header data and skeletons, '
      'never numbers of locked sections', (tester) async {
    final h = await _pump(tester, evidence: ValueNotifier(_premiumLocked));
    await tester.tap(find.text('Valuación, resultados y noticias'));
    await tester.pump();
    final preview = h.requests.single.preview!;

    await _pump(
      tester,
      evidence: ValueNotifier(_premiumLocked),
      body: preview,
      reuse: h,
    );
    expect(find.text('\$47.31'), findsOneWidget);
    expect(find.byType(QaSkeleton), findsNWidgets(3));
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
        .where((t) => RegExp(r'\d').hasMatch(t))
        .toSet();
    // Solo los números del encabezado (precio y variación de Premium).
    expect(texts, {'\$47.31', '+4.2%'});
  });

  testWidgets('weekly free analysis: text while available, full analysis '
      'marked as courtesy, and it goes away animated once used', (tester) async {
    final harness = _Harness();
    Widget bar(BuildContext _) => QaFollowUpBar(
      items: QaTickerFollowUps.of('BAC'),
      limit: 3,
    );
    await _pump(
      tester,
      evidence: ValueNotifier(_premiumLocked),
      weeklyFree: true,
      body: bar,
      reuse: harness,
    );
    expect(find.text('1 análisis Gold gratis esta semana'), findsOneWidget);
    await tester.tap(find.text('Análisis'));
    expect(harness.sent, ['Haceme un análisis de BAC']);

    // El análisis de cortesía sale completo y lo dice.
    await _pump(
      tester,
      evidence: ValueNotifier(TurnEvidence(calls: [_quote, ..._gold(courtesy: true)])),
      reuse: harness,
    );
    expect(find.text('Análisis Gold de cortesía'), findsOneWidget);
    expect(find.text('11,6x'), findsOneWidget);
    await tester.tap(find.text('Conocer Gold'));
    expect(harness.requests.last.source, 'weekly_free_analysis');

    // Usado: el texto se va con transición (no de golpe) y "Análisis" vuelve
    // a tener candado.
    await _pump(
      tester,
      evidence: ValueNotifier(_premiumLocked),
      weeklyFree: true,
      body: bar,
      reuse: harness,
      reduceMotion: false,
    );
    final before = tester.getSize(find.byType(QaFollowUpBar)).height;
    await _pump(
      tester,
      evidence: ValueNotifier(_premiumLocked),
      weeklyFree: false,
      body: bar,
      reuse: harness,
      reduceMotion: false,
    );
    await tester.pumpAndSettle();
    final after = tester.getSize(find.byType(QaFollowUpBar)).height;
    expect(after, lessThan(before));
    expect(find.text('1 análisis Gold gratis esta semana'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('Desbloquear con Gold: Análisis')), findsOneWidget);
  });

  testWidgets('after buying: skeletons while loading, then the sections open '
      'in place with a close haptic, space animated (no jump)', (tester) async {
    final evidence = ValueNotifier(_premiumLocked);
    final h = await _pump(tester, evidence: evidence, reduceMotion: false);
    await tester.pumpAndSettle();
    h.haptics.clear();
    final cardBefore = tester.getSize(find.byType(QaGoldLock)).height;

    evidence.value = evidence.value.copyWith(loading: true);
    await tester.pump();
    // El shimmer repite: no hay "settle"; alcanza con pasar la transición.
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(QaSkeleton), findsWidgets);
    expect(find.byType(QaGoldLock), findsNothing);

    evidence.value = evidence.value.copyWith(
      calls: [...evidence.value.calls, ..._gold()],
      loading: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    // A mitad de la transición el espacio está creciendo, no saltó.
    final mid = tester.getSize(find.byType(AnimatedSize).first).height;
    await tester.pumpAndSettle();
    final end = tester.getSize(find.byType(AnimatedSize).first).height;
    expect(mid, lessThan(end));
    expect(cardBefore, lessThan(end));
    expect(find.text('11,6x'), findsOneWidget);
    expect(find.text('Superó'), findsOneWidget);
    expect(h.haptics, [PortyHapticPattern.medium]);
  });

  testWidgets('reduce motion: no animation, no shimmer', (tester) async {
    await _pump(
      tester,
      evidence: ValueNotifier(_premiumLocked.copyWith(loading: true)),
    );
    expect(find.byType(QaSkeleton), findsWidgets);
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('rebuilding history: an already-open card never re-animates '
      'nor vibrates', (tester) async {
    final open = ValueNotifier(TurnEvidence(calls: [_quote, ..._gold()]));
    final h = await _pump(tester, evidence: open);
    await _pump(tester, evidence: open, reuse: h);
    expect(h.haptics, isEmpty);
    expect(find.byType(QaGoldLock), findsNothing);
  });

}
