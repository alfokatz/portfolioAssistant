import 'package:portfolio_assistant/features/home_widget/domain/widget_items_selector.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_snapshot.dart';

/// Quién encabeza el feed y desde cuándo (se guarda en
/// `widget_feed_state_v1`, por uid).
class WidgetFeedState {
  const WidgetFeedState({this.headId, this.headSince});

  final String? headId;
  final DateTime? headSince;

  Map<String, Object?> toJson() => {
    'head_id': headId,
    'head_since': headSince?.toUtc().millisecondsSinceEpoch,
  };

  static WidgetFeedState fromJson(Map<String, Object?> json) {
    final since = json['head_since'];
    return WidgetFeedState(
      headId: json['head_id'] as String?,
      headSince:
          since is num
              ? DateTime.fromMillisecondsSinceEpoch(
                since.toInt(),
                isUtc: true,
              )
              : null,
    );
  }
}

class WidgetFeedOrderResult {
  const WidgetFeedOrderResult({
    required this.feed,
    required this.state,
    required this.feedRev,
  });

  final List<WidgetFeedItem> feed;
  final WidgetFeedState state;
  final String feedRev;
}

/// Histéresis del feed (docs/specs/home-widget-v2-tech.md §4.3): el primero
/// no cambia por ruido. Solo lo desplaza algo de prioridad estrictamente
/// más alta, o pasadas [minHold] horas.
abstract final class WidgetFeedOrder {
  /// Cuánto se sostiene el primero (la ajusta data con `widget_items_rendered`).
  static const minHold = Duration(hours: 3);

  /// FNV-1a 32 de los ids en orden, unidos por ",": 8 hex.
  static String feedRev(List<WidgetFeedItem> feed) =>
      WidgetItemsSelector.itemId([for (final i in feed) i.id ?? ''].join(','));

  /// [ordered] es el orden base (§4.2) con los ítems completos (con `id`).
  static WidgetFeedOrderResult apply({
    required List<WidgetFeedItem> ordered,
    required WidgetFeedState state,
    required DateTime now,
  }) {
    var feed = ordered;
    final headId = state.headId;
    final since = state.headSince;
    if (headId != null && since != null) {
      final index = ordered.indexWhere(
        (i) => i.id == headId && now.isBefore(i.expiresAt),
      );
      if (index > 0) {
        final held = ordered[index];
        final heldPrio = held.prioAt(now);
        final holding = now.difference(since) < minHold;
        final outranked = ordered.any((i) => i.prioAt(now) < heldPrio);
        if (holding && !outranked) {
          feed = [held, ...ordered.sublist(0, index), ...ordered.sublist(index + 1)];
        }
      }
    }
    final newHead = feed.isEmpty ? null : feed.first.id;
    final next =
        newHead == headId && since != null
            ? state
            : WidgetFeedState(headId: newHead, headSince: now);
    return WidgetFeedOrderResult(
      feed: feed,
      state: next,
      feedRev: feedRev(feed),
    );
  }
}
