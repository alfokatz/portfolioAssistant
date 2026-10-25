import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_calculator.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/assistant/models/action_proposal.dart';
import 'package:portfolio_assistant/features/assistant/tools/action_tools.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_tool_context.dart';
import 'package:portfolio_assistant/features/assistant/utils/portfolio_context_builder.dart';

import '../fakes/assistant_fakes.dart';

/// VOO solo de eToro; AAPL mitad manual, mitad eToro; MSFT solo manual.
final _summary = PortfolioCalculator.summarize([
  for (final (id, ticker, qty, source) in [
    ('voo-e', 'VOO', 2.0, PositionSource.etoro),
    ('aapl-m', 'AAPL', 3.0, PositionSource.manual),
    ('aapl-e', 'AAPL', 10.0, PositionSource.etoro),
    ('msft-m', 'MSFT', 1.0, PositionSource.manual),
  ])
    PortfolioCalculator.valuate(
      position: Position(
        id: id,
        ticker: ticker,
        quantity: qty,
        purchasePrice: 100,
        purchaseDate: DateTime(2025, 1, 1),
        source: source,
      ),
      currentPrice: 120,
    ),
]);

AssistantToolContext _ctx() => AssistantToolContext(
  tier: SubscriptionTier.premium,
  data: fakeDataSources(),
  summary: _summary,
  now: DateTime(2026, 9, 29),
);

void main() {
  test('el asistente ve TODA la cartera, con el origen de lo importado', () {
    final map = PortfolioContextBuilder.buildMap(_summary, asOf: DateTime(2026, 9, 29));
    final positions = {
      for (final p in map['positions'] as List) (p as Map)['ticker']: p,
    };
    expect(positions.keys.toSet(), {'VOO', 'AAPL', 'MSFT'});
    expect(positions['VOO']!['source'], 'etoro');
    expect(positions['AAPL']!['source'], 'mixed');
    // Las manuales no cambian: sin campo nuevo.
    expect(positions['MSFT']!.containsKey('source'), isFalse);
  });

  test('cerradas de eToro: el P&L es el neto del bróker y se aclara', () {
    final map = PortfolioContextBuilder.buildMap(
      null,
      closedPositions: [
        ClosedPosition(
          id: 'c',
          ticker: 'UNH',
          quantity: 2,
          avgPurchasePrice: 300,
          closePrice: 320,
          closeDate: DateTime(2026, 6, 24),
          closedAt: DateTime(2026, 6, 24),
          source: PositionSource.etoro,
          realizedPnl: 38.5,
        ),
      ],
      asOf: DateTime(2026, 9, 29),
    );
    final closed = (map['closed_positions'] as List).single as Map;
    expect(closed['pnl_abs'], 38.5);
    expect(closed['source'], 'etoro');
    expect(closed['pnl_includes_fees'], isTrue);
  });

  test('vender o borrar algo que solo está en eToro → managed_by_broker', () async {
    final sell = await ProposeSellTool(_ctx()).run({
      'ticker': 'VOO',
      'all': true,
      'date': '2026-09-25',
    });
    expect(sell, {'status': 'invalid', 'reason': 'managed_by_broker'});

    final delete = await ProposeDeletePositionTool(_ctx()).run({'ticker': 'VOO'});
    expect(delete['reason'], 'managed_by_broker');
  });

  test('ticker mixto: solo se puede vender/borrar lo cargado a mano', () async {
    final tooMuch = await ProposeSellTool(_ctx()).run({
      'ticker': 'AAPL',
      'shares': 5,
      'date': '2026-09-25',
    });
    expect(tooMuch['reason'], 'exceeds_holdings');
    expect(tooMuch['held_shares'], 3);

    final delete = await ProposeDeletePositionTool(_ctx()).run({'ticker': 'AAPL'});
    final proposal = ActionProposal.fromToolResult(delete)!;
    expect(proposal.lots.map((l) => l.id), ['aapl-m']);
    expect(proposal.heldShares, 3);
  });

  test('lo que no está en la cartera sigue siendo not_held', () async {
    final r = await ProposeDeletePositionTool(_ctx()).run({'ticker': 'TSLA'});
    expect(r['reason'], 'not_held');
  });

  test('conectar eToro está en Premium y Gold, no en Free', () {
    expect(PlanMatrix.allows(SubscriptionTier.free, PlanFeature.brokerSync), isFalse);
    expect(PlanMatrix.allows(SubscriptionTier.premium, PlanFeature.brokerSync), isTrue);
    expect(PlanMatrix.allows(SubscriptionTier.gold, PlanFeature.brokerSync), isTrue);
    expect(PlanMatrix.minimumTier(PlanFeature.brokerSync), SubscriptionTier.premium);
  });
}
