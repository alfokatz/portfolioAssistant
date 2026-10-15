// La app no puede llevar secretos: todo lo que está en `lib/` o en los
// assets declarados en pubspec termina dentro del binario y se extrae en
// minutos. Las keys de OpenAI y Finnhub viven en los secrets de las edge
// functions (`ai-chat`, `finnhub`); la app solo conoce la URL de Supabase y
// su anon key (pública por diseño).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _forbiddenNames = RegExp(
  r'OPENAI_API_KEY|FINNHUB_API_KEY|REVENUECAT_SECRET_API_KEY|'
  r'REVENUECAT_WEBHOOK_SECRET|SERVICE_ROLE_KEY',
);
final _secretShapes = <String, RegExp>{
  'OpenAI key': RegExp(r'sk-(proj-|svcacct-)?[A-Za-z0-9_-]{20,}'),
  'RevenueCat secret key': RegExp(r'\bsk_[A-Za-z0-9]{20,}'),
  'Supabase secret key': RegExp(r'sb_secret_[A-Za-z0-9_-]{10,}'),
  'OpenAI host': RegExp(r'api\.openai\.com'),
  'Finnhub host': RegExp(r'finnhub\.io'),
};

/// Directorios/archivos que `flutter build` mete en el bundle.
List<File> _bundledFiles() {
  final pubspec = File('pubspec.yaml').readAsLinesSync();
  final start = pubspec.indexWhere((l) => l.trim() == 'assets:');
  final assets = <String>[];
  for (final line in pubspec.skip(start + 1)) {
    final m = RegExp(r'^\s+-\s+(\S+)').firstMatch(line);
    if (m == null) break;
    assets.add(m.group(1)!);
  }
  final files = <File>[];
  for (final path in ['lib/', ...assets]) {
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.directory) {
      files.addAll(
        Directory(path).listSync(recursive: true).whereType<File>(),
      );
    } else if (type == FileSystemEntityType.file) {
      files.add(File(path));
    }
  }
  return files;
}

void main() {
  test('nothing bundled in the app contains a server secret', () {
    final problems = <String>[];
    for (final file in _bundledFiles()) {
      final String text;
      try {
        text = file.readAsStringSync();
      } on FileSystemException {
        continue; // binario (imágenes, fuentes)
      }
      if (_forbiddenNames.hasMatch(text)) {
        problems.add('${file.path}: nombra un secreto del servidor');
      }
      for (final MapEntry(key: label, value: re) in _secretShapes.entries) {
        if (re.hasMatch(text)) problems.add('${file.path}: $label');
      }
    }
    expect(problems, isEmpty);
  });
}
