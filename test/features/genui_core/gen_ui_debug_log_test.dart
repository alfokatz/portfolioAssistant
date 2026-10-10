import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_debug_log.dart';

void main() {
  // Estos métodos son no-op fuera de debug mode (`kDebugMode`) — en el
  // entorno de test SÍ corre en debug, así que esto ejercita el mismo path
  // que corre en desarrollo. El objetivo no es aserción sobre stdout (ver
  // debugPrint no es práctico acá), sino confirmar que loguear nunca tira
  // una excepción — un log roto no debe tumbar el turno real del chat.
  group('GenUiDebugLog', () {
    test('installLoggerBridge is idempotent and does not throw', () {
      expect(GenUiDebugLog.installLoggerBridge, returnsNormally);
      expect(GenUiDebugLog.installLoggerBridge, returnsNormally);
      expect(
        () => genUiLogger.warning('Validation failed for surface test: boom'),
        returnsNormally,
      );
    });

    test('rawResponse does not throw for a null surfaceId', () {
      expect(
        () => GenUiDebugLog.rawResponse(surfaceId: null, raw: 'not json'),
        returnsNormally,
      );
    });

    test('controllerResubmit does not throw for the error-shaped message '
        'SurfaceController.reportError sends', () {
      final message = ChatMessage.user(
        '',
        parts: [
          UiInteractionPart.create(
            jsonEncode({
              'version': 'v0.9',
              'error': {
                'code': 'VALIDATION_FAILED',
                'message': 'Widget with id: investOptionNVDA not found.',
              },
            }),
          ),
        ],
      );

      expect(() => GenUiDebugLog.controllerResubmit(message), returnsNormally);
    });

    test(
      'componentChoice does not throw on malformed input',
      () {
        expect(
          () => GenUiDebugLog.componentChoice(
            surfaceId: 'surface_1',
            normalized: 'not json at all',
          ),
          returnsNormally,
        );
      },
    );
  });

  group('GenUiDebugLog.extractComponentTypes', () {
    test(
      'reads id:component pairs out of a createSurface + updateComponents '
      'pair — exactly the shape this needs to answer "which widget did the '
      'model actually choose?"',
      () {
        final normalized = [
          jsonEncode({
            'version': 'v0.9',
            'createSurface': {
              'surfaceId': 'surface_1',
              'catalogId': 'cat',
            },
          }),
          jsonEncode({
            'version': 'v0.9',
            'updateComponents': {
              'surfaceId': 'surface_1',
              'components': [
                {
                  'id': 'root',
                  'component': 'Column',
                  'children': ['answer', 'snapshot'],
                },
                {'id': 'answer', 'component': 'QaAnswerText'},
                {'id': 'snapshot', 'component': 'QaTickerSnapshot'},
              ],
            },
          }),
        ].join('\n');

        expect(
          GenUiDebugLog.extractComponentTypes(normalized),
          ['root:Column', 'answer:QaAnswerText', 'snapshot:QaTickerSnapshot'],
        );
      },
    );

    test('returns an empty list for text with no updateComponents message', () {
      expect(GenUiDebugLog.extractComponentTypes('not json at all'), isEmpty);
    });

    test('skips a malformed line but keeps parsing the rest', () {
      final normalized = [
        'this line is not json',
        jsonEncode({
          'version': 'v0.9',
          'updateComponents': {
            'surfaceId': 'surface_1',
            'components': [
              {'id': 'root', 'component': 'QaAnswerText'},
            ],
          },
        }),
      ].join('\n');

      expect(
        GenUiDebugLog.extractComponentTypes(normalized),
        ['root:QaAnswerText'],
      );
    });
  });
}
