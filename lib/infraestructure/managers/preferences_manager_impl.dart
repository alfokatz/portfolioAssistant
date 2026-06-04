import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:portfolio_assistant/domain/managers/preferences_manager.dart';

const _KEY_USER_TOKEN = 'KEY_USER_TOKEN';
const _KEY_USER_RISK_PROFILE = 'user_risk_profile';
const _KEY_GOAL_LABEL = 'goal_label';
const _KEY_GOAL_TARGET_AMOUNT = 'goal_target_amount';
const _KEY_GOAL_TARGET_DATE = 'goal_target_date';
const _KEY_MONTHLY_CONTRIBUTION = 'user_monthly_contribution';

class PreferencesManagerImpl extends PreferencesManager {
  final SharedPreferences sharedPreferences;
  final FlutterSecureStorage secureStorage;

  PreferencesManagerImpl({
    required this.sharedPreferences,
    required this.secureStorage,
  });

  @override
  Future<void> saveToken({required String token}) async {
    await secureStorage.write(
      key: _KEY_USER_TOKEN,
      value: token,
      aOptions: AndroidOptions(),
    );
  }

  @override
  Future<String?> getToken() async {
    final String? token = await secureStorage.read(key: _KEY_USER_TOKEN);
    return token;
  }

  @override
  Future<double?> getRiskProfile() async {
    return sharedPreferences.getDouble(_KEY_USER_RISK_PROFILE);
  }

  @override
  Future<void> saveRiskProfile(double value) async {
    await sharedPreferences.setDouble(_KEY_USER_RISK_PROFILE, value);
  }

  @override
  Future<void> saveGoal({
    required String label,
    required double targetAmount,
    required String targetDate,
  }) async {
    await sharedPreferences.setString(_KEY_GOAL_LABEL, label);
    await sharedPreferences.setDouble(_KEY_GOAL_TARGET_AMOUNT, targetAmount);
    await sharedPreferences.setString(_KEY_GOAL_TARGET_DATE, targetDate);
  }

  @override
  Future<({String label, double targetAmount, String targetDate})?>
      getSavedGoal() async {
    final label = sharedPreferences.getString(_KEY_GOAL_LABEL);
    final amount = sharedPreferences.getDouble(_KEY_GOAL_TARGET_AMOUNT);
    final date = sharedPreferences.getString(_KEY_GOAL_TARGET_DATE);
    if (label == null || amount == null || date == null) return null;
    return (label: label, targetAmount: amount, targetDate: date);
  }

  @override
  Future<void> saveMonthlyContribution(double amount) async {
    await sharedPreferences.setDouble(_KEY_MONTHLY_CONTRIBUTION, amount);
  }

  @override
  Future<double?> getMonthlyContribution() async {
    return sharedPreferences.getDouble(_KEY_MONTHLY_CONTRIBUTION);
  }
}

final sharedPreferencesProvider = Provider<SharedPreferences>(
  ((ref) => throw UnimplementedError()),
);

final secureStorageProvider = Provider<FlutterSecureStorage>(
  ((ref) => throw UnimplementedError()),
);

final preferenceManagerProvider = Provider<PreferencesManager>(
  (ref) => PreferencesManagerImpl(
    sharedPreferences: ref.watch(sharedPreferencesProvider),
    secureStorage: ref.watch(secureStorageProvider),
  ),
);
