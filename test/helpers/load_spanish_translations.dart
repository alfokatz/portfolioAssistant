import 'dart:convert';
import 'dart:io';
import 'dart:ui';

// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart';

/// Carga los textos en español de la app para los tests de las cards del
/// chat (que escriben sus textos con claves `qa_*`). Se usa desde los
/// `flutter_test_config.dart` de `test/features/assistant`,
/// `test/features/genui_core` y `test/genui`.
void loadSpanishTranslations() => Localization.load(
  const Locale('es', 'ES'),
  translations: Translations(
    jsonDecode(File('assets/translations/es-ES.json').readAsStringSync())
        as Map<String, dynamic>,
  ),
  ignorePluralRules: false,
);
