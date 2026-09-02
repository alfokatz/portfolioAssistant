import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:portfolio_assistant/features/assistant/catalog/portfolio_qa_catalog.dart';
import 'package:portfolio_assistant/features/genui_core/utils/a2ui_response_normalizer.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_request_tracker.dart';
import '../../helpers/genui_test_helpers.dart';

void main() {
  group('GenUiRequestTracker.sendAndWait', () {
    late SurfaceController controller;
    late Conversation conversation;

    setUp(() {
      controller = SurfaceController(catalogs: [PortfolioQaCatalog.build()]);
      conversation = Conversation(
        controller: controller,
        transport: A2uiTransportAdapter(),
      );
    });

    tearDown(() {
      conversation.dispose();
    });

    test(
      'times out instead of hanging forever when send() never resolves',
      () async {
        // Reproduces the reported bug: an OpenAI stream that stalls mid
        // response used to hang `send()` forever, and the old timeout only
        // wrapped the completer wait, which was never reached.
        Future<void> neverCompletingSend() => Completer<void>().future;

        await expectLater(
          GenUiRequestTracker.sendAndWait(
            conversation: conversation,
            targetSurfaceId: 'portfolio_qa_0',
            send: neverCompletingSend,
            timeout: const Duration(milliseconds: 200),
          ),
          throwsA(isA<TimeoutException>()),
        );
      },
      timeout: const Timeout(Duration(seconds: 5)),
    );

    test(
      'completes once the target surface renders a root component',
      () async {
        const surfaceId = 'portfolio_qa_0';
        // `dispatchNormalizedA2ui` expects newline-delimited JSON (one
        // complete message per line); run the raw fixture through the same
        // normalizer the real pipeline uses instead of hand-formatting it.
        const raw = '''
[
  {"id": "root", "component": "QaAnswerText", "text": "Tu portfolio subió 5,4% hoy."}
]
''';
        final normalized = A2uiResponseNormalizer.normalize(
          raw,
          surfaceId: surfaceId,
        );

        await GenUiRequestTracker.sendAndWait(
          conversation: conversation,
          targetSurfaceId: surfaceId,
          send: () async {
            dispatchNormalizedA2ui(controller, normalized);
          },
          timeout: const Duration(seconds: 1),
        );

        expect(controller.activeSurfaceIds, contains(surfaceId));
      },
    );
  });
}
