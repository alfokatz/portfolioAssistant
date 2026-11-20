import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/investor_profile.dart';

InvestorProfile _profileUpdatedAt(DateTime updatedAt) => InvestorProfile(
      risk: RiskTolerance.moderate,
      horizon: InvestmentHorizon.medium,
      objective: InvestmentObjective.income,
      updatedAt: updatedAt,
    );

void main() {
  group('InvestorProfile.isStaleAt', () {
    final now = DateTime(2026, 9, 26, 10);

    test('fresh profile is not stale', () {
      expect(_profileUpdatedAt(DateTime(2026, 1, 1)).isStaleAt(now), isFalse);
    });

    test('exactly 12 months old is not stale yet', () {
      expect(
        _profileUpdatedAt(DateTime(2025, 9, 26, 10)).isStaleAt(now),
        isFalse,
      );
    });

    test('older than 12 months is stale', () {
      expect(_profileUpdatedAt(DateTime(2025, 9, 25)).isStaleAt(now), isTrue);
    });
  });

  group('storage values', () {
    test('round-trip through fromStorage', () {
      for (final v in RiskTolerance.values) {
        expect(RiskTolerance.fromStorage(v.storageValue), v);
      }
      for (final v in InvestmentHorizon.values) {
        expect(InvestmentHorizon.fromStorage(v.storageValue), v);
      }
      for (final v in InvestmentObjective.values) {
        expect(InvestmentObjective.fromStorage(v.storageValue), v);
      }
    });

    test('unknown value maps to null', () {
      expect(RiskTolerance.fromStorage('yolo'), isNull);
      expect(InvestmentObjective.fromStorage(null), isNull);
    });
  });
}
