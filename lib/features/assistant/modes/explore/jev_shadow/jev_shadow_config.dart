import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Gate único del experimento de shadow-mode de Jev/TypeSafe (routing de
/// widgets en modo Explore, comparado contra la elección real de
/// gpt-4.1-mini — ver `JevShadowRunner`).
///
/// A propósito nunca corre fuera de debug builds, sin importar qué haya en
/// el `.env`: mientras se evalúa este vendor nuevo, ningún mensaje ni
/// snapshot de portfolio de un usuario real de producción debe llegar a
/// TypeSafe. El tráfico "real" de este experimento es el que generes vos
/// mismo usando la app en un build de debug con `TYPESAFE_API_KEY` seteada.
abstract final class JevShadowConfig {
  static String? get _rawKey {
    final key = dotenv.env['TYPESAFE_API_KEY'];
    return (key == null || key.isEmpty) ? null : key;
  }

  static bool get isEnabled => kDebugMode && _rawKey != null;

  static String get apiKey => _rawKey ?? '';
}
