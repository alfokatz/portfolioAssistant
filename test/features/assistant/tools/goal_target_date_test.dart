import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/tools/advice_tools.dart';

/// "En 14 meses" lo calcula la app, no el modelo (bug 2026-11-05: el
/// modelo daba enero de 2027 en noviembre de 2026, o sea 2 meses).
void main() {
  final now = DateTime(2026, 11, 5);
  DateTime? of(Map<String, Object?> args) =>
      GetGoalProjectionTool.targetDateOf(args, now);

  test('months_from_now crosses the year correctly', () {
    expect(of({'months_from_now': 14}), DateTime(2028, 1, 5));
    expect(of({'months_from_now': 24}), DateTime(2028, 11, 5));
    expect(of({'months_from_now': 2}), DateTime(2027, 1, 5));
  });

  test('a day past the end of the target month is clamped', () {
    expect(
      GetGoalProjectionTool.targetDateOf(
        {'months_from_now': 1},
        DateTime(2027, 1, 31),
      ),
      DateTime(2027, 2, 28),
    );
  });

  test('months_from_now wins over a wrong target_date; absolute dates work',
      () {
    expect(
      of({'months_from_now': 14, 'target_date': '2027-01-05'}),
      DateTime(2028, 1, 5),
    );
    expect(of({'target_date': '2030-03-01'}), DateTime(2030, 3, 1));
    expect(of({}), isNull);
    expect(of({'months_from_now': 0}), isNull);
  });
}
