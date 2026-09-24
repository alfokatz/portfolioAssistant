import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';

void main() {
  // Regresión: `SurfaceController.handleUiEvent`/`.reportError` (paquete
  // genui) reenvían un mensaje automático vía `Conversation.onSubmit` →
  // `A2uiTransportAdapter.sendRequest` → `handleSend`, SIN pasar
  // `surfaceId` y con el contenido real en `message.parts` (no en
  // `message.text`). Antes de este fix, `handleSend` solo miraba
  // `message.text` (vacío en ese caso), así que el motivo del error se
  // perdía en silencio — el modelo nunca se enteraba de qué corregir, y
  // `history` no dejaba ningún rastro de que algo había pasado. Estos
  // tests no llegan a la red (sin `apiKey` configurada, `handleSend` tira
  // `StateError` antes de llamar a OpenAI), pero eso pasa DESPUÉS de que
  // `history` ya se actualizó — suficiente para probar el fix en sí.
  OpenAIGenUiService buildService() {
    final service = OpenAIGenUiService(
      apiKey: '',
      model: 'test-model',
      systemPrompt: 'system prompt',
      catalog: const Catalog([]),
    );
    addTearDown(service.dispose);
    return service;
  }

  group('OpenAIGenUiService.handleSend', () {
    test(
      'a normal, explicit-surfaceId send still appends the user text to '
      'history',
      () async {
        final service = buildService();

        await expectLater(
          service.handleSend(ChatMessage.user('hola'), surfaceId: 'surface_1'),
          throwsA(isA<StateError>()),
        );

        expect(service.history.length, 2); // system + user
        expect(service.history.last.content!.first.text, 'hola');
      },
    );

    test(
      'does not silently drop a UiInteractionPart-only message — the exact '
      'shape SurfaceController.reportError sends after a failed validation '
      '(e.g. "Widget with id: investOptionNVDA not found")',
      () async {
        final service = buildService();
        final errorMessage = ChatMessage.user(
          '',
          parts: [
            UiInteractionPart.create(
              jsonEncode({
                'version': 'v0.9',
                'error': {
                  'code': 'VALIDATION_FAILED',
                  'surfaceId': 'surface_1',
                  'message': 'Widget with id: investOptionNVDA not found.',
                },
              }),
            ),
          ],
        );

        // Sin `surfaceId` explícito — así es como llega desde
        // `Conversation.onSubmit`.
        await expectLater(
          service.handleSend(errorMessage),
          throwsA(isA<StateError>()),
        );

        expect(service.history.length, 2); // system + el error descrito
        final added = service.history.last.content!.first.text!;
        expect(added, contains('investOptionNVDA'));
        expect(added, contains('ERROR DE VALIDACIÓN'));
      },
    );

    test(
      'forwards an interaction with an unrecognized shape as-is, instead of '
      'assuming it is always a validation error',
      () async {
        final service = buildService();
        final actionMessage = ChatMessage.user(
          '',
          parts: [
            UiInteractionPart.create(
              jsonEncode({
                'version': 'v0.9',
                'action': {'name': 'confirm_invest'},
              }),
            ),
          ],
        );

        await expectLater(
          service.handleSend(actionMessage),
          throwsA(isA<StateError>()),
        );

        final added = service.history.last.content!.first.text!;
        expect(added, contains('confirm_invest'));
      },
    );

    test('a message with no text and no parts is a pure no-op', () async {
      final service = buildService();

      await service.handleSend(ChatMessage.user(''));

      expect(service.history.length, 1); // solo el system prompt
    });

    // Regresión: mandar un segundo mensaje sin esperar respuesta al
    // primero. `history` es estado compartido entre llamadas — sin la
    // cola de serialización (`AsyncCallQueue`, ver `handleSend`), dos
    // `handleSend` sueltos en paralelo podían intercalar sus appends a
    // `history` en cualquier orden. Acá ambos apuntan a `apiKey: ''`, así
    // que los dos terminan en el mismo `StateError` — el punto no es el
    // error en sí, sino que (a) NINGUNO se pierde en silencio (ambos
    // futures resuelven) y (b) sus mensajes de usuario quedan en `history`
    // en el orden en que se mandaron, no mezclados.
    test(
      'sending a second message before awaiting the first never drops '
      'either one, and does not interleave their history entries',
      () async {
        final service = buildService();

        final first = service.handleSend(
          ChatMessage.user('primer mensaje'),
          surfaceId: 'surface_1',
        );
        final second = service.handleSend(
          ChatMessage.user('segundo mensaje'),
          surfaceId: 'surface_2',
        );

        await expectLater(first, throwsA(isA<StateError>()));
        await expectLater(second, throwsA(isA<StateError>()));

        // system + "primer mensaje" + "segundo mensaje" — en ese orden,
        // sin importar que se dispararon sin esperar entre sí.
        expect(service.history.length, 3);
        expect(service.history[1].content!.first.text, 'primer mensaje');
        expect(service.history[2].content!.first.text, 'segundo mensaje');
      },
    );
  });
}
