import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_send_guard.dart';

void main() {
  group('GenUiSendGuard', () {
    test('blocks concurrent runs until the first completes', () async {
      final guard = GenUiSendGuard();
      var firstStarted = false;
      var secondRan = false;

      final first = guard.run(() async {
        firstStarted = true;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });

      expect(guard.isInFlight, isTrue);

      await guard.run(() async {
        secondRan = true;
      });

      await first;

      expect(firstStarted, isTrue);
      expect(secondRan, isFalse);
      expect(guard.isInFlight, isFalse);
    });

    test('allows a new run after the previous one finishes', () async {
      final guard = GenUiSendGuard();
      var runCount = 0;

      await guard.run(() async {
        runCount++;
      });
      await guard.run(() async {
        runCount++;
      });

      expect(runCount, 2);
      expect(guard.isInFlight, isFalse);
    });
  });
}
