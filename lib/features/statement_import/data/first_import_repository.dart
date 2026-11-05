import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_client_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Resultado de pedir el cupo de la primera importación completa.
enum FirstImportClaim {
  /// El cupo es de esta importación (o es un reintento de la misma).
  granted,

  /// El cupo ya se gastó en otra importación.
  alreadyUsed,
}

/// No se pudo hablar con el servidor (sin red, sin sesión, respuesta rara).
/// Quien llama falla cerrado: no importa por encima del tope.
class FirstImportUnavailable implements Exception {
  const FirstImportUnavailable();
}

/// La primera importación de un Free que pasa el tope de posiciones entra
/// entera, una sola vez (`first_import_status` y `claim_first_import` en
/// Supabase; ver docs/superpowers/specs/2026-11-05-diferenciacion-planes-v2.md
/// §3.2).
abstract class FirstImportStore {
  /// `true` si el cupo todavía no se usó. Lanza [FirstImportUnavailable].
  Future<bool> isAvailable();

  /// Gasta el cupo con [importId] (uno por vista previa; el mismo id es un
  /// reintento). [origin] es `file`, `screenshot` o `note`. Lanza
  /// [FirstImportUnavailable].
  Future<FirstImportClaim> claim({
    required String importId,
    required String origin,
    required int positions,
  });
}

class FirstImportRepository implements FirstImportStore {
  FirstImportRepository({required SupabaseClient? Function() client})
    : _client = client;

  final SupabaseClient? Function() _client;

  SupabaseClient get _signedIn {
    final client = _client();
    if (client == null || client.auth.currentUser == null) {
      throw const FirstImportUnavailable();
    }
    return client;
  }

  @override
  Future<bool> isAvailable() async {
    try {
      final response = await _signedIn.rpc('first_import_status');
      if (response is Map && response['available'] is bool) {
        return response['available'] as bool;
      }
    } on FirstImportUnavailable {
      rethrow;
    } catch (_) {
      // Cae al final: no se pudo saber.
    }
    throw const FirstImportUnavailable();
  }

  @override
  Future<FirstImportClaim> claim({
    required String importId,
    required String origin,
    required int positions,
  }) async {
    try {
      final response = await _signedIn.rpc(
        'claim_first_import',
        params: {
          'p_import_id': importId,
          'p_origin': origin,
          'p_positions': positions,
        },
      );
      if (response is Map) {
        if (response['ok'] == true) return FirstImportClaim.granted;
        if (response['reason'] == 'already_used') {
          return FirstImportClaim.alreadyUsed;
        }
      }
    } on FirstImportUnavailable {
      rethrow;
    } catch (_) {
      // Cae al final: no se pudo saber.
    }
    throw const FirstImportUnavailable();
  }
}

final firstImportRepositoryProvider = Provider<FirstImportStore>(
  (ref) => FirstImportRepository(
    client: () {
      try {
        return ref.read(supabaseClientProvider);
      } catch (_) {
        return null;
      }
    },
  ),
);
