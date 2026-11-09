import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/broker_connect/domain/sync_due.dart';

void main() {
  final now = DateTime(2026, 11, 9, 12);
  const staleAfter = Duration(minutes: 30);

  test('never synced: due', () {
    expect(isSyncDue(null, staleAfter: staleAfter, now: now), isTrue);
  });

  test('fresher than staleAfter: not due', () {
    final last = now.subtract(const Duration(minutes: 29));
    expect(isSyncDue(last, staleAfter: staleAfter, now: now), isFalse);
  });

  test('exactly staleAfter or older: due', () {
    expect(
      isSyncDue(now.subtract(staleAfter), staleAfter: staleAfter, now: now),
      isTrue,
    );
    expect(
      isSyncDue(
        now.subtract(const Duration(hours: 2)),
        staleAfter: staleAfter,
        now: now,
      ),
      isTrue,
    );
  });
}
