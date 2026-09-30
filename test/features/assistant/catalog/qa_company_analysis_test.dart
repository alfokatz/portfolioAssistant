import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/catalog/assistant_catalog.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_evidence_scope.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_follow_up_scope.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_primitives.dart';
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
      'held': false,
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

final _fundamentals = _call('get_fundamentals', {
  'status': 'ok',
  'fundamentals': {
    'BAC': {
      'company_name': 'Bank of America Corp',
      'industry': 'Banking',
      'pe_ttm': 11.63,
      'net_margin_ttm': 30.16,
      'roe_ttm': 11.13,
      'dividend_yield_indicated_annual': 3.23,
      'beta': 1.2,
      'week_52_high': 52.4,
      'week_52_low': 33.1,
    },
  },
});

final _earnings = _call('get_earnings', {
  'status': 'ok',
  'earnings': {
    'BAC': {
      'next_report': {
        'date_label': '14 oct 2026',
        'date': '2026-10-14',
        'fiscal_period_label': 'T3 FY26',
        'eps_estimate': 0.95,
      },
      'latest_result': {
        'report_date_label': '15 jul 2026',
        'eps_actual': 0.89,
        'eps_estimate': 0.86,
        'beat': true,
      },
    },
  },
});

final _news = _call('get_news', {
  'status': 'ok',
  'news': [
    {
      'ticker': 'BAC',
      'title': 'Bank of America raises dividend after stress test',
      'url': 'https://example.com/a',
      'source': 'Reuters',
      'published_at': '2026-09-28T10:00:00Z',
    },
  ],
});

ToolCallRecord _locked(String name) =>
    _call(name, {'status': 'locked', 'required_plan': 'gold'});

String _brief({bool held = false}) =>
    'PORTFOLIO_BRIEF — cartera:\n${jsonEncode({
      'positions': [
        if (held) {'ticker': 'BAC', 'market_value': 946.2, 'pnl_abs': 120.5, 'pnl_pct': 14.6, 'weight_pct': 22.4},
      ],
    })}';

const _prose = {
  'id': 'analysis',
  'component': 'QaCompanyAnalysis',
  'ticker': 'BAC',
  'summary':
      'Es uno de los bancos más grandes de Estados Unidos y gana bien con lo '
      'que presta.',
  'keyPoints': [
    {
      'tone': 'strength',
      'text': 'Rentabilidad alta: gana 30 de cada 100 dólares que vende.',
    },
    {'tone': 'watch', 'text': 'Depende de las tasas de interés.'},
  ],
  'metrics': [
    {'key': 'pe_ttm', 'explanation': 'Pagás 11,6 veces lo que gana por año.'},
    {
      'key': 'net_margin_ttm',
      'explanation': 'De cada 100 dólares, le quedan 30.',
    },
  ],
  'newsTake': 'Los titulares hablan sobre todo de su dividendo.',
};

Future<void> _pump(
  WidgetTester tester, {
  required List<ToolCallRecord> calls,
  Map<String, Object?> prose = _prose,
  bool held = false,
  bool reduceMotion = true,
  ValueChanged<String>? onFollowUp,
}) async {
  final catalog = AssistantCatalog.build();
  final item = catalog.items.firstWhere((i) => i.name == 'QaCompanyAnalysis');
  final evidence = TurnEvidence(
    calls: calls,
    pinnedContext: _brief(held: held),
  );
  await tester.binding.setSurfaceSize(const Size(390, 2400));
  Widget body = Scaffold(
    body: SingleChildScrollView(
      child: Builder(
        builder:
            (context) => item.widgetBuilder(
              catalogContextFor(
                buildContext: context,
                component: Map<String, dynamic>.from(prose),
                catalog: catalog,
                surfaceId: 's1',
              ),
            ),
      ),
    ),
  );
  if (onFollowUp != null) {
    body = QaFollowUpScope(onFollowUp: onFollowUp, child: body);
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(extensions: const [CustomColors.light]),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: QaEvidenceScope(
          lookup: (_) => ValueNotifier(evidence),
          child: body,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('full analysis: every section, numbers from the tools', (
    tester,
  ) async {
    await _pump(tester, calls: [_quote, _fundamentals, _earnings, _news]);

    expect(find.text('Bank of America Corp · Banking'), findsOneWidget);
    expect(find.text('\$47.31'), findsOneWidget);
    expect(find.text('+4.2%'), findsOneWidget); // PnlBadge
    expect(find.text('EN RESUMEN'), findsOneWidget);
    expect(find.textContaining('gana 30 de cada 100'), findsOneWidget);
    // Valor formateado por la app (no copiado del modelo).
    expect(find.text('11,6x'), findsOneWidget);
    expect(find.text('30,2%'), findsOneWidget);
    expect(find.byType(QaRangeBar), findsOneWidget);
    expect(find.textContaining('de su máximo de 52 semanas'), findsOneWidget);
    expect(find.text('Superó'), findsOneWidget);
    expect(find.text('14 oct 2026'), findsOneWidget);
    expect(find.textContaining('raises dividend'), findsOneWidget);
    expect(find.text('Riesgo medio'), findsOneWidget);
    expect(find.text('EN TU CARTERA'), findsNothing);
    expect(
      find.text(
        'Análisis informativo, no asesoramiento financiero personalizado.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('held ticker adds the "En tu cartera" row', (tester) async {
    await _pump(tester, calls: [_quote, _fundamentals], held: true);
    expect(find.text('EN TU CARTERA'), findsOneWidget);
    expect(find.text('22,4%'), findsOneWidget);
    expect(find.text('+\$121'), findsOneWidget);
  });

  testWidgets('sections without data are omitted, never "N/A"', (tester) async {
    await _pump(tester, calls: [_quote], prose: {..._prose, 'newsTake': ''});
    expect(find.text('\$47.31'), findsOneWidget);
    expect(find.text('VALUACIÓN Y RENTABILIDAD'), findsNothing);
    expect(find.text('RESULTADOS'), findsNothing);
    expect(find.text('NOTICIAS'), findsNothing);
    expect(find.text('RIESGO'), findsNothing);
    expect(find.byType(QaRangeBar), findsNothing);
    expect(find.textContaining('N/A'), findsNothing);
  });

  testWidgets('sources outside the plan show a compact Gold notice', (
    tester,
  ) async {
    await _pump(
      tester,
      calls: [
        _quote,
        _locked('get_fundamentals'),
        _locked('get_earnings'),
        _locked('get_news'),
      ],
    );
    // Tope: UN solo bloque bloqueado por card, que nombra todo lo de Gold.
    expect(find.text('Incluido en el plan Gold'), findsOneWidget);
    expect(find.text('Valuación, resultados y noticias'), findsOneWidget);
    // El resto se muestra igual.
    expect(find.text('\$47.31'), findsOneWidget);
    expect(find.textContaining('bancos más grandes'), findsOneWidget);
  });

  testWidgets('an invented number in the prose is dropped before rendering', (
    tester,
  ) async {
    await _pump(
      tester,
      calls: [_quote, _fundamentals],
      prose: {
        ..._prose,
        'summary': 'Es un banco grande. Su P/E está 40% debajo del sector.',
      },
    );
    expect(find.text('Es un banco grande.'), findsOneWidget);
    expect(find.textContaining('40%'), findsNothing);
  });

  testWidgets('follow-ups: Gráfico/Noticias/Earnings, never Análisis again', (
    tester,
  ) async {
    final sent = <String>[];
    await _pump(tester, calls: [_quote, _fundamentals], onFollowUp: sent.add);
    expect(find.text('Análisis'), findsNothing);
    expect(find.text('Gráfico'), findsOneWidget);
    expect(find.text('Noticias'), findsWidgets);
  });

  testWidgets('entrance animates in, but reduce motion shows it at once', (
    tester,
  ) async {
    await _pump(tester, calls: [_quote, _fundamentals], reduceMotion: false);
    // Con animación: termina de entrar y todo queda visible.
    await tester.pumpAndSettle();
    expect(find.text('11,6x'), findsOneWidget);

    await _pump(tester, calls: [_quote, _fundamentals]);
    final opacities = tester.widgetList<Opacity>(
      find.ancestor(of: find.text('11,6x'), matching: find.byType(Opacity)),
    );
    expect(opacities.every((o) => o.opacity == 1), isTrue);
  });

  test('catalog exposes QaCompanyAnalysis with a text-only schema', () {
    final item = AssistantCatalog.build().items.firstWhere(
      (i) => i.name == 'QaCompanyAnalysis',
    );
    // genui agrega `component`; el resto es todo texto: ningún número.
    final props =
        (item.dataSchema.value['properties'] as Map).keys.toSet()
          ..remove('component');
    expect(props, {'ticker', 'summary', 'keyPoints', 'metrics', 'newsTake'});
    expect(item.exampleData, isNotEmpty);
  });
}
