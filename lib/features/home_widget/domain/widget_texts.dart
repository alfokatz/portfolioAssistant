import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Los textos del widget en un idioma, leídos directo de los JSON de
/// traducciones (`home_widget_*`). No usa easy_localization: el refresco de
/// fondo corre en otro isolate donde no está inicializado, y el snapshot
/// tiene que salir en el idioma que se le pide, no en el del contexto.
class WidgetTexts {
  const WidgetTexts(this._values, [this._inbox = const {}]);

  /// Solo se quedan las claves `home_widget_*` y `porty_inbox_*` (los
  /// títulos de los avisos de la Home, que el widget reusa tal cual).
  factory WidgetTexts.fromJson(Map<String, Object?> json) => WidgetTexts(
    {
      for (final e in json.entries)
        if (e.key.startsWith(_prefix) && e.value is String)
          e.key.substring(_prefix.length): e.value! as String,
    },
    {
      for (final e in json.entries)
        if (e.key.startsWith(_inboxPrefix) && e.value is String)
          e.key.substring(_inboxPrefix.length): e.value! as String,
    },
  );

  static const _prefix = 'home_widget_';
  static const _inboxPrefix = 'porty_inbox_';

  final Map<String, String> _values;
  final Map<String, String> _inbox;

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

  /// El texto de `porty_inbox_<key>` (los avisos de la Home) con `{nombre}`
  /// reemplazados por [args]. Mismas claves que usa la Home, sin `.tr()`.
  String getInbox(String key, [Map<String, String> args = const {}]) {
    var text = _inbox[key] ?? key;
    args.forEach((name, value) => text = text.replaceAll('{$name}', value));
    return text;
  }

  /// Abreviaturas de los 12 meses, en orden.
  List<String> get months => get('months').split(',');
}
