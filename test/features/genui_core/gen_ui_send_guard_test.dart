import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_send_guard.dart';

void main() {
  group('GenUiSendGuard', () {
    test('tryAcquire is exclusive: a second concurrent call is rejected', () {
      final guard = GenUiSendGuard();

      expect(guard.tryAcquire(), isTrue);
      expect(guard.isInFlight, isTrue);

      // Simulates a second send racing in while the first is still running
      // (e.g. a double-tap on a chip/button before the UI rebuilds to
      // disable it).
      expect(guard.tryAcquire(), isFalse);
      expect(guard.isInFlight, isTrue);
    });

    test('release frees the lock for the next send', () {
      final guard = GenUiSendGuard();
      guard.tryAcquire();

      guard.release();

      expect(guard.isInFlight, isFalse);
      expect(guard.tryAcquire(), isTrue);
    });
  });
}
