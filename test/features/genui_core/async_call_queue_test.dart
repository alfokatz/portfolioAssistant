import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/genui_core/utils/async_call_queue.dart';

void main() {
  group('AsyncCallQueue', () {
    // El escenario del bug: mandar un segundo mensaje sin esperar
    // respuesta al primero. `OpenAIGenUiService.handleSend` usa esta cola
    // para que, aunque el caller (AssistantProvider) ya haya dejado de
    // esperar al primer turno (p. ej. por su propio timeout externo), el
    // segundo `run` no empiece a ejecutar su callback hasta que el primero
    // termine de verdad — nunca corren en paralelo sobre el mismo recurso.
    test(
      'a second run() does not start executing until the first one settles, '
      'even if the caller does not await the first',
      () async {
        final queue = AsyncCallQueue();
        final order = <String>[];
        final firstStarted = Completer<void>();
        final releaseFirst = Completer<void>();

        // No se espera (`unawaited`, a propósito) — así se prueba la cola,
        // no el orden en que el test llama a `run`.
        final firstResult = queue.run(() async {
          order.add('first-start');
          firstStarted.complete();
          await releaseFirst.future;
          order.add('first-end');
        });

        await firstStarted.future;
        expect(order, ['first-start']);

        // Se dispara el segundo ANTES de que el primero termine — sin
        // esperar respuesta al primero, igual que el reporte del usuario.
        final secondResult = queue.run(() async {
          order.add('second-start');
        });

        // Si la cola no serializara, "second-start" ya estaría acá.
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(order, ['first-start']);

        releaseFirst.complete();
        await firstResult;
        await secondResult;

        expect(order, ['first-start', 'first-end', 'second-start']);
      },
    );

    // Criterio de aceptación: por más rápido que se manden mensajes
    // seguidos, cada uno termina con una respuesta real o un error
    // honesto — nunca en silencio. A nivel de la cola, eso significa que
    // NINGÚN `run()` se pierde: cada uno resuelve (éxito o error propio).
    test(
      'every queued run() eventually settles — none is silently dropped, '
      'even when sent back-to-back without waiting',
      () async {
        final queue = AsyncCallQueue();
        final results = <int>[];

        final futures = [
          for (var i = 0; i < 5; i++)
            queue.run(() async {
              await Future<void>.delayed(const Duration(milliseconds: 5));
              results.add(i);
              return i;
            }),
        ];

        final settled = await Future.wait(futures);

        expect(settled, [0, 1, 2, 3, 4]);
        expect(results, [0, 1, 2, 3, 4]);
      },
    );

    test(
      'a failing run() does not block the ones queued behind it, and its '
      'own error still reaches its caller',
      () async {
        final queue = AsyncCallQueue();

        final failing = queue.run<void>(
          () async => throw StateError('boom'),
        );
        final next = queue.run(() async => 'ok');

        await expectLater(failing, throwsA(isA<StateError>()));
        expect(await next, 'ok');
      },
    );

    test('runs sequentially in FIFO order for many overlapping calls', () async {
      final queue = AsyncCallQueue();
      final order = <int>[];

      final futures = [
        for (var i = 0; i < 3; i++)
          queue.run(() async {
            // Delay decreciente: si NO estuviera serializado, el orden de
            // finalización se invertiría (el más corto terminaría primero).
            await Future<void>.delayed(Duration(milliseconds: (3 - i) * 10));
            order.add(i);
          }),
      ];

      await Future.wait(futures);

      expect(order, [0, 1, 2]);
    });
  });
}
