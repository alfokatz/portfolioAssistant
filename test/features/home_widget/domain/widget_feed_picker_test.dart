// Reglas del selector de referencia (§3.5 de la spec v2) y verificación de
// feed_cases.json, el contrato compartido con Swift y Kotlin. Para regenerar
// los `expected`: UPDATE_WIDGET_FIXTURES=1 flutter test <este archivo>
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_feed_picker.dart';

const _file = 'test/fixtures/home_widget/v2/feed_cases.json';

Map<String, Object?> _item(String kind, int prio, {int expires = 1000}) => {
  'kind': kind,
  'icon': 'news',
  'expires_at': expires,
  'segments': [
    {'from': 0, 'prio': prio},
  ],
};

Map<String, Object?> _snap(
  List<Map<String, Object?>> feed, {
  Object? chart,
  bool hidden = false,
  int? planUntil,
}) => {
  'stale_at': 5000,
  'v2': {
    'positions_hidden': hidden,
    'plan_until': planUntil,
    'chart': chart,
    'feed_rev': hidden ? null : 'abc12345',
    'feed': feed,
    'questions': {
      'fallback': {'ref': 'fb000000'},
      'large': <Object?>[],
    },
  },
};

Map<String, Object?> _pick(
  Map<String, Object?> snap, {
  int now = 10,
  Map<String, Object?>? cursor,
}) => WidgetFeedPicker.pick(snapshot: snap, now: now, cursor: cursor);

void main() {
  group('WidgetFeedPicker', () {
    test('live orders by prio keeping the order inside each one', () {
      final snap = _snap([
        _item('news', 3),
        _item('earnings', 1),
        _item('insight', 2),
        _item('news', 1),
      ]);
      final live = WidgetFeedPicker.live(WidgetFeedPicker.v2Of(snap)!, 10);
      expect([for (final l in live) l.index], [1, 3, 2, 0]);
    });

    test('segment change reorders: prio follows the current segment', () {
      final item = _item('news', 1)
        ..['segments'] = [
          {'from': 0, 'prio': 1},
          {'from': 100, 'prio': 3},
        ];
      final snap = _snap([item, _item('insight', 2)]);
      final v2 = WidgetFeedPicker.v2Of(snap)!;
      expect(WidgetFeedPicker.live(v2, 10).first.index, 0);
      expect(WidgetFeedPicker.live(v2, 200).first.index, 1);
    });

    test('expired and paid-after-plan items are dropped', () {
      final paid = _item('news', 1)..['paid'] = true;
      final snap = _snap([paid, _item('insight', 2, expires: 50)], planUntil: 20);
      final v2 = WidgetFeedPicker.v2Of(snap)!;
      expect(WidgetFeedPicker.live(v2, 10), hasLength(2));
      expect(WidgetFeedPicker.live(v2, 30).map((l) => l.index), [1]);
      expect(WidgetFeedPicker.live(v2, 60), isEmpty);
    });

    test('small: first prio<=2, else chart, else no_news', () {
      expect(_pick(_snap([_item('news', 2)]))['small'], {
        'line': 'item',
        'feed_index': 0,
      });
      expect(_pick(_snap([_item('news', 3)], chart: {}))['small'], {
        'line': 'chart',
      });
      expect(_pick(_snap([]))['small'], {'line': 'no_news'});
    });

    test('hidden positions: counts only, no button', () {
      final r = _pick(_snap([_item('news', 1), _item('news', 3)], hidden: true));
      expect(r['small'], {'line': 'hidden_count', 'n': 1});
      expect((r['medium']! as Map)['mode'], 'hidden_count');
      expect((r['medium']! as Map)['n'], 2);
      expect((r['medium']! as Map)['next_button'], false);
      expect(r['next_index'], isNull);
    });

    test('medium: cursor of another rev goes back to 0; same rev wraps', () {
      final snap = _snap([_item('news', 1), _item('news', 1), _item('news', 1)]);
      Map<String, Object?> medium(Map<String, Object?>? c) =>
          _pick(snap, cursor: c)['medium']! as Map<String, Object?>;
      expect(medium({'rev': 'zzz', 'index': 2})['feed_index'], 0);
      expect(medium({'rev': 'abc12345', 'index': 2})['feed_index'], 2);
      expect(medium({'rev': 'abc12345', 'index': 4})['feed_index'], 1);
      expect(medium(null)['next_button'], true);
    });

    test('advance cycles and wraps; null without items', () {
      final v2 = WidgetFeedPicker.v2Of(
        _snap([_item('news', 1), _item('news', 1)]),
      )!;
      final first = WidgetFeedPicker.advance(v2, 10, null)!;
      expect(first['index'], 1);
      final second = WidgetFeedPicker.advance(v2, 10, first)!;
      expect(second['index'], 0);
      expect(WidgetFeedPicker.advance(WidgetFeedPicker.v2Of(_snap([]))!, 10, null), isNull);
    });

    test('large: max 2 per kind, then fills with the skipped', () {
      final five = _snap([for (var i = 0; i < 5; i++) _item('news', 1)]);
      expect((_pick(five)['large']! as Map)['rows'], [0, 1, 2]);
      final mixed = _snap([
        for (var i = 0; i < 4; i++) _item('news', 1),
        _item('insight', 2),
      ]);
      expect((_pick(mixed)['large']! as Map)['rows'], [0, 1, 4]);
    });

    test('header_n counts live items with prio <= 2', () {
      final snap = _snap([_item('news', 1), _item('insight', 2), _item('mover', 3)]);
      expect(_pick(snap)['header_n'], 2);
    });
  });

  group('feed_cases.json', () {
    final update = Platform.environment['UPDATE_WIDGET_FIXTURES'] == '1';
    final doc =
        jsonDecode(File(_file).readAsStringSync()) as Map<String, Object?>;
    final cases = doc['cases']! as List;

    test('every case matches the reference picker', () {
      for (final raw in cases) {
        final c = raw as Map<String, Object?>;
        final actual =
            jsonDecode(
                  jsonEncode(
                    WidgetFeedPicker.pick(
                      snapshot: (c['snapshot']! as Map).cast<String, Object?>(),
                      now: c['now']! as int,
                      cursor: (c['cursor'] as Map?)?.cast<String, Object?>(),
                    ),
                  ),
                )
                as Map<String, Object?>;
        if (update) {
          c['expected'] = actual;
        } else {
          expect(actual, c['expected'], reason: c['name'] as String);
        }
      }
      if (update) {
        File(_file).writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(doc)}\n',
        );
      }
    });
  });
}
