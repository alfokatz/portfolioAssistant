import 'dart:convert';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/services.dart';
import 'dart:ui' show Locale;

class RemoteConfigAssetLoader extends AssetLoader {
  final FirebaseRemoteConfig _remoteConfig;

  RemoteConfigAssetLoader({FirebaseRemoteConfig? remoteConfig})
    : _remoteConfig = remoteConfig ?? FirebaseRemoteConfig.instance {
    // Valores por defecto desde assets/locales/*.json
    _remoteConfig.setDefaults(<String, dynamic>{
      'translations_en': rootBundle.loadString(
        'assets/translations/en-EN.json',
      ),
      'translations_es': rootBundle.loadString(
        'assets/translations/es-ES.json',
      ),
    });
  }

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    // 1. Obtener y activar valores de Remote Config
    await _remoteConfig.fetch();
    await _remoteConfig.activate();

    // 2. Leer el JSON para el idioma solicitado
    final key = 'translations_${locale.languageCode}';
    String jsonString = _remoteConfig.getString(key);

    // 3. Si no llegó nada o está vacío, cargar local de fallback
    if (jsonString.isEmpty) {
      jsonString = await rootBundle.loadString(
        'assets/translations/${locale.languageCode}.json',
      );
    }

    // 4. Parsear y devolver
    return json.decode(jsonString) as Map<String, dynamic>;
  }
}
