import 'package:portfolio_assistant/features/genui_core/utils/partial_json.dart';

/// El texto de Porty (`QaAnswerText`) de una respuesta A2UI que todavía se
/// está escribiendo, para mostrarlo mientras llega.
///
/// Solo el texto: las cards con datos (precios, gráficos, noticias) no se
/// muestran a medias. Aparecen recién con la respuesta completa, después de
/// los controles de siempre (sanitizer, grounding, layout), así nunca queda
/// en pantalla un dato que después se corrige.
abstract final class AnswerStreamPreview {
  static const _textComponent = 'QaAnswerText';

  /// Los textos en el orden en que vienen, unidos por un renglón en blanco;
  /// vacío si todavía no hay ninguno (o la ronda pide tools).
  static String textOf(String raw) {
    if (!raw.contains(_textComponent)) return '';
    final texts = <String>[];
    for (final value in PartialJson.values(raw)) {
      final components = _componentsOf(value);
      for (final component in components) {
        final text = _answerText(component);
        if (text != null && text.trim().isNotEmpty) texts.add(text.trim());
      }
    }
    return texts.join('\n\n');
  }

  static List<Map<dynamic, dynamic>> _componentsOf(Object? value) {
    if (value is! Map) return const [];
    final update = value['updateComponents'];
    final list = update is Map ? update['components'] : value['components'];
    return list is List ? list.whereType<Map>().toList() : const [];
  }

  /// `{"component": "QaAnswerText", "text": ...}` (v0.9) o
  /// `{"component": {"QaAnswerText": {"text": ...}}}`.
  static String? _answerText(Map<dynamic, dynamic> component) {
    final kind = component['component'];
    if (kind == _textComponent) {
      final text = component['text'];
      return text is String ? text : null;
    }
    if (kind is Map && kind[_textComponent] is Map) {
      final text = (kind[_textComponent] as Map)['text'];
      return text is String ? text : null;
    }
    return null;
  }
}
