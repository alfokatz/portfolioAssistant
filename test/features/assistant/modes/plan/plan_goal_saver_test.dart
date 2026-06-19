import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/managers/preferences_manager.dart';
import 'package:portfolio_assistant/features/assistant/modes/plan/plan_goal_saver.dart';

class _FakePreferencesManager implements PreferencesManager {
  ({String label, double targetAmount, String targetDate})? lastSaved;

  @override
  Future<void> saveGoal({
    required String label,
    required double targetAmount,
    required String targetDate,
  }) async {
    lastSaved = (label: label, targetAmount: targetAmount, targetDate: targetDate);
  }

  @override
  Future<({String label, double targetAmount, String targetDate})?> getSavedGoal() async =>
      null;

  @override
  Future<double?> getMonthlyContribution() async => null;

  @override
  Future<void> saveMonthlyContribution(double amount) async {}

  @override
  Future<double?> getRiskProfile() async => null;

  @override
  Future<void> saveRiskProfile(double value) async {}

  @override
  Future<String?> getToken() async => null;

  @override
  Future<void> saveToken({required String token}) async {}

  @override
  bool hasCompletedOnboarding() => false;

  @override
  Future<void> setOnboardingCompleted({required bool completed}) async {}
}

void main() {
  group('PlanGoalSaver', () {
    late _FakePreferencesManager prefs;

    setUp(() {
      prefs = _FakePreferencesManager();
    });

    test('saves goal when save keyword and complete parsed goal', () async {
      await PlanGoalSaver.persistIfRequested(
        prefs: prefs,
        userMessage: 'Guardá mi meta de \$50.000 para 2030',
        snapshot: {
          'has_complete_goal': true,
          'parsed_goal': {
            'label': 'Ahorro',
            'target_amount': 50000.0,
            'target_date': '2030-01-01',
          },
          'active_goal': {
            'label': 'Ahorro',
            'target_amount': 50000.0,
            'target_date': '2030-01-01',
          },
        },
      );

      expect(prefs.lastSaved, isNotNull);
      expect(prefs.lastSaved!.targetAmount, 50000);
      expect(prefs.lastSaved!.targetDate, '2030-01-01');
    });

    test('does not save without save keyword', () async {
      await PlanGoalSaver.persistIfRequested(
        prefs: prefs,
        userMessage: 'Quiero ahorrar \$50.000 para 2030',
        snapshot: {
          'has_complete_goal': true,
          'parsed_goal': {
            'target_amount': 50000.0,
            'target_date': '2030-01-01',
          },
          'active_goal': {
            'target_amount': 50000.0,
            'target_date': '2030-01-01',
          },
        },
      );

      expect(prefs.lastSaved, isNull);
    });

    test('does not save when only saved goal without parsed goal', () async {
      await PlanGoalSaver.persistIfRequested(
        prefs: prefs,
        userMessage: 'Guardar mi meta actual',
        snapshot: {
          'has_complete_goal': true,
          'parsed_goal': null,
          'active_goal': {
            'label': 'Retiro',
            'target_amount': 50000.0,
            'target_date': '2030-01-01',
          },
        },
      );

      expect(prefs.lastSaved, isNull);
    });
  });
}
