import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/data/card_numbers.dart';
import 'package:portfolio_assistant/features/assistant/services/assistant_openai_service.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';

/// El brief como viaja en el turno (ver `pinnedContextFor`).
TurnEvidence _withBrief(
  Map<String, Object?> brief, [
  List<ToolCallRecord> calls = const [],
]) => TurnEvidence(
  calls: calls,
  pinnedContext: AssistantOpenAiService.pinnedContextFor({
    'app_language': 'es',
    ...brief,
  }),
);

final _brief = <String, Object?>{
  'has_positions': true,
  'total_value': 24350.8,
  'total_cost_basis': 20000.0,
  'total_pnl_abs': 4350.8,
  'total_pnl_pct': 21.75,
  'period_returns': {
    'week': {
      'label_es': 'últimos 7 días',
      'pnl_abs': -320.5,
      'pnl_pct': -1.3,
      'value_start': 24671.3,
      'value_end': 24350.8,
      'has_sufficient_history': true,
    },
    'year': {
      'label_es': 'último año',
      'pnl_abs': 0,
      'pnl_pct': 0,
      'value_start': 0,
      'value_end': 24350.8,
      'has_sufficient_history': false,
    },
  },
  'positions': [
    {'ticker': 'VOO', 'weight_pct': 30.0, 'pnl_abs': 1},
    {'ticker': 'NVDA', 'weight_pct': 55.5, 'pnl_abs': 2},
    {'ticker': 'SGOV', 'weight_pct': 14.5, 'pnl_abs': 3},
  ],
  'closed_pnl_total_abs': 150.0,
  'closed_pnl_total_cost_basis': 1000.0,
  'closed_pnl_total_pct': 15.0,
};

ToolCallRecord _tool(String name, String key, Map<String, Object?> entry) =>
    ToolCallRecord(
      name: name,
      args: {
        'tickers': ['NVDA'],
      },
      result: {
        'status': 'ok',
        key: {'NVDA': entry},
      },
    );

void main() {
  group('portfolio cards (PORTFOLIO_BRIEF)', () {
    test('QaPeriodChange: the model sends the period, the app the numbers', () {
      final filled = CardNumbers.fill({
        'component': 'QaPeriodChange',
        'period': 'week',
      }, _withBrief(_brief));
      expect(filled, {
        'component': 'QaPeriodChange',
        'period': 'week',
        'periodLabel': 'últimos 7 días',
        'changeAbs': -320.5,
        'changePct': -1.3,
        'valueStart': 24671.3,
        'valueEnd': 24350.8,
      });
    });

    test('QaPeriodChange: a window without enough history is not filled', () {
      final c = {'component': 'QaPeriodChange', 'period': 'year'};
      expect(CardNumbers.fill(c, _withBrief(_brief)), c);
    });

    test('QaPositionsSnapshot: totals and weights, heaviest first', () {
      final filled = CardNumbers.fill({
        'component': 'QaPositionsSnapshot',
      }, _withBrief(_brief));
      expect(filled['totalValue'], 24350.8);
      expect(filled['pnlAbs'], 4350.8);
      expect(filled['pnlPct'], 21.75);
      expect(filled['positionsCount'], 3);
      expect(filled['positions'], [
        {'ticker': 'NVDA', 'weightPct': 55.5},
        {'ticker': 'VOO', 'weightPct': 30.0},
        {'ticker': 'SGOV', 'weightPct': 14.5},
      ]);
    });

    test('QaPnLBreakdown: open = since purchase, closed = realized', () {
      final open = CardNumbers.fill({
        'component': 'QaPnLBreakdown',
        'scope': 'open',
      }, _withBrief(_brief));
      expect(open['costBasis'], 20000.0);
      expect(open['currentValue'], 24350.8);
      expect(open['gainLoss'], 4350.8);
      expect(open['gainLossPercent'], 21.75);

      final closed = CardNumbers.fill({
        'component': 'QaPnLBreakdown',
        'scope': 'closed',
      }, _withBrief(_brief));
      expect(closed['costBasis'], 1000.0);
      expect(closed['currentValue'], 1150.0);
      expect(closed['gainLoss'], 150.0);
      expect(closed['gainLossPercent'], 15.0);
    });

    test('without a brief (or an old answer without the new fields) the '
        'card stays as the model sent it', () {
      final legacy = {
        'component': 'QaPnLBreakdown',
        'costBasis': 1,
        'currentValue': 2,
        'gainLoss': 1,
        'gainLossPercent': 100,
      };
      expect(CardNumbers.fill(legacy, _withBrief(_brief)), legacy);
      expect(
        CardNumbers.fill({
          'component': 'QaPositionsSnapshot',
        }, TurnEvidence.empty),
        {'component': 'QaPositionsSnapshot'},
      );
    });
  });

  group('QaEarningsCalendar (get_earnings)', () {
    final earnings = _tool('get_earnings', 'earnings', {
      'next_report': {
        'date': '2026-11-19',
        'date_label': '19 nov 2026',
        'fiscal_period_label': 'T3 FY27',
        'timing_label': 'Después del cierre',
        'eps_estimate': 0.85,
      },
      'latest_result': {
        'report_date_label': '27 ago 2026',
        'eps_actual': 0.81,
        'eps_estimate': 0.75,
        'beat': true,
      },
      'history': [
        {
          'fiscal_period_label': 'T1 FY27',
          'eps_actual': 0.6,
          'eps_estimate': 0.55,
        },
        {
          'fiscal_period_label': 'T2 FY27',
          'eps_actual': 0.81,
          'eps_estimate': 0.75,
        },
      ],
    });

    test('show next: only the upcoming report', () {
      final filled = CardNumbers.fill({
        'component': 'QaEarningsCalendar',
        'ticker': 'NVDA',
        'show': 'next',
      }, TurnEvidence(calls: [earnings]));
      expect(filled['nextReportDateLabel'], '19 nov 2026');
      expect(filled['nextReportDate'], '2026-11-19');
      expect(filled['timingLabel'], 'Después del cierre');
      expect(filled['fiscalPeriodLabel'], 'T3 FY27');
      expect(filled['nextEpsEstimate'], 0.85);
      expect(filled['nextReportEstimated'], false);
      expect(filled.containsKey('epsActual'), isFalse);
      expect(filled.containsKey('history'), isFalse);
    });

    test('show latest: last result and history, oldest first', () {
      final filled = CardNumbers.fill({
        'component': 'QaEarningsCalendar',
        'ticker': 'nvda',
        'show': 'latest',
      }, TurnEvidence(calls: [earnings]));
      expect(filled.containsKey('nextReportDateLabel'), isFalse);
      expect(filled['latestReportDateLabel'], '27 ago 2026');
      expect(filled['epsActual'], 0.81);
      expect(filled['epsEstimate'], 0.75);
      expect(filled['beat'], true);
      expect(filled['history'], [
        {'periodLabel': 'T1 FY27', 'epsActual': 0.6, 'epsEstimate': 0.55},
        {'periodLabel': 'T2 FY27', 'epsActual': 0.81, 'epsEstimate': 0.75},
      ]);
    });

    test('SEC (no consensus): EPS with its year-over-year change', () {
      final sec = _tool('get_earnings', 'earnings', {
        'next_report': {
          'date': '2026-11-19',
          'date_label': '19 nov 2026',
          'estimated': true,
        },
        'latest_result': {
          'fiscal_period_label': 'T2 FY27',
          'eps_actual': 0.81,
          'eps_yoy_pct': 12.5,
        },
        'history': [
          {
            'fiscal_period_label': 'T1 FY27',
            'eps_actual': 0.6,
            'eps_yoy_pct': 5,
          },
          {
            'fiscal_period_label': 'T2 FY27',
            'eps_actual': 0.81,
            'eps_yoy_pct': 12.5,
          },
        ],
      });
      final filled = CardNumbers.fill({
        'component': 'QaEarningsCalendar',
        'ticker': 'NVDA',
        'show': 'both',
      }, TurnEvidence(calls: [sec]));
      expect(filled['nextReportEstimated'], true);
      expect(filled['latestReportDateLabel'], 'T2 FY27');
      expect(filled['epsYoyPct'], 12.5);
      expect(filled.containsKey('epsEstimate'), isFalse);
      expect((filled['history'] as List).last, {
        'periodLabel': 'T2 FY27',
        'epsActual': 0.81,
        'epsYoyPct': 12.5,
      });
    });
  });

  group('QaFundamentals (get_fundamentals)', () {
    final fundamentals = _tool('get_fundamentals', 'fundamentals', {
      'industry': 'Semiconductors',
      'pe_ttm': 38.62,
      'market_capitalization': 4977637,
      'net_margin_ttm': 27.6,
      'dividend_yield_indicated_annual': 0.02,
      'beta': 1.734,
      'week_52_low': 86.6,
      'week_52_high': 153.1,
    });
    final quote = ToolCallRecord(
      name: 'get_quote',
      args: const {
        'tickers': ['NVDA'],
      },
      result: const {
        'status': 'ok',
        'tickers': {
          'NVDA': {'fetch_ok': true, 'current_price': 120.5},
        },
      },
    );

    test('the model picks the metrics; the app formats them, in order, '
        'skipping absent ones', () {
      final filled = CardNumbers.fill({
        'component': 'QaFundamentals',
        'ticker': 'NVDA',
        'metrics': ['net_margin_ttm', 'pe_ttm', 'roe_ttm', 'beta'],
      }, TurnEvidence(calls: [fundamentals, quote]));
      final items = (filled['items'] as List).cast<Map>();
      expect(items.map((i) => i['group']), [
        'profitability',
        'valuation',
        'other',
      ]);
      expect(items[0]['value'], '27,6%');
      expect(items[1]['value'], '38,6x');
      expect(items[2], {'label': 'Beta', 'value': '1,73', 'group': 'other'});
      // Sin overview: ni industria ni rango de 52 semanas.
      expect(filled.containsKey('week52Low'), isFalse);
      expect(filled.containsKey('industry'), isFalse);
    });

    test('overview adds industry, the 52-week range and the price', () {
      final filled = CardNumbers.fill({
        'component': 'QaFundamentals',
        'ticker': 'NVDA',
        'metrics': ['market_capitalization', 'dividend_yield_indicated_annual'],
        'overview': true,
      }, TurnEvidence(calls: [fundamentals, quote]));
      final items = (filled['items'] as List).cast<Map>();
      expect(items.map((i) => i['group']), ['valuation', 'dividend']);
      expect(items.first['value'], contains('T'));
      expect(filled['industry'], 'Semiconductors');
      expect(filled['week52Low'], 86.6);
      expect(filled['week52High'], 153.1);
      expect(filled['currentPrice'], 120.5);
    });

    test('a locked or missing get_fundamentals leaves the card untouched', () {
      final c = {
        'component': 'QaFundamentals',
        'ticker': 'NVDA',
        'metrics': ['pe_ttm'],
      };
      const locked = ToolCallRecord(
        name: 'get_fundamentals',
        args: {
          'tickers': ['NVDA'],
        },
        result: {'status': 'locked'},
      );
      expect(CardNumbers.fill(c, TurnEvidence(calls: const [locked])), c);
      expect(
        jsonEncode(CardNumbers.fill(c, TurnEvidence.empty)),
        jsonEncode(c),
      );
    });
  });
}
