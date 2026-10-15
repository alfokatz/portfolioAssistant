import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// La app se llama Porty. Ningún texto que ve el usuario puede seguir
/// diciendo el nombre viejo. Los identificadores técnicos (paquete Dart
/// `portfolio_assistant`, bundle id, applicationId, dominio de los links
/// legales) no son texto visible y no entran en este chequeo.
final _oldName = RegExp(r'PortfolioAI|PortfolioAssistant|Portfolio Assistant');

/// Archivos de textos visibles: traducciones y nombres de la app por
/// plataforma.
const _userFacingFiles = [
  'assets/translations/es-ES.json',
  'assets/translations/en-US.json',
  'ios/Runner/Info.plist',
  'android/app/src/main/AndroidManifest.xml',
  'web/manifest.json',
  'web/index.html',
];

List<String> _hits(String path, String content) => [
  for (final (i, line) in content.split('\n').indexed)
    if (_oldName.hasMatch(line)) '$path:${i + 1}: ${line.trim()}',
];

void main() {
  test('translations and platform app names never show the old name', () {
    final hits = [
      for (final path in _userFacingFiles)
        ..._hits(path, File(path).readAsStringSync()),
    ];
    expect(hits, isEmpty, reason: hits.join('\n'));
  });

  test('no Dart string in lib/ shows the old name', () {
    final hits = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final lines = file.readAsLinesSync().where(
        (l) => !l.trimLeft().startsWith('import ') && !l.contains('package:'),
      );
      hits.addAll(_hits(file.path, lines.join('\n')));
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });

  test('the visible app name is Porty on iOS and Android', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(
      plist,
      contains('<key>CFBundleDisplayName</key>\n\t<string>Porty</string>'),
    );
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android:label="Porty"'));
  });
}
