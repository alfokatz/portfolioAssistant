import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';
import 'package:portfolio_assistant/features/assistant/models/portfolio_qa_message.dart';
import 'package:portfolio_assistant/features/assistant/providers/assistant_provider.dart';
import 'package:portfolio_assistant/features/assistant/states/assistant_state.dart';
import 'package:portfolio_assistant/features/assistant/unified/unified_assistant_flag.dart';
import 'package:portfolio_assistant/features/genui_core/genui_surface_ids.dart';

void main() {
  tearDown(() => UnifiedAssistantFlag.debugOverride = null);

  test('the unified pipeline is OFF by default (mode pipeline untouched)', () {
    expect(UnifiedAssistantFlag.enabled, isFalse);
    UnifiedAssistantFlag.debugOverride = true;
    expect(UnifiedAssistantFlag.enabled, isTrue);
  });

  test('unified surface ids carry no mode', () {
    final id = GenUiSurfaceIds.assistantUnifiedTurn(3);
    expect(id, 'assistant_unified_3');
    for (final mode in AssistantMode.values) {
      expect(id, isNot(contains(mode.name)));
    }
  });

  group('serviceForMessage', () {
    AssistantProvider notifier() {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      return container.read(assistantProvider(const AssistantArgs()).notifier);
    }

    test(
      'a unified message with no unified service yet resolves to null (screen falls back)',
      () {
        final message = PortfolioQaMessage(
          role: PortfolioQaRole.assistant,
          surfaceId: GenUiSurfaceIds.assistantUnifiedTurn(0),
        );
        expect(notifier().serviceForMessage(message), isNull);
      },
    );

    test(
      'a mode message resolves through its mode (null until that service exists)',
      () {
        const message = PortfolioQaMessage(
          role: PortfolioQaRole.assistant,
          surfaceId: 'assistant_explore_0',
          engineMode: AssistantMode.explore,
        );
        expect(notifier().serviceForMessage(message), isNull);
      },
    );
  });
}
