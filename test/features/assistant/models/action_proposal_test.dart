import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/models/action_proposal.dart';
import 'package:portfolio_assistant/features/assistant/states/assistant_state.dart';

void main() {
  group('ActionProposal tool result', () {
    test('a buy survives the round trip', () {
      final proposal = ActionProposal(
        id: 'p1',
        kind: ActionKind.buy,
        ticker: 'AAPL',
        companyName: 'Apple Inc.',
        shares: 2.5,
        amountUsd: 500,
        unit: AmountUnit.usd,
        price: 200,
        priceSource: PriceSource.closeOnDate,
        date: DateTime(2026, 10, 5),
      );

      final result = proposal.toToolResult();
      expect(result['status'], 'ok');
      expect(result['proposal_id'], 'p1');
      expect(result['date'], '2026-10-05');
      expect(result['price_source'], 'close_on_date');

      final back = ActionProposal.fromToolResult(result)!;
      expect(back.id, 'p1');
      expect(back.kind, ActionKind.buy);
      expect(back.ticker, 'AAPL');
      expect(back.companyName, 'Apple Inc.');
      expect(back.shares, 2.5);
      expect(back.amountUsd, 500);
      expect(back.unit, AmountUnit.usd);
      expect(back.price, 200);
      expect(back.priceSource, PriceSource.closeOnDate);
      expect(back.date, DateTime(2026, 10, 5));
      expect(back.lots, isEmpty);
    });

    test('a sell keeps its lots in order', () {
      final proposal = ActionProposal(
        id: 'p2',
        kind: ActionKind.sell,
        ticker: 'TSLA',
        shares: 15,
        price: 250,
        priceSource: PriceSource.user,
        date: DateTime(2026, 10, 7),
        heldShares: 20,
        lots: [
          ActionLot(
            id: 'a',
            quantity: 10,
            purchasePrice: 180,
            purchaseDate: DateTime(2025, 1, 2),
          ),
          ActionLot(
            id: 'b',
            quantity: 10,
            purchasePrice: 220,
            purchaseDate: DateTime(2025, 6, 2),
          ),
        ],
      );

      final back = ActionProposal.fromToolResult(proposal.toToolResult())!;
      expect(back.heldShares, 20);
      expect(back.priceSource, PriceSource.user);
      expect(back.lots.map((l) => l.id), ['a', 'b']);
      expect(back.lots.first.purchaseDate, DateTime(2025, 1, 2));
      expect(back.lots.last.purchasePrice, 220);
    });

    test('without a price, the source is missing', () {
      final result =
          const ActionProposal(
            id: 'p3',
            kind: ActionKind.buy,
            ticker: 'NVDA',
            shares: 1,
          ).toToolResult();
      expect(result.containsKey('price'), isFalse);
      expect(
        ActionProposal.fromToolResult(result)!.priceSource,
        PriceSource.missing,
      );
    });

    test('anything that is not a complete ok proposal → null', () {
      for (final result in <Map<String, Object?>>[
        {'status': 'needs_input', 'missing': ['date']},
        {'status': 'ok', 'kind': 'buy', 'ticker': 'AAPL'},
        {'status': 'ok', 'proposal_id': 'x', 'kind': 'swap', 'ticker': 'AAPL'},
        {'status': 'ok', 'proposal_id': 'x', 'kind': 'buy'},
      ]) {
        expect(ActionProposal.fromToolResult(result), isNull, reason: '$result');
      }
    });

    test('a malformed lot is skipped, not the whole proposal', () {
      final back = ActionProposal.fromToolResult({
        'status': 'ok',
        'proposal_id': 'p4',
        'kind': 'delete',
        'ticker': 'VOO',
        'lots': [
          {
            'id': 'a',
            'quantity': 3,
            'purchase_price': 400,
            'purchase_date': '2024-03-22',
          },
          {'id': 'b'},
        ],
      })!;
      expect(back.lots.map((l) => l.id), ['a']);
    });
  });

  group('fifoCostBasis', () {
    final proposal = ActionProposal(
      id: 'p',
      kind: ActionKind.sell,
      ticker: 'TSLA',
      lots: [
        ActionLot(
          id: 'old',
          quantity: 10,
          purchasePrice: 100,
          purchaseDate: DateTime(2025, 1, 2),
        ),
        ActionLot(
          id: 'new',
          quantity: 5,
          purchasePrice: 200,
          purchaseDate: DateTime(2025, 6, 2),
        ),
      ],
    );

    test('sells the oldest purchase first', () {
      expect(proposal.fifoCostBasis(4), 400);
      expect(proposal.fifoCostBasis(12), 1400);
      expect(proposal.fifoCostBasis(15), 2000);
    });

    test('more than the lots, or no lots → null', () {
      expect(proposal.fifoCostBasis(16), isNull);
      expect(
        const ActionProposal(
          id: 'x',
          kind: ActionKind.sell,
          ticker: 'TSLA',
        ).fifoCostBasis(1),
        isNull,
      );
    });
  });

  group('progress', () {
    test('an unknown proposal is pending and can be confirmed', () {
      const state = AssistantState();
      final progress = state.actionProgress('p1');
      expect(progress.status, ActionProposalStatus.pending);
      expect(progress.canConfirm, isTrue);
    });

    test('only pending and failed can be confirmed', () {
      for (final status in ActionProposalStatus.values) {
        expect(
          ActionProposalProgress(status).canConfirm,
          status == ActionProposalStatus.pending ||
              status == ActionProposalStatus.failed,
          reason: status.name,
        );
      }
    });

    test('toBrief: what the model needs to know, without the form', () {
      final progress = ActionProposalProgress(
        ActionProposalStatus.done,
        draft: ActionDraft(
          proposalId: 'p1',
          kind: ActionKind.buy,
          ticker: 'AAPL',
          shares: 4,
          price: 205,
          date: DateTime(2026, 9, 28),
        ),
      );
      expect(progress.toBrief('p1'), {
        'proposal_id': 'p1',
        'status': 'confirmed',
        'kind': 'buy',
        'ticker': 'AAPL',
        'shares': 4.0,
        'price': 205.0,
        'date': '2026-09-28',
      });
      expect(
        const ActionProposalProgress(ActionProposalStatus.saving).toBrief('p2'),
        {'proposal_id': 'p2', 'status': 'saving'},
      );
    });

    test('copyWith keeps the statuses', () {
      final state = const AssistantState().copyWith(
        actionProposals: {
          'p1': const ActionProposalProgress(ActionProposalStatus.done),
        },
      );
      expect(
        state.copyWith(isWaiting: true).actionProgress('p1').status,
        ActionProposalStatus.done,
      );
    });
  });
}
