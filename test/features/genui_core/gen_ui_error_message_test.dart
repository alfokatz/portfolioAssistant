import 'dart:async';
import 'dart:io';

import 'package:dart_openai/dart_openai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_error_message.dart';

void main() {
  group('genUiErrorMessage', () {
    test('429 without rate limit text is treated as rate limit', () {
      final error = RequestFailedException(
        '{"error":{"message":"Too many requests"}}',
        429,
      );

      expect(isOpenAiRateLimitError(error), isTrue);
      expect(
        genUiErrorMessage(error),
        contains('límite de uso por minuto'),
      );
    });

    test('extracts retry seconds from retry-after milliseconds', () {
      expect(
        openAiSuggestedRetrySeconds('retry-after: 3200ms'),
        4,
      );
    });
  });

  group('isConnectionFailure', () {
    // Regresión: distingue una falla de conexión real (sin internet, DNS,
    // conexión rechazada) de una falla de generación (el modelo tardó,
    // devolvió JSON inválido, etc.) — el banner de error visible queda
    // reservado solo para la primera; la segunda cae a una respuesta de
    // texto simple (ver AssistantProvider.sendMessage).
    test('is true for a SocketException', () {
      final error = const SocketException('Failed host lookup');
      expect(isConnectionFailure(error), isTrue);
    });

    test('is false for a TimeoutException (falla de generación, no de red)', () {
      expect(isConnectionFailure(TimeoutException('tardó demasiado')), isFalse);
    });

    test('is false for a StateError (esquema/interfaz inválida)', () {
      expect(
        isConnectionFailure(StateError('La IA no generó una interfaz válida.')),
        isFalse,
      );
    });

    test('is false for a RequestFailedException (falla de la API)', () {
      final error = RequestFailedException('server error', 500);
      expect(isConnectionFailure(error), isFalse);
    });

    test('is false for an A2uiValidationException', () {
      expect(isConnectionFailure(A2uiValidationException('bad shape')), isFalse);
    });
  });
}
