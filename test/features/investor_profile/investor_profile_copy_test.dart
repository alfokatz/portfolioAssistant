import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// El aviso de Porty tiene que nombrar la fila de Ajustes EXACTAMENTE como
/// se ve en pantalla: se arma con las mismas claves que usa la fila
/// (`settings_title` → `settings_investor_profile`). Esto fija ese contrato
/// en los dos idiomas.
String _format(String template, List<String> args) {
  var out = template;
  for (final arg in args) {
    out = out.replaceFirst('{}', arg);
  }
  return out;
}

void main() {
  for (final (file, expectedPath) in [
    ('es-ES', 'Ajustes → Perfil de inversor'),
    ('en-US', 'Settings → Investor profile'),
  ]) {
    test('$file nudges name the exact Settings row', () {
      final json =
          jsonDecode(File('assets/translations/$file.json').readAsStringSync())
              as Map<String, dynamic>;
      final args = [
        json['nav_settings'] as String,
        json['settings_investor_profile'] as String,
      ];
      // La pestaña y el título de la pantalla dicen lo mismo.
      expect(json['settings_title'], json['nav_settings']);
      for (final key in [
        'assistant_profile_nudge_missing',
        'assistant_profile_nudge_stale',
      ]) {
        expect(_format(json[key] as String, args), contains(expectedPath));
      }
    });
  }
}
