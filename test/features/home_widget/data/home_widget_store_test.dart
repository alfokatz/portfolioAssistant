// "Ocultar posiciones" sobre el snapshot ya guardado (arranque sin red).
// Correr: flutter test test/features/home_widget/data/home_widget_store_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/home_widget/data/home_widget_store.dart';

Map<String, Object?> _ready() => {
  'v': 1,
  'state': 'ready',
  'change_pct_text': '+1.2%',
  'v2': {
    'positions_hidden': false,
    'feed_rev': 'abcd1234',
    'feed': [
      {
        'id': '3d94a431',
        'kind': 'news',
        'icon': 'news',
        'tag': 'NVDA',
        'paid': true,
        'expires_at': 10,
        'segments': [
          {'from': 1, 'prio': 1, 'short': 'NVDA · noticia', 'title': 'Titular'},
        ],
        'a11y': 'Noticia de NVDA',
        'open': {'target': 'news', 'id': '3d94a431'},
        'q': {'ref': 'a2cb7053', 't': 'news_what', 'text': '¿Qué pasó con NVDA?'},
      },
    ],
    'questions': {
      'fallback': {'ref': 'c83a8d13', 'text': '¿Cómo voy con Casa?'},
      'large': [
        {'ref': 'a2cb7053', 'text': '¿Qué pasó con NVDA?'},
      ],
    },
  },
};

void main() {
  test('keeps kind, icon, expiry and priority; drops everything else', () {
    final out = scrubPositionsFromSnapshotJson(_ready())!;
    final v2 = out['v2']! as Map;
    expect(v2['positions_hidden'], true);
    expect(v2.containsKey('feed_rev'), isFalse);
    final item = (v2['feed']! as List).single as Map;
    expect(item, {
      'kind': 'news',
      'icon': 'news',
      'paid': true,
      'expires_at': 10,
      'segments': [
        {'from': 1, 'prio': 1},
      ],
    });
    expect(v2['questions'], {'fallback': null, 'large': <Object?>[]});
    expect(out['change_pct_text'], '+1.2%');
    final text = out.toString();
    for (final secret in ['NVDA', 'Titular', 'Casa', '3d94a431', 'a2cb7053']) {
      expect(text, isNot(contains(secret)), reason: secret);
    }
  });

  test('not ready or without v2: nothing to scrub', () {
    expect(scrubPositionsFromSnapshotJson({'state': 'signed_out'}), isNull);
    expect(scrubPositionsFromSnapshotJson({'state': 'ready'}), isNull);
  });
}
