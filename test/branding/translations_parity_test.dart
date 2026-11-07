// es-ES y en-US tienen que tener las mismas keys: una key en uno solo se ve
// como la key cruda ("genui_chip_market_today") en el otro idioma.
//
//   flutter test test/branding/translations_parity_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Set<String> _keys(String path) {
  final json = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  final out = <String>{};
  void walk(Map<String, dynamic> map, String prefix) {
    for (final entry in map.entries) {
      final key = '$prefix${entry.key}';
      final value = entry.value;
      if (value is Map<String, dynamic>) {
        walk(value, '$key.');
      } else {
        out.add(key);
      }
    }
  }

  walk(json, '');
  return out;
}

void main() {
  test('es-ES and en-US have the same translation keys', () {
    final es = _keys('assets/translations/es-ES.json');
    final en = _keys('assets/translations/en-US.json');

    expect(es.difference(en), isEmpty, reason: 'keys missing in en-US.json');
    expect(en.difference(es), isEmpty, reason: 'keys missing in es-ES.json');
  });
}
