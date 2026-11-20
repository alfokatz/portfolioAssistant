import 'dart:async';

import '../helpers/load_spanish_translations.dart';

/// Los tests de esta carpeta ven la app en español (los textos de las cards
/// salen de claves `qa_*`).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  loadSpanishTranslations();
  await testMain();
}
