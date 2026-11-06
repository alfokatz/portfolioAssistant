import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Los textos del widget en un idioma, leídos directo de los JSON de
/// traducciones (`home_widget_*`). No usa easy_localization: el refresco de
/// fondo corre en otro isolate donde no está inicializado, y el snapshot
/// tiene que salir en el idioma que se le pide, no en el del contexto.
class WidgetTexts {
  const WidgetTexts(this._values);

  /// Solo se quedan las claves `home_widget_*`.
  factory WidgetTexts.fromJson(Map<String, Object?> json) => WidgetTexts({
    for (final e in json.entries)
      if (e.key.startsWith(_prefix) && e.value is String)
        e.key.substring(_prefix.length): e.value! as String,
  });

  static const _prefix = 'home_widget_';

  final Map<String, String> _values;

  static const _files = {
    'es': 'assets/translations/es-ES.json',
    'en': 'assets/translations/en-US.json',
  };

  /// Lee el asset del idioma ('es' | 'en'; cualquier otro, español).
  static Future<WidgetTexts> load(String lang) async {
    final raw = await rootBundle.loadString(_files[lang] ?? _files['es']!);
    return WidgetTexts.fromJson(jsonDecode(raw) as Map<String, Object?>);
  }

  /// El texto de `home_widget_<key>` con `{nombre}` reemplazados por [args].
  /// Una clave que falta es un bug de traducciones: lo dice el test.
  String get(String key, [Map<String, String> args = const {}]) {
    var text = _values[key] ?? key;
    args.forEach((name, value) => text = text.replaceAll('{$name}', value));
    return text;
  }

  /// Abreviaturas de los 12 meses, en orden.
  List<String> get months => get('months').split(',');
}
