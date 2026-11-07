import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/utils/answer_stream_preview.dart';

import '../fakes/assistant_fakes.dart';

void main() {
  test('the text of QaAnswerText while it is being written', () {
    final full = a2uiAnswer('s1', 'Tu cartera subió 1,05 % en la semana.');
    final cut = full.indexOf('1,05');
    expect(
      AnswerStreamPreview.textOf(full.substring(0, cut)),
      'Tu cartera subió',
    );
    expect(
      AnswerStreamPreview.textOf(full),
      'Tu cartera subió 1,05 % en la semana.',
    );
  });

  test('every prefix of a full answer reads as a prefix of its text', () {
    const text = 'MSFT subió 3 % en una semana en la que anunció recompras.';
    final full = a2uiAnswer('s1', text);
    for (var i = 0; i <= full.length; i++) {
      final preview = AnswerStreamPreview.textOf(full.substring(0, i));
      expect(text.startsWith(preview), isTrue, reason: 'cut at $i: $preview');
    }
  });

  test('only the text: cards and tool rounds give nothing', () {
    const cards =
        '{"version":"v0.9","updateComponents":{"surfaceId":"s","components":'
        '[{"id":"root","component":"Column","children":["c"]},'
        '{"id":"c","component":"QaPriceChart","ticker":"AAPL"}]}}';
    expect(AnswerStreamPreview.textOf(cards), '');
    expect(AnswerStreamPreview.textOf(''), '');
  });

  test('several texts in order, and the nested component form', () {
    const raw =
        '{"updateComponents":{"components":['
        '{"id":"a","component":"QaAnswerText","text":"Uno."},'
        '{"id":"b","component":{"QaAnswerText":{"text":"Dos."}}}]}}';
    expect(AnswerStreamPreview.textOf(raw), 'Uno.\n\nDos.');
  });
}
