import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/services/quota_nudge_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Memoria de la línea de cuota baja: una vez por mes UTC y por usuario.
// Correr: flutter test test/features/assistant/services/quota_nudge_memory_test.dart
void main() {
  Future<SharedPreferences> prefs([Map<String, Object> initial = const {}]) {
    SharedPreferences.setMockInitialValues(initial);
    return SharedPreferences.getInstance();
  }

  group('QuotaNudgeMemory', () {
    test('entry is "<userId>:YYYY-MM" in UTC, not local time', () {
      // 31/10 23:30 en UTC-3 ya es 1/11 02:30 UTC.
      final late = DateTime.parse('2026-10-31T23:30:00-03:00');
      expect(QuotaNudgeMemory.entryFor('u1', late), 'u1:2026-11');
      expect(
        QuotaNudgeMemory.entryFor('u1', DateTime.utc(2026, 1, 5)),
        'u1:2026-01',
      );
    });

    test('marks the month for that user only', () async {
      final memory = QuotaNudgeMemory(await prefs());
      final now = DateTime.utc(2026, 11, 10);

      expect(memory.wasShown('u1', now), isFalse);
      await memory.markShown('u1', now);

      expect(memory.wasShown('u1', now), isTrue);
      expect(memory.wasShown('u2', now), isFalse);
      expect(memory.wasShown('u1', DateTime.utc(2026, 12, 1)), isFalse);
    });

    test('persists in SharedPreferences and survives a new instance',
        () async {
      final p = await prefs();
      await QuotaNudgeMemory(p).markShown('u1', DateTime.utc(2026, 11, 10));

      expect(p.getStringList(QuotaNudgeMemory.prefsKey), ['u1:2026-11']);
      expect(
        QuotaNudgeMemory(p).wasShown('u1', DateTime.utc(2026, 11, 30)),
        isTrue,
      );
    });

    test('keeps other users of the month and drops past months', () async {
      final p = await prefs({
        QuotaNudgeMemory.prefsKey: ['u2:2026-11', 'u1:2026-10'],
      });
      await QuotaNudgeMemory(p).markShown('u1', DateTime.utc(2026, 11, 10));

      expect(
        p.getStringList(QuotaNudgeMemory.prefsKey),
        unorderedEquals(['u2:2026-11', 'u1:2026-11']),
      );
    });

    test('without SharedPreferences it still remembers in memory', () async {
      final memory = QuotaNudgeMemory();
      final now = DateTime.utc(2026, 11, 10);

      await memory.markShown('u1', now);

      expect(memory.wasShown('u1', now), isTrue);
    });
  });
}
