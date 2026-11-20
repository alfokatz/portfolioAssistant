import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_tool_context.dart';
import 'package:portfolio_assistant/features/assistant/tools/portfolio_tools.dart';
import 'package:portfolio_assistant/features/assistant/utils/assistant_answer_review.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';

import '../fakes/assistant_fakes.dart';

String _answer(String text) =>
    '{"version":"v0.9","updateComponents":{"surfaceId":"s","components":['
    '{"id":"root","component":"Column","children":["a"]},'
    '{"id":"a","component":"QaAnswerText","text":"$text"}]}}';

void main() {
  test('"voy a revisar…" without calling anything → call the tool now', () {
    final fix = AssistantAnswerReview.check(
      _answer(
        'Voy a revisar los detalles de tu plan para ver cuántas te quedan.',
      ),
      TurnEvidence.empty,
    );
    expect(fix, isNotNull);
    expect(fix!.requiresTools, isTrue);
  });

  test('the same words after a tool call, or a normal answer, pass', () {
    const call = ToolCallRecord(
      name: 'get_app_settings',
      args: {},
      result: {'status': 'ok'},
    );
    expect(
      AssistantAnswerReview.check(
        _answer('Voy a ver: te quedan 380.'),
        const TurnEvidence(calls: [call], turnCalls: [call]),
      ),
      isNull,
    );
    expect(
      AssistantAnswerReview.check(_answer('¡De nada!'), TurnEvidence.empty),
      isNull,
    );
  });

  test('the brief carries the plan and the queries left', () {
    final brief = PortfolioBrief.build(
      AssistantToolContext(
        tier: SubscriptionTier.premium,
        data: fakeDataSources(),
        queriesLeftThisMonth: 380,
      ),
    );
    expect(brief[PortfolioBrief.accountKey], {
      'plan': 'premium',
      'queries_left_this_month': 380,
    });
  });
}
