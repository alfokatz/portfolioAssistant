import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/providers/assistant_provider.dart';
import 'package:portfolio_assistant/features/assistant/states/assistant_state.dart';

// Regresión: al scrollear el historial de chat, los items del ListView (ver
// AssistantScreen) se desmontan y remontan, perdiendo cualquier estado local
// de "ya se revelé" — por eso ese flag ahora vive acá, en el provider (ver
// PortfolioQaMessage.hasRevealed / AssistantState.introRevealed), no en el
// State de ningún widget. Estos tests cubren la mutación de estado en sí,
// aislada de los widgets que la consumen (ya cubiertos en
// assistant_loading_animations_test.dart y fade_slide_in_test.dart).
void main() {
  ProviderContainer buildContainer() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  AssistantProvider buildNotifier(ProviderContainer container) {
    return container.read(assistantProvider(const AssistantArgs()).notifier);
  }

  group('markUserMessageRevealed', () {
    test('marks the message at the given index as revealed, once', () {
      final notifier = buildNotifier(buildContainer());
      expect(notifier.state.messages[0].hasRevealed, isFalse);

      notifier.markUserMessageRevealed(0);

      expect(notifier.state.messages[0].hasRevealed, isTrue);
    });

    test('is idempotent — a second call does not rebuild the list', () {
      final notifier = buildNotifier(buildContainer());
      notifier.markUserMessageRevealed(0);
      final afterFirst = notifier.state;

      notifier.markUserMessageRevealed(0);

      expect(identical(notifier.state, afterFirst), isTrue);
    });

    test('is a no-op for an out-of-range index', () {
      final notifier = buildNotifier(buildContainer());
      final before = notifier.state;

      notifier.markUserMessageRevealed(99);
      notifier.markUserMessageRevealed(-1);

      expect(identical(notifier.state, before), isTrue);
    });
  });

  group('markRevealed', () {
    test('is a no-op when no message has that surfaceId', () {
      final notifier = buildNotifier(buildContainer());
      final before = notifier.state;

      notifier.markRevealed('does_not_exist');

      expect(identical(notifier.state, before), isTrue);
    });
  });

  group('markIntroRevealed', () {
    test('flips introRevealed to true', () {
      final notifier = buildNotifier(buildContainer());
      expect(notifier.state.introRevealed, isFalse);

      notifier.markIntroRevealed();

      expect(notifier.state.introRevealed, isTrue);
    });

    test('is idempotent — a second call does not rebuild the state', () {
      final notifier = buildNotifier(buildContainer());
      notifier.markIntroRevealed();
      final afterFirst = notifier.state;

      notifier.markIntroRevealed();

      expect(identical(notifier.state, afterFirst), isTrue);
    });
  });
}
