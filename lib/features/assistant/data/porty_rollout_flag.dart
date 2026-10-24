import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Un interruptor de Porty que se prende por usuario desde el servidor, sin
/// publicar la app: una fila de `app_config` ([key]) con
///
/// ```json
/// {"percent": 0, "users": ["<uuid>", ...]}
/// ```
///
/// - `users`: siempre prendido para esos usuarios (para probarlo antes);
/// - `percent` (0-100): qué parte del resto lo tiene. Cada usuario cae
///   siempre en el mismo grupo (hash de su id, como `GPT6_ROLLOUT_PERCENT`).
///
/// Falla cerrado: sin red, sin la fila o con un valor raro, apagado (lo de
/// siempre).
class PortyRolloutFlag {
  PortyRolloutFlag(
    this.key, {
    Future<Object?> Function()? read,
    this.ttl = const Duration(minutes: 10),
  }) : _read = read ?? (() => _readFromSupabase(key));

  /// La respuesta en streaming (el texto aparece mientras se escribe).
  static final streaming = PortyRolloutFlag('porty_streaming');

  /// El prompt lean (`PromptVariant.lean`): lo que cada área necesita
  /// después de traer sus datos viaja con el resultado de la tool.
  static final leanPrompt = PortyRolloutFlag('porty_lean_prompt');

  /// La fila de `app_config`.
  final String key;

  final Future<Object?> Function() _read;
  final Duration ttl;

  Object? _value;
  DateTime? _readAt;
  Future<Object?>? _inFlight;

  /// Si [userId] lo tiene prendido. Nunca tira.
  Future<bool> enabledFor(String? userId) async {
    if (userId == null || userId.isEmpty) return false;
    return isEnabled(await _load(), userId);
  }

  @visibleForTesting
  static bool isEnabled(Object? value, String userId) {
    if (value is! Map) return false;
    final users = value['users'];
    if (users is List && users.contains(userId)) return true;
    final percent = value['percent'];
    if (percent is! num) return false;
    return bucket(userId) < percent.clamp(0, 100);
  }

  /// 0-99, estable por usuario (FNV-1a del id, igual que `rolloutBucket`
  /// del proxy `ai-chat`).
  @visibleForTesting
  static int bucket(String userId) {
    var h = 0x811c9dc5;
    for (final unit in userId.codeUnits) {
      h ^= unit;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h % 100;
  }

  Future<Object?> _load() {
    final readAt = _readAt;
    if (readAt != null && DateTime.now().difference(readAt) < ttl) {
      return Future.value(_value);
    }
    return _inFlight ??= _fetch().whenComplete(() => _inFlight = null);
  }

  Future<Object?> _fetch() async {
    try {
      _value = await _read().timeout(const Duration(seconds: 4));
      _readAt = DateTime.now();
    } catch (e) {
      if (kDebugMode) debugPrint('[PortyRolloutFlag] $key off: $e');
    }
    return _value;
  }

  static Future<Object?> _readFromSupabase(String key) async {
    final row =
        await Supabase.instance.client
            .from('app_config')
            .select('value')
            .eq('key', key)
            .maybeSingle();
    return row?['value'];
  }
}
