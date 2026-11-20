import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/investor_profile.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/supabase/investor_profile_supabase_data_source.dart';

void main() {
  group('InvestorProfileSupabaseDataSource.fromRow', () {
    test('parses a valid row', () {
      final profile = InvestorProfileSupabaseDataSource.fromRow({
        'user_id': 'u1',
        'risk_tolerance': 'aggressive',
        'horizon': 'short',
        'objective': 'specific_goal',
        'updated_at': '2026-09-01T12:00:00+00:00',
      });

      expect(profile, isNotNull);
      expect(profile!.risk, RiskTolerance.aggressive);
      expect(profile.horizon, InvestmentHorizon.short);
      expect(profile.objective, InvestmentObjective.specificGoal);
      expect(profile.updatedAt, DateTime.utc(2026, 9, 1, 12));
    });

    test('unknown enum value is treated as a missing profile', () {
      expect(
        InvestorProfileSupabaseDataSource.fromRow({
          'risk_tolerance': 'reckless',
          'horizon': 'long',
          'objective': 'growth',
          'updated_at': '2026-09-01T12:00:00+00:00',
        }),
        isNull,
      );
    });
  });
}
