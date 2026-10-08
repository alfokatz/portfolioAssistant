import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/catalog/assistant_catalog.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_action_scope.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_evidence_scope.dart';
import 'package:portfolio_assistant/features/assistant/catalog/portfolio_qa_catalog.dart';
import 'package:portfolio_assistant/features/assistant/models/action_proposal.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

import '../../../helpers/genui_test_helpers.dart';

ToolCallRecord _call(String name, ActionProposal proposal) => ToolCallRecord(
  name: name,
  args: const {},
  result: proposal.toToolResult(),
);

final _buy = ActionProposal(
  id: 'buy-1',
  kind: ActionKind.buy,
  ticker: 'AAPL',
  shares: 10,
  price: 210,
  priceSource: PriceSource.closeOnDate,
  date: DateTime(2026, 9, 28),
);

final _sell = ActionProposal(
  id: 'sell-1',
  kind: ActionKind.sell,
  ticker: 'TSLA',
  shares: 12,
  price: 210,
  priceSource: PriceSource.closeOnDate,
  date: DateTime(2026, 9, 28),
  heldShares: 15,
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

final _delete = ActionProposal(
  id: 'del-1',
  kind: ActionKind.delete,
  ticker: 'TSLA',
  shares: 15,
  heldShares: 15,
  lots: _sell.lots,
);

/// Lo que la card le manda a la pantalla.
class _Host {
  final confirmed = <ActionDraft>[];
  final cancelled = <String>[];
  final opened = <String>[];
  final priceRequests = <DateTime>[];
  final forms = <String, ActionForm>{};
  double? nextPrice = 199;

  QaActionScope scope(
    Widget child, {
    Map<String, ActionProposalProgress> proposals = const {},
  }) => QaActionScope(
    proposals: proposals,
    onConfirm: (draft) async => confirmed.add(draft),
    onCancel: (draft) => cancelled.add(draft.proposalId),
    onOpenPosition: opened.add,
    formOf: (id) => forms[id],
    onFormChanged: (id, form) => forms[id] = form,
    priceOn: (ticker, date) async {
      priceRequests.add(date);
      return nextPrice;
    },
    child: child,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required List<ToolCallRecord> calls,
  required String proposalId,
  _Host? host,
  Map<String, ActionProposalProgress> proposals = const {},
}) async {
  final catalog = AssistantCatalog.build();
  await tester.binding.setSurfaceSize(const Size(390, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  Widget body = Scaffold(
    body: SingleChildScrollView(
      child: Builder(
        builder:
            (context) => qaActionProposalItem.widgetBuilder(
              catalogContextFor(
                buildContext: context,
                component: {
                  'id': 'a',
                  'component': 'QaActionProposal',
                  'proposalId': proposalId,
                },
                catalog: catalog,
                surfaceId: 's1',
              ),
            ),
      ),
    ),
  );
  if (host != null) body = host.scope(body, proposals: proposals);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(extensions: const [CustomColors.light]),
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: QaEvidenceScope(
          lookup: (_) => ValueNotifier(TurnEvidence(calls: calls)),
          child: body,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder get _confirm => find.widgetWithText(FilledButton, 'Confirmar');

bool _enabled(WidgetTester tester, Finder button) =>
    tester.widget<FilledButton>(button).onPressed != null;

String _fieldText(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;

void main() {
  group('data from the tool result', () {
    testWidgets('a buy shows what the tool proposed, ready to edit', (
      tester,
    ) async {
      await _pump(
        tester,
        calls: [_call('propose_buy', _buy)],
        proposalId: 'buy-1',
      );
      expect(find.text('REGISTRAR COMPRA'), findsOneWidget);
      expect(find.text('AAPL'), findsOneWidget);
      expect(find.text('28 sep 2026'), findsOneWidget);
      expect(_fieldText(tester, 'qa_action_amount'), '10');
      expect(_fieldText(tester, 'qa_action_price'), '210');
      expect(find.text('\$2,100.00'), findsOneWidget);
    });

    testWidgets('an id that is not among the tool calls draws nothing', (
      tester,
    ) async {
      await _pump(
        tester,
        calls: [_call('propose_buy', _buy)],
        proposalId: 'invented',
      );
      expect(find.text('REGISTRAR COMPRA'), findsNothing);
    });

    testWidgets('a proposal from another tool is ignored', (tester) async {
      await _pump(
        tester,
        calls: [_call('get_quote', _buy)],
        proposalId: 'buy-1',
      );
      expect(find.text('REGISTRAR COMPRA'), findsNothing);
    });

    testWidgets('without the screen scope, Confirm is disabled', (
      tester,
    ) async {
      await _pump(
        tester,
        calls: [_call('propose_buy', _buy)],
        proposalId: 'buy-1',
      );
      expect(_enabled(tester, _confirm), isFalse);
    });
  });

  group('editing', () {
    testWidgets('confirm sends the edited draft', (tester) async {
      final host = _Host();
      await _pump(
        tester,
        calls: [_call('propose_buy', _buy)],
        proposalId: 'buy-1',
        host: host,
      );
      await tester.enterText(find.byKey(const ValueKey('qa_action_amount')), '4');
      await tester.enterText(
        find.byKey(const ValueKey('qa_action_price')),
        '205,5',
      );
      await tester.pump();
      await tester.tap(_confirm);
      await tester.pump();

      final draft = host.confirmed.single;
      expect(draft.proposalId, 'buy-1');
      expect(draft.kind, ActionKind.buy);
      expect(draft.ticker, 'AAPL');
      expect(draft.shares, 4);
      expect(draft.price, 205.5);
      expect(draft.date, DateTime(2026, 9, 28));
    });

    testWidgets('switching to USD converts the amount', (tester) async {
      await _pump(
        tester,
        calls: [_call('propose_buy', _buy)],
        proposalId: 'buy-1',
        host: _Host(),
      );
      await tester.tap(find.text('USD'));
      await tester.pumpAndSettle();
      expect(_fieldText(tester, 'qa_action_amount'), '2100.00');
      expect(find.text('Equivale a 10 acciones'), findsOneWidget);
    });

    testWidgets('a new date fetches that day\'s price', (tester) async {
      final host = _Host();
      await _pump(
        tester,
        calls: [_call('propose_buy', _buy)],
        proposalId: 'buy-1',
        host: host,
      );
      await tester.tap(find.byKey(const ValueKey('qa_action_date')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('25'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(host.priceRequests, [DateTime(2026, 9, 25)]);
      expect(find.text('25 sep 2026'), findsOneWidget);
      expect(_fieldText(tester, 'qa_action_price'), '199');
    });

    testWidgets('a price typed by the user is not replaced by a new date', (
      tester,
    ) async {
      final host = _Host();
      await _pump(
        tester,
        calls: [_call('propose_buy', _buy)],
        proposalId: 'buy-1',
        host: host,
      );
      await tester.enterText(
        find.byKey(const ValueKey('qa_action_price')),
        '180',
      );
      await tester.tap(find.byKey(const ValueKey('qa_action_date')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('25'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(host.priceRequests, isEmpty);
      expect(_fieldText(tester, 'qa_action_price'), '180');
    });

    testWidgets('without a price, Confirm waits for one', (tester) async {
      final noPrice = ActionProposal(
        id: 'buy-2',
        kind: ActionKind.buy,
        ticker: 'AAPL',
        shares: 1,
        date: DateTime(2026, 9, 28),
      );
      await _pump(
        tester,
        calls: [_call('propose_buy', noPrice)],
        proposalId: 'buy-2',
        host: _Host(),
      );
      expect(
        find.text(
          'No encontramos el precio de ese día: completalo para confirmar.',
        ),
        findsOneWidget,
      );
      expect(_enabled(tester, _confirm), isFalse);
      await tester.enterText(
        find.byKey(const ValueKey('qa_action_price')),
        '150',
      );
      await tester.pump();
      expect(_enabled(tester, _confirm), isTrue);
    });

    testWidgets('cancel goes to the screen', (tester) async {
      final host = _Host();
      await _pump(
        tester,
        calls: [_call('propose_buy', _buy)],
        proposalId: 'buy-1',
        host: host,
      );
      await tester.tap(find.text('Cancelar'));
      expect(host.cancelled, ['buy-1']);
    });
  });

  group('edits survive the card being unmounted (scroll)', () {
    testWidgets('amount, unit and a typed price come back', (tester) async {
      final host = _Host();
      Future<void> pumpCard() => _pump(
        tester,
        calls: [_call('propose_buy', _buy)],
        proposalId: 'buy-1',
        host: host,
      );
      await pumpCard();
      await tester.enterText(
        find.byKey(const ValueKey('qa_action_price')),
        '180',
      );
      await tester.tap(find.text('USD'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('qa_action_amount')),
        '900',
      );
      await tester.pump();

      await tester.pumpWidget(const SizedBox());
      await pumpCard();

      expect(_fieldText(tester, 'qa_action_amount'), '900');
      expect(_fieldText(tester, 'qa_action_price'), '180');
      expect(find.text('Equivale a 5 acciones'), findsOneWidget);

      // El precio sigue siendo "del usuario": otra fecha no lo pisa.
      await tester.tap(find.byKey(const ValueKey('qa_action_date')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('25'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(host.priceRequests, isEmpty);
      expect(_fieldText(tester, 'qa_action_price'), '180');
      expect(host.forms['buy-1']!.date, DateTime(2026, 9, 25));
    });

    testWidgets('the purchases picked for a delete come back', (tester) async {
      final host = _Host();
      Future<void> pumpCard() => _pump(
        tester,
        calls: [_call('propose_delete_position', _delete)],
        proposalId: 'del-1',
        host: host,
      );
      await pumpCard();
      await tester.tap(find.byKey(const ValueKey('qa_action_lot_old')));
      await tester.pump();

      await tester.pumpWidget(const SizedBox());
      await pumpCard();

      await tester.tap(find.widgetWithText(FilledButton, 'Confirmar borrado'));
      await tester.pump();
      expect(host.confirmed.single.lotIds, ['old']);
    });
  });

  group('sell', () {
    testWidgets('shows the estimated result with FIFO cost', (tester) async {
      await _pump(
        tester,
        calls: [_call('propose_sell', _sell)],
        proposalId: 'sell-1',
        host: _Host(),
      );
      // 12 a $210 = $2,520; costo FIFO 10×100 + 2×200 = $1,400.
      expect(find.text('\$2,520.00'), findsOneWidget);
      expect(find.text('+\$1,120.00'), findsOneWidget);
      expect(find.text('Tenés 15 acciones'), findsOneWidget);
    });

    testWidgets('more than held blocks Confirm; "Vender todo" fixes it', (
      tester,
    ) async {
      await _pump(
        tester,
        calls: [_call('propose_sell', _sell)],
        proposalId: 'sell-1',
        host: _Host(),
      );
      await tester.enterText(
        find.byKey(const ValueKey('qa_action_amount')),
        '20',
      );
      await tester.pump();
      expect(
        find.text('No podés vender más acciones de las que tenés'),
        findsOneWidget,
      );
      expect(_enabled(tester, _confirm), isFalse);

      await tester.tap(find.text('Vender todo'));
      await tester.pump();
      expect(_fieldText(tester, 'qa_action_amount'), '15');
      expect(_enabled(tester, _confirm), isTrue);
    });
  });

  group('delete', () {
    testWidgets('with several purchases, the user picks which', (
      tester,
    ) async {
      final host = _Host();
      await _pump(
        tester,
        calls: [_call('propose_delete_position', _delete)],
        proposalId: 'del-1',
        host: host,
      );
      final confirm = find.widgetWithText(FilledButton, 'Confirmar borrado');
      expect(find.text('¿Qué compra querés borrar?'), findsOneWidget);
      expect(_enabled(tester, confirm), isFalse);

      await tester.tap(find.byKey(const ValueKey('qa_action_lot_new')));
      await tester.pump();
      await tester.tap(confirm);
      await tester.pump();

      final draft = host.confirmed.single;
      expect(draft.kind, ActionKind.delete);
      expect(draft.lotIds, ['new']);
      expect(draft.shares, 5);
    });
  });

  group('status from the screen', () {
    testWidgets('saved: read-only with what was confirmed, no Confirm', (
      tester,
    ) async {
      final host = _Host();
      await _pump(
        tester,
        calls: [_call('propose_buy', _buy)],
        proposalId: 'buy-1',
        host: host,
        proposals: {
          'buy-1': ActionProposalProgress(
            ActionProposalStatus.done,
            draft: ActionDraft(
              proposalId: 'buy-1',
              kind: ActionKind.buy,
              ticker: 'AAPL',
              shares: 4,
              price: 205,
              date: DateTime(2026, 9, 28),
            ),
          ),
        },
      );
      expect(find.text('Registrada'), findsOneWidget);
      expect(_confirm, findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('\$205.00'), findsOneWidget);
      expect(find.text('\$820.00'), findsOneWidget);

      await tester.tap(find.text('Ver en cartera'));
      expect(host.opened, ['AAPL']);
    });

    testWidgets('saving: fields locked and no Cancel', (tester) async {
      await _pump(
        tester,
        calls: [_call('propose_buy', _buy)],
        proposalId: 'buy-1',
        host: _Host(),
        proposals: {
          'buy-1': const ActionProposalProgress(ActionProposalStatus.saving),
        },
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('qa_action_amount')))
            .enabled,
        isFalse,
      );
      expect(find.text('Cancelar'), findsNothing);
    });

    testWidgets('failed: the error and Retry', (tester) async {
      final host = _Host();
      await _pump(
        tester,
        calls: [_call('propose_buy', _buy)],
        proposalId: 'buy-1',
        host: host,
        proposals: {
          'buy-1': const ActionProposalProgress(
            ActionProposalStatus.failed,
            errorMessage: 'Sin conexión',
          ),
        },
      );
      expect(find.text('Sin conexión'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Reintentar'));
      await tester.pump();
      expect(host.confirmed, hasLength(1));
    });

    testWidgets('cancelled: dimmed, tagged, nothing to confirm', (
      tester,
    ) async {
      await _pump(
        tester,
        calls: [_call('propose_buy', _buy)],
        proposalId: 'buy-1',
        host: _Host(),
        proposals: {
          'buy-1': const ActionProposalProgress(ActionProposalStatus.cancelled),
        },
      );
      expect(find.text('Cancelada'), findsOneWidget);
      expect(_confirm, findsNothing);
      expect(find.text('Ver en cartera'), findsNothing);
    });
  });
}
