import 'package:portfolio_assistant/domain/managers/preferences_manager.dart';

/// Persiste metas de planificación cuando el usuario lo solicita explícitamente.
abstract final class PlanGoalSaver {
  static const _saveKeywords = [
    'guardar',
    'guardá',
    'save',
    'recordar meta',
  ];

  /// If snapshot has complete active_goal from parsed message, save to preferences
  static Future<void> persistIfRequested({
    required PreferencesManager prefs,
    required Map<String, dynamic> snapshot,
    required String userMessage,
  }) async {
    if (!_wantsSave(userMessage)) return;
    if (snapshot['has_complete_goal'] != true) return;

    final parsedGoal = snapshot['parsed_goal'] as Map<String, dynamic>?;
    if (!_isCompleteParsedGoal(parsedGoal)) return;

    final activeGoal = snapshot['active_goal'] as Map<String, dynamic>?;
    if (activeGoal == null) return;

    final label =
        activeGoal['label'] as String? ??
        parsedGoal!['label'] as String? ??
        'Meta';
    final targetAmount = activeGoal['target_amount'] as double?;
    final targetDate = activeGoal['target_date'] as String?;
    if (targetAmount == null || targetDate == null) return;

    await prefs.saveGoal(
      label: label,
      targetAmount: targetAmount,
      targetDate: targetDate,
    );
  }

  static bool _wantsSave(String message) {
    final lower = message.toLowerCase();
    return _saveKeywords.any(lower.contains);
  }

  static bool _isCompleteParsedGoal(Map<String, dynamic>? parsed) {
    if (parsed == null) return false;
    return parsed['target_amount'] != null && parsed['target_date'] != null;
  }
}
