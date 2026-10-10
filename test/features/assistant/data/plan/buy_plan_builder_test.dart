import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/investor_profile.dart';
import 'package:portfolio_assistant/features/assistant/data/market/dividend_fetcher.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/buy_plan_builder.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/goal_projection_builder.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/savings_plan_calculator.dart';

import '../../fakes/assistant_fakes.dart';

Map<String, Object?> _incomePlan({RiskTolerance? risk}) =>
    GoalProjectionBuilder.build(
      currentPortfolioValue: 0,
      desiredMonthlyIncome: 3000,
      targetDate: DateTime(2051, 10, 9),
      statedRisk: risk,
      asOf: DateTime(2026, 10, 9),
    );

/// Una meta con monto (no de dividendos): sin reglas de composición.
Map<String, Object?> _targetPlan() => GoalProjectionBuilder.build(
  currentPortfolioValue: 0,
  targetAmount: 500000,
  label: 'Jubilación',
  targetDate: DateTime(2046, 10, 9),
  asOf: DateTime(2026, 10, 9),
);

Map<String, Object?> _info(String name, {bool etf = true, double? y}) =>
    DividendFetcher.parse(
      dividendQuoteSummary(name: name, etf: etf, yieldFraction: y),
    );

const _equities = PlanAssetClass.equities;
const _bonds = PlanAssetClass.bonds;
const _cash = PlanAssetClass.cash;

void main() {
  group('DividendFetcher.parse', () {
    test('ETF yield and stock dividend yield, in %', () {
      final etf = _info('Schwab US Dividend Equity ETF', y: 0.0362);
      expect(etf['kind'], 'etf');
      expect(etf['dividend_yield_pct'], 3.62);
      final stock = DividendFetcher.parse(
        dividendQuoteSummary(
          name: 'Coca-Cola',
          etf: false,
          yieldFraction: 0.029,
          dividendRate: 2.04,
        ),
      );
      expect(stock['kind'], 'stock');
      expect(stock['dividend_yield_pct'], 2.9);
      expect(stock['dividend_per_share_annual'], 2.04);
      expect(stock['ex_dividend_date'], isA<String>());
    });

    test('no dividend field → 0 (pays none), not missing', () {
      expect(_info('Growth ETF')['dividend_yield_pct'], 0.0);
    });
  });

  group('BuyPlanBuilder', () {
    final info = {
      'SCHD': _info('Schwab US Dividend Equity ETF', y: 0.036),
      'VYM': _info('Vanguard High Dividend Yield ETF', y: 0.028),
      'KO': _info('Coca-Cola', etf: false, y: 0.029),
      'JNJ': _info('Johnson & Johnson', etf: false, y: 0.032),
      'BND': _info('Vanguard Total Bond Market ETF', y: 0.038),
      'SGOV': _info('iShares 0-3 Month Treasury Bond ETF', y: 0.045),
    };

    Map<String, Object?> build(
      List<BuyPlanPick> picks, {
      Map<String, Object?>? base,
      Map<String, Object?>? withInfo,
    }) => BuyPlanBuilder.build(
      base: base ?? _incomePlan(),
      picks: picks,
      info: withInfo ?? info,
    );

    Map<String, Map> byTicker(Map<String, Object?> r) => {
      for (final i in (r['items'] as List).cast<Map>()) '${i['ticker']}': i,
    };

    test('follows the plan allocation; ETFs carry the stocks remainder', () {
      final r = build(const [
        BuyPlanPick('SCHD', _equities),
        BuyPlanPick('VYM', _equities),
        BuyPlanPick('KO', _equities),
        BuyPlanPick('BND', _bonds),
        BuyPlanPick('SGOV', _cash),
      ]);
      expect(r['status'], 'ok');
      final items = byTicker(r);
      // Moderada: 60 / 35 / 5.
      final equities =
          (items['SCHD']!['pct'] as int) +
          (items['VYM']!['pct'] as int) +
          (items['KO']!['pct'] as int);
      expect(equities, 60);
      expect(items['BND']!['pct'], 35);
      expect(items['SGOV']!['pct'], 5);
      expect(items['KO']!['pct'], lessThanOrEqualTo(15));
      expect(items['SCHD']!['kind'], 'etf');
      expect(items['KO']!['kind'], 'stock');
      final pcts = [for (final i in items.values) i['pct'] as int];
      expect(pcts.reduce((a, b) => a + b), 100);
      final amounts = [
        for (final i in items.values) i['monthly_amount'] as int,
      ];
      expect(amounts.reduce((a, b) => a + b), r['monthly_amount']);
    });

    test('an individual stock never goes over 15% next to ETFs', () {
      final r = build(const [
        BuyPlanPick('SCHD', _equities),
        BuyPlanPick('KO', _equities),
        BuyPlanPick('BND', _bonds),
      ]);
      final items = byTicker(r);
      expect(items['KO']!['pct'], 15);
      expect(items['SCHD']!['pct'], greaterThan(40));
    });

    test('a class without an instrument is spread over the others', () {
      final r = build(const [
        BuyPlanPick('SCHD', _equities),
        BuyPlanPick('BND', _bonds),
      ], base: _targetPlan());
      expect(r['classes_without_instrument'], ['cash']);
      final items = byTicker(r);
      expect(
        (items['SCHD']!['pct'] as int) + (items['BND']!['pct'] as int),
        100,
      );
      expect(items['SCHD']!['pct'], 63); // 60 / 95
    });

    test('the real weighted yield replaces the 3.5% and moves the goal', () {
      final r = build(const [
        BuyPlanPick('SCHD', _equities),
        BuyPlanPick('KO', _equities),
        BuyPlanPick('BND', _bonds),
      ]);
      expect(r['yield_source'], 'real');
      final y = r['weighted_dividend_yield_pct'] as double;
      expect(y, inInclusiveRange(3.51, 3.8));
      final before = r['plan_before'] as Map;
      final after = r['plan_after'] as Map;
      // Más rendimiento → hace falta menos capital para los mismos 3000.
      expect(after['target_amount'], lessThan(before['target_amount'] as int));
      expect(
        after['required_monthly_savings'],
        lessThan(before['required_monthly_savings'] as int),
      );
      expect(r['plan_id'], isNot(_incomePlan()['plan_id']));
      expect(r['active_goal'], isA<Map>());
    });

    test('without enough yield data it keeps the assumption', () {
      final r = build(
        const [BuyPlanPick('SCHD', _equities), BuyPlanPick('BND', _bonds)],
        base: _targetPlan(),
        withInfo: {
          'SCHD': const {'status': 'failed'},
          'BND': info['BND'],
        },
      );
      expect(r['yield_source'], 'assumption');
      expect(
        (r['plan_after'] as Map)['target_amount'],
        (r['plan_before'] as Map)['target_amount'],
      );
    });

    test('unknown tickers are dropped and reported', () {
      final r = build(
        const [BuyPlanPick('SCHD', _equities), BuyPlanPick('XXXX', _bonds)],
        base: _targetPlan(),
        withInfo: {
          'SCHD': info['SCHD'],
          'XXXX': const {'status': 'empty'},
        },
      );
      expect(r['unknown_tickers'], ['XXXX']);
      expect(byTicker(r).keys, ['SCHD']);
      expect(byTicker(r)['SCHD']!['pct'], 100);
    });

    test('a plan to live off dividends needs dividend ETFs and a stock', () {
      final info2 = {
        ...info,
        'VTI': _info('Vanguard Total Stock Market ETF', y: 0.013),
      };
      final onlyMarket = build(const [
        BuyPlanPick('VTI', _equities),
        BuyPlanPick('BND', _bonds),
      ], withInfo: info2);
      expect(onlyMarket['status'], 'needs_retry');
      expect(onlyMarket['reason'], contains('2 dividend-focused ETFs'));
      expect(onlyMarket['reason'], contains('VTI (1.3%)'));

      final noStock = build(const [
        BuyPlanPick('SCHD', _equities),
        BuyPlanPick('VYM', _equities),
        BuyPlanPick('BND', _bonds),
      ]);
      expect(noStock['status'], 'needs_retry');
      expect(noStock['reason'], contains('individual dividend-paying stocks'));

      // La misma compra para una meta con monto: sin reglas de dividendos.
      expect(
        build(
          const [BuyPlanPick('VTI', _equities), BuyPlanPick('BND', _bonds)],
          base: _targetPlan(),
          withInfo: info2,
        )['status'],
        'ok',
      );
    });

    test('same picks → same id', () {
      const picks = [
        BuyPlanPick('SCHD', _equities),
        BuyPlanPick('BND', _bonds),
      ];
      expect(build(picks)['buy_plan_id'], build(picks)['buy_plan_id']);
    });
  });
}
