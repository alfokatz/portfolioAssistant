/// Un ítem vivo del feed: [index] es su posición en `v2.feed` (así los casos
/// compartidos identifican filas aun cuando el ítem está en forma oculta).
typedef WidgetLiveItem = ({int index, Map<String, Object?> item, int prio});

/// Implementación de REFERENCIA en Dart de las reglas del nativo
/// (docs/specs/home-widget-v2-tech.md §3.5). La app NO la usa para dibujar:
/// existe para los tests y para generar `feed_cases.json`, el contrato que
/// comparten `FeedPicker` (Swift) y `PortyFeedPicker` (Kotlin).
///
/// Trabaja sobre el JSON del snapshot, igual que el nativo. Todas las horas
/// son epoch ms.
abstract final class WidgetFeedPicker {
  static Map<String, Object?>? v2Of(Map<String, Object?> snapshot) {
    final v2 = snapshot['v2'];
    return v2 is Map ? v2.cast<String, Object?>() : null;
  }

  static int _int(Object? value) => (value! as num).toInt();

  /// Prioridad del segmento vigente: el último con `from <= now` (el primero
  /// si ninguno arrancó).
  static int prioAt(Map<String, Object?> item, int now) {
    final segments = item['segments']! as List;
    var current = segments.first as Map;
    for (final raw in segments) {
      final seg = raw as Map;
      if (_int(seg['from']) <= now) current = seg;
    }
    return _int(current['prio']);
  }

  /// Ítems con `now < expires_at`, sin los pagos pasado `plan_until`,
  /// ordenados de forma estable por prioridad vigente.
  static List<WidgetLiveItem> live(Map<String, Object?> v2, int now) {
    final planUntil = v2['plan_until'] == null ? null : _int(v2['plan_until']);
    final feed = (v2['feed'] as List?) ?? const [];
    final alive = <WidgetLiveItem>[];
    for (var i = 0; i < feed.length; i++) {
      final item = (feed[i] as Map).cast<String, Object?>();
      if (now >= _int(item['expires_at'])) continue;
      if (item['paid'] == true && planUntil != null && now >= planUntil) {
        continue;
      }
      alive.add((index: i, item: item, prio: prioAt(item, now)));
    }
    // Orden estable: 1, 2, 3 y, dentro de cada una, el orden de Dart.
    return [
      for (final p in const [1, 2, 3])
        for (final l in alive)
          if (l.prio == p) l,
    ];
  }

  /// Cantidad de vivos con prioridad 1 o 2 (el número del encabezado).
  static int headerCount(List<WidgetLiveItem> live) =>
      live.where((l) => l.prio <= 2).length;

  /// Índice del ítem que muestra el mediano. El cursor solo vale si es del
  /// mismo `feed_rev`.
  static int currentIndex(
    Map<String, Object?> v2,
    List<WidgetLiveItem> live,
    Map<String, Object?>? cursor,
  ) {
    if (live.isEmpty) return 0;
    final rev = v2['feed_rev'];
    if (cursor == null || rev == null || cursor['rev'] != rev) return 0;
    return _int(cursor['index']) % live.length;
  }

  /// El cursor que escribe "siguiente"; `null` si no hay nada que avanzar.
  static Map<String, Object?>? advance(
    Map<String, Object?> v2,
    int now,
    Map<String, Object?>? cursor,
  ) {
    final alive = live(v2, now);
    if (alive.isEmpty || v2['positions_hidden'] == true) return null;
    final current = currentIndex(v2, alive, cursor);
    return {
      'rev': v2['feed_rev'],
      'index': (current + 1) % alive.length,
      'at': now,
    };
  }

  static String? _ref(Object? question) =>
      question is Map ? question['ref'] as String? : null;

  static List<WidgetLiveItem> largeRows(List<WidgetLiveItem> live) {
    final rows = <WidgetLiveItem>[];
    final skipped = <WidgetLiveItem>[];
    final perKind = <String, int>{};
    for (final l in live) {
      if (rows.length == 3) break;
      final kind = l.item['kind']! as String;
      final count = perKind[kind] ?? 0;
      if (count >= 2) {
        skipped.add(l);
      } else {
        perKind[kind] = count + 1;
        rows.add(l);
      }
    }
    for (final l in skipped) {
      if (rows.length == 3) break;
      rows.add(l);
    }
    return rows;
  }

  /// Lo que dibuja cada tamaño, en la forma de `expected` de
  /// `feed_cases.json` (ver `test/fixtures/home_widget/v2/README.md`).
  static Map<String, Object?> pick({
    required Map<String, Object?> snapshot,
    required int now,
    Map<String, Object?>? cursor,
  }) {
    final v2 = v2Of(snapshot)!;
    final hidden = v2['positions_hidden'] == true;
    final alive = live(v2, now);
    final questions = (v2['questions'] as Map?) ?? const {};
    final fallback = _ref(questions['fallback']);
    final large = [
      for (final q in (questions['large'] as List?) ?? const []) _ref(q),
    ];
    final top = alive.where((l) => l.prio <= 2).toList();
    final hasChart = v2['chart'] != null;

    final Map<String, Object?> small;
    if (hidden) {
      small =
          top.isNotEmpty
              ? {'line': 'hidden_count', 'n': top.length}
              : {'line': hasChart ? 'chart' : 'no_news'};
    } else if (top.isNotEmpty) {
      small = {'line': 'item', 'feed_index': top.first.index};
    } else {
      small = {'line': hasChart ? 'chart' : 'no_news'};
    }

    final current = currentIndex(v2, alive, cursor);
    final Map<String, Object?> medium;
    if (alive.isEmpty || (hidden && top.isEmpty)) {
      medium = {'mode': 'no_news', 'question': fallback, 'next_button': false};
    } else if (hidden) {
      medium = {
        'mode': 'hidden_count',
        'n': top.length,
        'question': fallback,
        'next_button': false,
      };
    } else {
      final shown = alive[current];
      medium = {
        'mode': 'item',
        'feed_index': shown.index,
        'question': _ref(shown.item['q']) ?? fallback,
        'next_button': alive.length >= 2,
      };
    }

    final Map<String, Object?> largeSize;
    if (alive.isEmpty || (hidden && top.isEmpty)) {
      largeSize = {'mode': 'no_news', 'questions': large};
    } else if (hidden) {
      largeSize = {
        'mode': 'hidden_count',
        'n': top.length,
        'questions': large,
      };
    } else {
      largeSize = {
        'mode': 'rows',
        'rows': [for (final l in largeRows(alive)) l.index],
        'questions': large,
      };
    }

    final staleAt = snapshot['stale_at'];
    final next = advance(v2, now, cursor);
    return {
      'stale': staleAt != null && now >= _int(staleAt),
      'header_n': headerCount(alive),
      'small': small,
      'medium': medium,
      'large': largeSize,
      'next_index': next?['index'],
    };
  }
}
