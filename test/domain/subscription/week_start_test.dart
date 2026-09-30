import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/repositories/weekly_free_analysis_repository.dart';
import 'package:portfolio_assistant/domain/subscription/week_start.dart';
import 'package:portfolio_assistant/features/subscription/providers/weekly_free_analysis_provider.dart';

class _Repo implements WeeklyFreeAnalysisRepository {
  final used = <String>{};
  @override
  Future<bool> isAvailable(String weekStart) async => !used.contains(weekStart);
  @override
  Future<bool> consume(String weekStart, {String? ticker}) async =>
      used.add(weekStart);
}

void main() {
  test('weeks run Monday to Sunday in local time', () {
    expect(weekStartKey(DateTime(2026, 9, 30, 10)), '2026-09-28'); // miércoles
    expect(weekStartKey(DateTime(2026, 10, 4, 23, 59)), '2026-09-28'); // domingo
    expect(weekStartKey(DateTime(2026, 10, 5, 0, 1)), '2026-10-05'); // lunes
  });

  test('used → locked for the rest of the week; a new week re-enables it',
      () async {
    var now = DateTime(2026, 9, 30, 10);
    final repo = _Repo();
    final notifier = WeeklyFreeAnalysisNotifier(repo, clock: () => now);
    await notifier.refresh(eligible: true);
    expect(notifier.state, isTrue);

    expect(await notifier.consume('BAC'), isTrue);
    expect(notifier.state, isFalse);
    await notifier.refresh(eligible: true);
    expect(notifier.state, isFalse, reason: 'misma semana');

    now = DateTime(2026, 10, 5, 9); // lunes siguiente
    await notifier.refreshIfNewWeek(eligible: true);
    expect(notifier.state, isTrue);
  });

  test('not eligible (Gold) → never offered', () async {
    final notifier = WeeklyFreeAnalysisNotifier(_Repo());
    await notifier.refresh(eligible: false);
    expect(notifier.state, isFalse);
  });
}
