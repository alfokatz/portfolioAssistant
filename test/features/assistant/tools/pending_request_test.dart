import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_tool_context.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_toolset.dart';
import 'package:portfolio_assistant/features/assistant/tools/portfolio_tools.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';

import '../fakes/assistant_fakes.dart';

ToolCallRecord _call(
  String name,
  String status, {
  Map<String, Object?>? args,
}) => ToolCallRecord(
  name: name,
  args: args ?? const {},
  result: {
    'status': status,
    if (status == 'needs_input') 'missing': ['ticker'],
  },
);

void main() {
  test('an action left waiting for data becomes the pending request', () {
    final pending = AssistantTurnPolicy.pendingRequest(
      TurnOutcome([
        _call('get_watchlist', 'ok'),
        _call('propose_watch', 'needs_input', args: {'action': 'follow'}),
      ]),
    );
    expect(pending, {
      'tool': 'propose_watch',
      'args': {'action': 'follow'},
      'missing': ['ticker'],
    });
  });

  test('nothing pending after a ready proposal or a read-only turn', () {
    expect(
      AssistantTurnPolicy.pendingRequest(
        TurnOutcome([
          _call('propose_watch', 'needs_input'),
          _call('propose_watch', 'ok'),
        ]),
      ),
      isNull,
    );
    expect(
      AssistantTurnPolicy.pendingRequest(
        TurnOutcome([_call('get_quote', 'needs_input')]),
      ),
      isNull,
    );
  });

  test('the pending request travels in the next turn brief', () {
    final brief = PortfolioBrief.build(
      AssistantToolContext(
        tier: SubscriptionTier.premium,
        data: fakeDataSources(),
        pendingRequest: const {
          'tool': 'propose_watch',
          'missing': ['ticker'],
        },
      ),
    );
    expect(
      (brief[PortfolioBrief.pendingRequestKey]! as Map)['tool'],
      'propose_watch',
    );
  });
}
