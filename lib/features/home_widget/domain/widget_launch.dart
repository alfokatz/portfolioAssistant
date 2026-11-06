/// Las preguntas rápidas del widget. Viajan por la URL solo como id: el
/// texto sale de las traducciones de la app, nunca de la URL.
enum WidgetQuestionId {
  today('today', 'question_today'),
  topMover('top_mover', 'question_top_mover');

  const WidgetQuestionId(this.wire, this.textKey);

  final String wire;

  /// Clave del texto de la pregunta dentro de `home_widget_*`.
  final String textKey;

  /// Clave completa en es-ES.json / en-US.json (para `.tr()`).
  String get translationKey => 'home_widget_$textKey';

  static WidgetQuestionId? fromWire(String? wire) {
    for (final id in values) {
      if (id.wire == wire) return id;
    }
    return null;
  }
}

enum WidgetLaunchTarget {
  chat('chat'),
  question('question'),
  addPortfolio('add_portfolio'),
  news('news'),
  earnings('earnings'),
  teaserNews('teaser_news'),
  teaserEarnings('teaser_earnings'),
  app('app');

  bool get isItem => this == news || this == earnings;
  bool get isTeaser => this == teaserNews || this == teaserEarnings;

  const WidgetLaunchTarget(this.wire);

  final String wire;

  static WidgetLaunchTarget? fromWire(String? wire) {
    for (final t in values) {
      if (t.wire == wire) return t;
    }
    return null;
  }
}

/// Un toque del widget, ya validado. Solo se aceptan valores de listas
/// cerradas: nada de texto libre que venga de afuera.
class WidgetLaunch {
  const WidgetLaunch({
    required this.target,
    this.questionId,
    this.size,
    this.dataAgeMin,
    this.itemId,
    this.rank,
  });

  final WidgetLaunchTarget target;

  /// Solo con `news` / `earnings`: 8 hex, opaco.
  final String? itemId;

  /// Posición del ítem tocado (1 a 4).
  final int? rank;

  /// Solo con `target == question`.
  final WidgetQuestionId? questionId;

  /// `small` | `medium` | `large` | `null` si no vino o no es uno de esos.
  final String? size;

  /// Minutos desde que se trajeron los datos que mostraba el widget.
  final int? dataAgeMin;

  static const scheme = 'porty-widget';
  static const host = 'open';

  /// `porty-widget://open?homeWidget&target=question&q=today&size=medium`.
  /// Devuelve `null` si no es del widget (otro esquema o host, sin
  /// `homeWidget`, `target` desconocido). Una pregunta desconocida abre el
  /// chat vacío: nunca se manda nada que no esté en [WidgetQuestionId].
  static WidgetLaunch? parse(Uri? uri) {
    if (uri == null || uri.scheme != scheme || uri.host != host) return null;
    final params = uri.queryParameters;
    if (!params.containsKey('homeWidget')) return null;
    final target = WidgetLaunchTarget.fromWire(params['target']);
    if (target == null) return null;
    final size = params['size'];
    final age = int.tryParse(params['age'] ?? '');
    final common = (
      size:
          size == 'small' || size == 'medium' || size == 'large' ? size : null,
      age: age != null && age >= 0 ? age : null,
    );
    if (target == WidgetLaunchTarget.question) {
      final id = WidgetQuestionId.fromWire(params['q']);
      return WidgetLaunch(
        target: id == null ? WidgetLaunchTarget.chat : target,
        questionId: id,
        size: common.size,
        dataAgeMin: common.age,
      );
    }
    if (target.isItem) {
      final id = params['id'];
      final rank = int.tryParse(params['rank'] ?? '');
      // Un id que no es de 8 hex no abre nada: queda en la Home.
      final valid = id != null && _idPattern.hasMatch(id);
      return WidgetLaunch(
        target: valid ? target : WidgetLaunchTarget.app,
        itemId: valid ? id : null,
        rank: valid && rank != null && rank >= 1 && rank <= 4 ? rank : null,
        size: common.size,
        dataAgeMin: common.age,
      );
    }
    return WidgetLaunch(
      target: target,
      size: common.size,
      dataAgeMin: common.age,
    );
  }

  static final _idPattern = RegExp(r'^[0-9a-f]{8}$');
}

/// iOS puede entregar el mismo toque dos veces (el launch inicial y el
/// stream): el segundo con la misma URL dentro de [window] se descarta.
class WidgetLaunchDeduper {
  WidgetLaunchDeduper({
    this.window = const Duration(seconds: 2),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Duration window;
  final DateTime Function() _now;

  String? _lastUrl;
  DateTime? _lastAt;

  /// `true` si hay que atender [uri]; lo anota como el último atendido.
  bool shouldHandle(Uri uri) {
    final url = uri.toString();
    final now = _now();
    final repeated =
        url == _lastUrl && _lastAt != null && now.difference(_lastAt!) < window;
    if (repeated) return false;
    _lastUrl = url;
    _lastAt = now;
    return true;
  }
}
