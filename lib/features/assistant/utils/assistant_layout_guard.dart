import 'dart:convert';

/// Hace cumplir la regla de LAYOUT de Porty sobre el A2UI ya normalizado:
/// el Column raíz lleva QaAnswerText, UN widget de datos y QaTipBanner.
/// Excepciones (composiciones diseñadas como tales):
/// - QaNewsSummary acompañando a un widget de precio ("por qué se movió").
/// - Hasta [maxInvestOptions] QaInvestOption: pedir ideas nombra varios
///   candidatos en el texto, y cada uno necesita su card (antes se veía
///   solo el primero, aunque el texto hablara de tres).
/// - QaGoalCard + un QaProjectionStrip: la meta sin el ahorro mensual
///   necesario deja la respuesta a medias.
///
/// Está en el prompt, pero gpt-4.1-mini a veces igual suma un gráfico por
/// ticker a una comparación, o tres widgets de proyección juntos (medido en
/// evals: ~1 de cada 3). Es una regla de producto (así está diseñada la
/// pantalla), así que se garantiza acá en vez de depender del modelo.
abstract final class AssistantLayoutGuard {
  static const _nonData = {'QaAnswerText', 'QaTipBanner', 'Text'};
  static const _priceWidgets = {
    'QaPriceChart',
    'QaTickerMove',
    'QaTickerSnapshot',
    'QaPeriodChange',
  };

  static const maxInvestOptions = 3;

  static String enforce(String normalized) {
    final lines = normalized.split('\n');
    final out = <String>[];
    for (final line in lines) {
      out.add(_enforceLine(line));
    }
    return out.join('\n');
  }

  static String _enforceLine(String line) {
    final Map<String, dynamic> message;
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map<String, dynamic>) return line;
      message = decoded;
    } catch (_) {
      return line;
    }
    final update = message['updateComponents'];
    if (update is! Map<String, dynamic>) return line;
    final components = update['components'];
    if (components is! List) return line;

    final byId = <String, Map<String, dynamic>>{
      for (final c in components.whereType<Map<String, dynamic>>())
        if (c['id'] is String) c['id'] as String: c,
    };
    final root = byId['root'];
    final children = root?['children'];
    if (root == null || root['component'] != 'Column' || children is! List) {
      return line;
    }

    final kept = <String>[];
    final dropped = <String>{};
    String? primary;
    int count(String type) =>
        kept.where((k) => byId[k]?['component'] == type).length;
    for (final id in children.whereType<String>()) {
      final type = byId[id]?['component'];
      if (type == null || _nonData.contains(type)) {
        kept.add(id);
      } else if (primary == null) {
        primary = type as String;
        kept.add(id);
      } else if (type == 'QaNewsSummary' &&
          _priceWidgets.contains(primary) &&
          count('QaNewsSummary') == 0) {
        kept.add(id);
      } else if (type == 'QaInvestOption' &&
          primary == 'QaInvestOption' &&
          count('QaInvestOption') < maxInvestOptions) {
        kept.add(id);
      } else if (type == 'QaProjectionStrip' &&
          primary == 'QaGoalCard' &&
          count('QaProjectionStrip') == 0) {
        kept.add(id);
      } else {
        dropped.add(id);
      }
    }
    if (dropped.isEmpty) return line;

    root['children'] = kept;
    update['components'] = [
      for (final c in components)
        if (c is! Map || !dropped.contains(c['id'])) c,
    ];
    return jsonEncode(message);
  }
}
