import 'package:portfolio_assistant/features/home_widget/domain/widget_questions.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_snapshot.dart';

enum WidgetLaunchTarget {
  chat('chat'),
  question('question'),
  addPortfolio('add_portfolio'),
  home('home'),
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
    this.questionTemplate,
    this.questionRef,
    this.questionSource,
    this.size,
    this.dataAgeMin,
    this.itemId,
    this.rank,
    this.itemKind,
    this.itemPrio,
  });

  final WidgetLaunchTarget target;

  /// Solo con `news` / `earnings`: 8 hex, opaco.
  final String? itemId;

  /// Posición del ítem tocado (1 a 4).
  final int? rank;

  /// Solo con `target == question`: la plantilla (lista cerrada), el `ref`
  /// de 8 hex que busca el detalle en la caché privada y de dónde salió.
  /// Nunca viaja texto.
  final WidgetQuestionTemplate? questionTemplate;
  final String? questionRef;
  final WidgetQuestionSource? questionSource;

  /// De qué novedad viene el toque (solo props de eventos); `null` si no
  /// vino o es inválido.
  final WidgetFeedKind? itemKind;
  final int? itemPrio;

  /// `small` | `medium` | `large` | `null` si no vino o no es uno de esos.
  final String? size;

  /// Minutos desde que se trajeron los datos que mostraba el widget.
  final int? dataAgeMin;

  static const scheme = 'porty-widget';
  static const host = 'open';

  /// `porty-widget://open?homeWidget&target=question&q=<plantilla>&ref=<8 hex>
  /// &src=<fuente>&size=medium`. Devuelve `null` si no es del widget (otro
  /// esquema o host, sin `homeWidget`, `target` desconocido). Una pregunta
  /// con plantilla, `ref` o fuente inválidos (o los ids viejos `today` /
  /// `top_mover`) abre el chat vacío: nunca se manda nada que no esté en
  /// [WidgetQuestionTemplate].
  static WidgetLaunch? parse(Uri? uri) {
    if (uri == null || uri.scheme != scheme || uri.host != host) return null;
    final params = uri.queryParameters;
    if (!params.containsKey('homeWidget')) return null;
    final target = WidgetLaunchTarget.fromWire(params['target']);
    if (target == null) return null;
    final size = params['size'];
    final age = int.tryParse(params['age'] ?? '');
    final prio = int.tryParse(params['prio'] ?? '');
    final common = (
      size:
          size == 'small' || size == 'medium' || size == 'large' ? size : null,
      age: age != null && age >= 0 ? age : null,
      kind: WidgetFeedKind.fromWire(params['kind']),
      prio: prio != null && prio >= 1 && prio <= 3 ? prio : null,
    );
    if (target == WidgetLaunchTarget.question) {
      final template = WidgetQuestionTemplate.fromWire(params['q']);
      final ref = params['ref'];
      final source = WidgetQuestionSource.fromWire(params['src']);
      final valid =
          template != null &&
          source != null &&
          ref != null &&
          _idPattern.hasMatch(ref);
      return WidgetLaunch(
        target: valid ? target : WidgetLaunchTarget.chat,
        questionTemplate: valid ? template : null,
        questionRef: valid ? ref : null,
        questionSource: valid ? source : null,
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
        itemKind: common.kind,
        itemPrio: common.prio,
        size: common.size,
        dataAgeMin: common.age,
      );
    }
    return WidgetLaunch(
      target: target,
      itemKind: target == WidgetLaunchTarget.home ? common.kind : null,
      itemPrio: target == WidgetLaunchTarget.home ? common.prio : null,
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
