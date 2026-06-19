abstract class PreferencesManager {
  Future<void> saveToken({required String token});

  Future<String?> getToken();

  Future<double?> getRiskProfile();

  Future<void> saveRiskProfile(double value);

  Future<void> saveGoal({
    required String label,
    required double targetAmount,
    required String targetDate,
  });

  Future<({String label, double targetAmount, String targetDate})?> getSavedGoal();

  Future<void> saveMonthlyContribution(double amount);

  Future<double?> getMonthlyContribution();

  bool hasCompletedOnboarding();

  Future<void> setOnboardingCompleted({required bool completed});
}
