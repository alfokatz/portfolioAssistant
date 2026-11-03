import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/utils/assistant_grounding_check.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';

String _answer(List<Map<String, Object?>> widgets) =>
    '```json\n${jsonEncode({
      'version': 'v0.9',
      'createSurface': {'surfaceId': 's', 'catalogId': 'x'},
    })}\n```\n```json\n${jsonEncode({
      'version': 'v0.9',
      'updateComponents': {
        'surfaceId': 's',
        'components': [
          {'id': 'root', 'component': 'Column', 'children': []},
          {'id': 'a', 'component': 'QaAnswerText', 'text': 'x'},
          ...widgets,
        ],
      },
    })}\n```';

ToolCallRecord _call(
  String name,
  List<String> tickers, [
  String status = 'ok',
]) => ToolCallRecord(
  name: name,
  args: {'tickers': tickers},
  result: {'status': status},
);

void main() {
  test('rejects fundamentals shown without get_fundamentals (numbers from '
      'memory)', () {
    final correction = AssistantGroundingCheck.check(
      _answer([
        {'id': 'f', 'component': 'QaFundamentals', 'ticker': 'AAPL'},
      ]),
      const [],
    );
    expect(
      correction,
      contains('QaFundamentals (AAPL) needs get_fundamentals'),
    );
  });

  test('an action card needs the ok proposal with that exact id', () {
    final widget = [
      {'id': 'p', 'component': 'QaActionProposal', 'proposalId': 'p-1'},
    ];
    ToolCallRecord proposal(String id, [String status = 'ok']) =>
        ToolCallRecord(
          name: 'propose_buy',
          args: const {'ticker': 'AAPL'},
          result: {'status': status, 'proposal_id': id},
        );

    expect(
      AssistantGroundingCheck.check(_answer(widget), const []),
      contains('QaActionProposal needs propose_buy'),
    );
    expect(
      AssistantGroundingCheck.check(_answer(widget), [proposal('p-2')]),
      isNotNull,
      reason: 'an invented id',
    );
    expect(
      AssistantGroundingCheck.check(_answer(widget), [
        proposal('p-1', 'needs_input'),
      ]),
      isNotNull,
    );
    expect(
      AssistantGroundingCheck.check(_answer(widget), [proposal('p-1')]),
      isNull,
    );
  });

  test('ETF holdings need an ok get_etf_holdings for that ticker', () {
    final widget = [
      {'id': 'h', 'component': 'QaEtfHoldings', 'ticker': 'XLF'},
    ];
    expect(
      AssistantGroundingCheck.check(_answer(widget), const []),
      contains('QaEtfHoldings (XLF) needs get_etf_holdings'),
    );
    expect(
      AssistantGroundingCheck.check(_answer(widget), [
        _call('get_etf_holdings', ['VOO']),
      ]),
      isNotNull,
    );
    expect(
      AssistantGroundingCheck.check(_answer(widget), [
        _call('get_etf_holdings', ['XLF']),
      ]),
      isNull,
    );
  });

  test('the backing result must be ok and for the same ticker', () {
    final widget = [
      {'id': 'c', 'component': 'QaPriceChart', 'ticker': 'MSFT'},
    ];
    expect(
      AssistantGroundingCheck.check(_answer(widget), [
        _call('get_quote', ['AAPL']),
      ]),
      isNotNull,
    );
    expect(
      AssistantGroundingCheck.check(_answer(widget), [
        _call('get_quote', ['MSFT'], 'locked'),
      ]),
      isNotNull,
    );
    expect(
      AssistantGroundingCheck.check(_answer(widget), [
        _call('get_quote', ['msft']),
      ]),
      isNull,
    );
  });

  test('a ticker the plan left locked inside an ok call does not back a card '
      '(mixed call: one held, one foreign without free lookups)', () {
    final widget = [
      {'id': 'c', 'component': 'QaPriceChart', 'ticker': 'AMZN'},
    ];
    final mixedQuote = ToolCallRecord(
      name: 'get_quote',
      args: const {
        'tickers': ['AAPL', 'AMZN'],
      },
      result: const {
        'status': 'ok',
        'tickers': {
          'AAPL': {'status': 'ok', 'fetch_ok': true},
          'AMZN': {'status': 'locked'},
        },
      },
    );
    expect(AssistantGroundingCheck.check(_answer(widget), [mixedQuote]),
        contains('QaPriceChart (AMZN)'));
    expect(
      AssistantGroundingCheck.check(
        _answer([
          {'id': 'c', 'component': 'QaPriceChart', 'ticker': 'AAPL'},
        ]),
        [mixedQuote],
      ),
      isNull,
    );

    final mixedEtf = ToolCallRecord(
      name: 'get_etf_holdings',
      args: const {
        'tickers': ['VOO', 'XLF'],
      },
      result: const {
        'status': 'ok',
        'locked_tickers': ['XLF'],
      },
    );
    expect(
      AssistantGroundingCheck.check(
        _answer([
          {'id': 'e', 'component': 'QaEtfHoldings', 'ticker': 'XLF'},
        ]),
        [mixedEtf],
      ),
      isNotNull,
    );
  });

  test('portfolio widgets and plain text answers need no tool', () {
    expect(
      AssistantGroundingCheck.check(
        _answer([
          {'id': 'p', 'component': 'QaPositionsSnapshot'},
        ]),
        const [],
      ),
      isNull,
    );
    expect(AssistantGroundingCheck.check(_answer([]), const []), isNull);
    expect(AssistantGroundingCheck.check('texto sin json', const []), isNull);
  });

  test(
    'detects widgets in pretty-printed JSON, the way the model writes it',
    () {
      const encoder = JsonEncoder.withIndent('  ');
      final raw =
          '```json\n${encoder.convert({
            'version': 'v0.9',
            'updateComponents': {
              'surfaceId': 's',
              'components': [
                {
                  'id': 'root',
                  'component': 'Column',
                  'children': ['f'],
                },
                {'id': 'f', 'component': 'QaFundamentals', 'ticker': 'AAPL'},
              ],
            },
          })}\n```';
      expect(AssistantGroundingCheck.check(raw, const []), isNotNull);
    },
  );
}
