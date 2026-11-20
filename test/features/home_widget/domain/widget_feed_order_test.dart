// Histéresis del feed (§4.3) y feed_rev.
// Correr: flutter test test/features/home_widget/domain/widget_feed_order_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_feed_order.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_snapshot.dart';

final _now = DateTime.utc(2026, 11, 6, 15);

WidgetFeedItem _item(String id, int prio, {Duration life = const Duration(hours: 24)}) =>
    WidgetFeedItem(
      id: id,
      kind: WidgetFeedKind.news,
      icon: 'news',
      expiresAt: _now.add(life),
      segments: [WidgetFeedSegment(from: _now, prio: prio)],
    );

WidgetFeedState _state(String head, Duration ago) =>
    WidgetFeedState(headId: head, headSince: _now.subtract(ago));

List<String?> _ids(WidgetFeedOrderResult r) => [for (final i in r.feed) i.id];

void main() {
  group('WidgetFeedOrder.apply', () {
    test('holds the head under 3 h against an equal-prio item', () {
      final r = WidgetFeedOrder.apply(
        ordered: [_item('new', 1), _item('old', 1)],
        state: _state('old', const Duration(hours: 1)),
        now: _now,
      );
      expect(_ids(r), ['old', 'new']);
      expect(r.state.headId, 'old');
      expect(r.state.headSince, _now.subtract(const Duration(hours: 1)));
    });

    test('releases the head at 3 h', () {
      final r = WidgetFeedOrder.apply(
        ordered: [_item('new', 1), _item('old', 1)],
        state: _state('old', const Duration(hours: 3)),
        now: _now,
      );
      expect(_ids(r), ['new', 'old']);
      expect(r.state.headId, 'new');
      expect(r.state.headSince, _now);
    });

    test('a higher-priority item displaces the head before 3 h', () {
      final r = WidgetFeedOrder.apply(
        ordered: [_item('urgent', 1), _item('old', 2)],
        state: _state('old', const Duration(minutes: 30)),
        now: _now,
      );
      expect(_ids(r), ['urgent', 'old']);
      expect(r.state.headId, 'urgent');
    });

    test('expired or missing head: new head starts now', () {
      final gone = WidgetFeedOrder.apply(
        ordered: [_item('a', 1)],
        state: _state('x', const Duration(hours: 1)),
        now: _now,
      );
      expect(gone.state.headId, 'a');
      expect(gone.state.headSince, _now);
      final expired = WidgetFeedOrder.apply(
        ordered: [_item('a', 1), _item('old', 1, life: Duration.zero)],
        state: _state('old', const Duration(hours: 1)),
        now: _now,
      );
      expect(_ids(expired), ['a', 'old']);
    });

    test('empty state sets the first as head', () {
      final r = WidgetFeedOrder.apply(
        ordered: [_item('a', 1)],
        state: const WidgetFeedState(),
        now: _now,
      );
      expect(r.state.headId, 'a');
    });

    test('feed_rev is 8 hex, stable and order-sensitive', () {
      final ab = WidgetFeedOrder.feedRev([_item('a', 1), _item('b', 1)]);
      expect(ab, matches(RegExp(r'^[0-9a-f]{8}$')));
      expect(WidgetFeedOrder.feedRev([_item('a', 1), _item('b', 1)]), ab);
      expect(WidgetFeedOrder.feedRev([_item('b', 1), _item('a', 1)]), isNot(ab));
    });
  });
}
