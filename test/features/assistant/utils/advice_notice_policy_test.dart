import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';
import 'package:portfolio_assistant/features/assistant/models/portfolio_qa_message.dart';
import 'package:portfolio_assistant/features/assistant/utils/advice_notice_policy.dart';

Map<String, dynamic> _investSnapshot(String status) => {
      'mode': 'invest',
      'investor_profile': {'status': status},
    };

void main() {
  group('AdviceNoticePolicy.showsDisclaimer', () {
    test('always on Invest, with or without profile', () {
      expect(
        AdviceNoticePolicy.showsDisclaimer(
          AssistantMode.invest,
          _investSnapshot('missing'),
        ),
        isTrue,
      );
      expect(
        AdviceNoticePolicy.showsDisclaimer(
          AssistantMode.invest,
          _investSnapshot('complete'),
        ),
        isTrue,
      );
    });

    test('on Plan only when there is a complete goal (a projection)', () {
      expect(
        AdviceNoticePolicy.showsDisclaimer(
          AssistantMode.plan,
          {'has_complete_goal': true},
        ),
        isTrue,
      );
      expect(
        AdviceNoticePolicy.showsDisclaimer(
          AssistantMode.plan,
          {'has_complete_goal': false},
        ),
        isFalse,
      );
    });

    test('never on the other engines', () {
      for (final mode in [
        AssistantMode.portfolio,
        AssistantMode.learn,
        AssistantMode.explore,
      ]) {
        expect(AdviceNoticePolicy.showsDisclaimer(mode, const {}), isFalse);
      }
    });
  });

  group('AdviceNoticePolicy.profileNudge', () {
    test('missing and stale profiles nudge on Invest', () {
      expect(
        AdviceNoticePolicy.profileNudge(
          AssistantMode.invest,
          _investSnapshot('missing'),
          alreadyShown: false,
        ),
        InvestorProfileNudge.missing,
      );
      expect(
        AdviceNoticePolicy.profileNudge(
          AssistantMode.invest,
          _investSnapshot('stale'),
          alreadyShown: false,
        ),
        InvestorProfileNudge.stale,
      );
    });

    test('complete profile does not nudge', () {
      expect(
        AdviceNoticePolicy.profileNudge(
          AssistantMode.invest,
          _investSnapshot('complete'),
          alreadyShown: false,
        ),
        isNull,
      );
    });

    test('only once per conversation', () {
      expect(
        AdviceNoticePolicy.profileNudge(
          AssistantMode.invest,
          _investSnapshot('missing'),
          alreadyShown: true,
        ),
        isNull,
      );
    });

    test('never on Plan', () {
      expect(
        AdviceNoticePolicy.profileNudge(
          AssistantMode.plan,
          {'investor_profile': {'status': 'missing'}},
          alreadyShown: false,
        ),
        isNull,
      );
    });
  });
}
