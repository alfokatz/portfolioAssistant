import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';
import 'package:portfolio_assistant/features/assistant/models/portfolio_qa_message.dart';
import 'package:portfolio_assistant/features/assistant/utils/assistant_message_sync.dart';
import 'package:portfolio_assistant/features/genui_core/utils/llm_json_sanitizer.dart';

void main() {
  group('AssistantMessageSync.applyFallback', () {
    test(
      'replaces the streaming placeholder with fallback text, keeping the '
      'surfaceId (marked isFallback) instead of discarding it',
      () {
        final messages = [
          const PortfolioQaMessage(role: PortfolioQaRole.user, content: 'hola'),
          const PortfolioQaMessage(
            role: PortfolioQaRole.assistant,
            surfaceId: 'assistant_invest_2',
            isStreaming: true,
            engineMode: AssistantMode.invest,
          ),
        ];

        final updated = AssistantMessageSync.applyFallback(
          messages,
          'assistant_invest_2',
          AssistantMode.invest,
        );

        final message = updated.last;
        expect(message.isStreaming, isFalse);
        expect(message.isFallback, isTrue);
        expect(message.content, LlmJsonSanitizer.defaultFallbackMessage);
        // Conservar el surfaceId es lo que permite que un reintento tardío
        // encuentre este mensaje de nuevo — ver applySurfaceReady abajo.
        expect(message.surfaceId, 'assistant_invest_2');
        expect(message.isGenUiSurface, isFalse);
      },
    );

    test('is a no-op when no message is streaming for that surfaceId', () {
      final messages = [
        const PortfolioQaMessage(
          role: PortfolioQaRole.assistant,
          surfaceId: 'assistant_invest_2',
        ),
      ];

      final updated = AssistantMessageSync.applyFallback(
        messages,
        'assistant_invest_2',
        AssistantMode.invest,
      );

      expect(identical(updated, messages), isTrue);
    });
  });

  group('AssistantMessageSync.applySurfaceReady', () {
    test('marks a streaming message ready (the normal success path)', () {
      final messages = [
        const PortfolioQaMessage(
          role: PortfolioQaRole.assistant,
          surfaceId: 'assistant_invest_2',
          isStreaming: true,
          engineMode: AssistantMode.invest,
        ),
      ];

      final updated = AssistantMessageSync.applySurfaceReady(
        messages,
        'assistant_invest_2',
        hasRootComponent: true,
      );

      expect(updated.last.isStreaming, isFalse);
      expect(updated.last.isFallback, isFalse);
    });

    // Tercer caso del bug de superficies: el modelo puede terminar una
    // generación con `components: []` (o sin `root`) — el paquete genui
    // despacha ese evento igual, sin validarlo de su lado. Si esto marcara
    // el mensaje como listo, la card quedaría en blanco para siempre (el
    // warning "Surface X has no root component" del log del usuario) sin
    // que ningún mecanismo de timeout/fallback llegara a intervenir.
    test(
      'does NOT mark a streaming message ready when the surface has no '
      'root component — an empty/malformed generation must not be '
      'silently accepted as "done"',
      () {
        final messages = [
          const PortfolioQaMessage(
            role: PortfolioQaRole.assistant,
            surfaceId: 'assistant_explore_3',
            isStreaming: true,
            engineMode: AssistantMode.explore,
          ),
        ];

        final updated = AssistantMessageSync.applySurfaceReady(
          messages,
          'assistant_explore_3',
          hasRootComponent: false,
        );

        expect(identical(updated, messages), isTrue);
        expect(updated.last.isStreaming, isTrue);
      },
    );

    test(
      'does NOT resurrect an already-shown fallback when the late retry '
      'also has no root component',
      () {
        final messages = [
          PortfolioQaMessage(
            role: PortfolioQaRole.assistant,
            surfaceId: 'assistant_explore_3',
            engineMode: AssistantMode.explore,
            isFallback: true,
            content: LlmJsonSanitizer.defaultFallbackMessage,
          ),
        ];

        final updated = AssistantMessageSync.applySurfaceReady(
          messages,
          'assistant_explore_3',
          hasRootComponent: false,
        );

        expect(identical(updated, messages), isTrue);
        expect(updated.last.isFallback, isTrue);
      },
    );

    // El escenario del bug: el primer intento agota su espera y se muestra
    // el fallback, pero un reintento (interno de OpenAIGenUiService, o la
    // auto-resubmisión del paquete genui) resuelve la MISMA surface después
    // con componentes válidos. La respuesta real tiene que reemplazar al
    // error en pantalla — nunca debe quedar un error visible mientras hay
    // una respuesta válida para el mismo turno.
    test(
      'a late successful retry replaces an already-shown fallback error '
      'with the real surface, never leaving the error on screen',
      () {
        final afterFirstAttemptFailed = [
          const PortfolioQaMessage(role: PortfolioQaRole.user, content: 'quiero invertir 500 dólares'),
          PortfolioQaMessage(
            role: PortfolioQaRole.assistant,
            surfaceId: 'assistant_invest_2',
            engineMode: AssistantMode.invest,
            isFallback: true,
            content: LlmJsonSanitizer.defaultFallbackMessage,
          ),
        ];
        // Antes de la resurrección: la UI mostraría el error.
        expect(afterFirstAttemptFailed.last.isGenUiSurface, isFalse);
        expect(
          afterFirstAttemptFailed.last.content,
          LlmJsonSanitizer.defaultFallbackMessage,
        );

        // Llega tarde: ConversationComponentsUpdated para la misma surface,
        // ahora con QaAnswerText + QaBudgetSplit válidos en el registry.
        final afterLateRetrySucceeded = AssistantMessageSync.applySurfaceReady(
          afterFirstAttemptFailed,
          'assistant_invest_2',
          hasRootComponent: true,
        );

        final resurrected = afterLateRetrySucceeded.last;
        expect(resurrected.isFallback, isFalse);
        expect(resurrected.surfaceId, 'assistant_invest_2');
        // Ya no muestra el texto de error — y al no estar más en fallback,
        // AssistantScreen la renderiza como la surface real (ver
        // PortfolioQaMessage.isGenUiSurface).
        expect(resurrected.content, isNot(LlmJsonSanitizer.defaultFallbackMessage));
        expect(resurrected.isGenUiSurface, isTrue);
      },
    );

    test('is a no-op when no message has that surfaceId', () {
      final messages = [
        const PortfolioQaMessage(
          role: PortfolioQaRole.assistant,
          surfaceId: 'assistant_invest_2',
          isStreaming: true,
        ),
      ];

      final updated = AssistantMessageSync.applySurfaceReady(
        messages,
        'does_not_exist',
        hasRootComponent: true,
      );

      expect(identical(updated, messages), isTrue);
    });

    test(
      'is a no-op when the message for that surfaceId is already resolved '
      '(not streaming, not a fallback)',
      () {
        final messages = [
          const PortfolioQaMessage(
            role: PortfolioQaRole.assistant,
            surfaceId: 'assistant_invest_2',
          ),
        ];

        final updated = AssistantMessageSync.applySurfaceReady(
          messages,
          'assistant_invest_2',
          hasRootComponent: true,
        );

        expect(identical(updated, messages), isTrue);
      },
    );
  });
}
