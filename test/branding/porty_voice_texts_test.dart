// La app habla como Porty: ningún texto dice "IA"/"AI" (ni "inteligencia
// artificial") ni usa la raya larga (—) típica de los textos generados.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Iterable<MapEntry<String, String>> _strings(
  Map<String, dynamic> map, [
  String prefix = '',
]) sync* {
  for (final e in map.entries) {
    final key = '$prefix${e.key}';
    final value = e.value;
    if (value is String) yield MapEntry(key, value);
    if (value is Map<String, dynamic>) yield* _strings(value, '$key.');
  }
}

void main() {
  final aiWord = RegExp(
    r'\b(IA|AI|A\.I\.)\b|inteligencia artificial|artificial intelligence',
    caseSensitive: false,
  );

  for (final file in ['es-ES', 'en-US']) {
    test('$file: no text says AI or uses the long dash', () {
      final map =
          jsonDecode(File('assets/translations/$file.json').readAsStringSync())
              as Map<String, dynamic>;
      final offenders = [
        for (final e in _strings(map))
          if (e.value.contains('—') || aiWord.hasMatch(e.value))
            '${e.key}: ${e.value}',
      ];
      expect(offenders, isEmpty);
    });
  }
}
