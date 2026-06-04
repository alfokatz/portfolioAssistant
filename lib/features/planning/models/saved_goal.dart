/// Meta financiera persistida localmente.
class SavedGoal {
  const SavedGoal({
    required this.label,
    required this.targetAmount,
    required this.targetDate,
  });

  final String label;
  final double targetAmount;
  final String targetDate;

  Map<String, dynamic> toJson() => {
        'label': label,
        'targetAmount': targetAmount,
        'targetDate': targetDate,
      };

  factory SavedGoal.fromJson(Map<String, dynamic> json) {
    return SavedGoal(
      label: json['label'] as String? ?? 'Meta financiera',
      targetAmount: (json['targetAmount'] as num?)?.toDouble() ?? 0,
      targetDate: json['targetDate'] as String? ?? '',
    );
  }
}
