import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/investor_profile.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/assistant/services/assistant_openai_service.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_tool_context.dart';
import 'package:portfolio_assistant/features/assistant/tools/portfolio_tools.dart';
import 'package:portfolio_assistant/features/assistant/utils/investor_profile_context.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/supabase/investor_profile_supabase_data_source.dart';

import '../fakes/assistant_fakes.dart';

final _now = DateTime.utc(2026, 10, 7);

InvestorProfile _profile({
  InvestmentExperience? experience,
  DrawdownReaction? drawdown,
  DateTime? updatedAt,
}) => InvestorProfile(
  risk: RiskTolerance.aggressive,
  horizon: InvestmentHorizon.medium,
  objective: InvestmentObjective.growth,
  updatedAt: updatedAt ?? DateTime.utc(2026, 9, 26),
  experience: experience,
  drawdownReaction: drawdown,
);

Map<String, Object?> _brief(InvestorProfile? profile) => PortfolioBrief.build(
  AssistantToolContext(
    tier: SubscriptionTier.free,
    data: fakeDataSources(),
    summary: null,
    investorProfile: profile,
    now: _now,
  ),
);

void main() {
  group('the profile in every turn (PORTFOLIO_BRIEF)', () {
    test('without a profile there is no block and no guidance: Porty '
        'assumes nothing', () {
      final brief = _brief(null);
      expect(brief.containsKey(PortfolioBrief.userProfileKey), isFalse);
      final pinned = AssistantOpenAiService.pinnedContextFor(brief);
      expect(pinned, isNot(contains('user_profile')));
    });

    test('with a profile: the values in Spanish, the optional ones only if '
        'answered', () {
      final basic = _brief(_profile())[PortfolioBrief.userProfileKey]! as Map;
      expect(basic['risk_tolerance'], 'agresivo');
      expect(basic.containsKey('experience'), isFalse);
      expect(basic.containsKey('stale'), isFalse);

      final full =
          _brief(
                _profile(
                  experience: InvestmentExperience.beginner,
                  drawdown: DrawdownReaction.sell,
                ),
              )[PortfolioBrief.userProfileKey]!
              as Map;
      expect(full['experience'], 'principiante');
      expect(full['drawdown_reaction'], 'vendería para no perder más');
    });

    test('an old profile is flagged stale', () {
      final stale =
          _brief(_profile(updatedAt: DateTime.utc(2025, 1, 1)))[
                PortfolioBrief.userProfileKey]!
              as Map;
      expect(stale['stale'], isTrue);
    });

    test('the guidance (only use it when it changes the answer) goes '
        'BEFORE the JSON, which still parses from the first "{" (the company '
        'analysis reads the position that way)', () {
      final brief = _brief(_profile());
      final pinned = AssistantOpenAiService.pinnedContextFor(brief);
      expect(pinned, contains(AssistantOpenAiService.userProfileGuidance));
      expect(AssistantOpenAiService.userProfileGuidance, isNot(contains('{')));
      final json = jsonDecode(pinned.substring(pinned.indexOf('{')));
      expect(json, jsonDecode(jsonEncode(brief)));
    });
  });

  test('the Invest/Goal tool block also carries the optional answers', () {
    final block = InvestorProfileContext.build(
      _profile(experience: InvestmentExperience.advanced),
      _now,
    );
    expect(block['status'], InvestorProfileContext.statusComplete);
    expect(block['experience'], 'avanzada');
  });

  group('stored row', () {
    final base = {
      'risk_tolerance': 'moderate',
      'horizon': 'long',
      'objective': 'income',
      'updated_at': '2026-10-07T12:00:00+00:00',
    };

    test('reads the optional answers', () {
      final p =
          InvestorProfileSupabaseDataSource.fromRow({
            ...base,
            'experience': 'intermediate',
            'drawdown_reaction': 'buy_more',
          })!;
      expect(p.experience, InvestmentExperience.intermediate);
      expect(p.drawdownReaction, DrawdownReaction.buyMore);
    });

    test('without them (old profile, or the migration not applied yet) the '
        'profile is still valid', () {
      final p = InvestorProfileSupabaseDataSource.fromRow(base)!;
      expect(p.experience, isNull);
      expect(p.drawdownReaction, isNull);
    });
  });
}
