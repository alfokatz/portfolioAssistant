import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_client_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Falla al leer o borrar las posiciones cargadas a mano.
class ManualPositionsException implements Exception {
  const ManualPositionsException();
}

/// Las posiciones ABIERTAS cargadas a mano (`source = 'manual'`), para
/// reemplazarlas por lo importado de un bróker. Las ventas cargadas a mano
/// (`closed_positions`) no se tocan.
class ManualPositionsRepository {
  ManualPositionsRepository({required SupabaseClient? Function() client})
    : _client = client;

  final SupabaseClient? Function() _client;

  /// Cuántas acciones distintas tiene cargadas a mano (0 sin sesión).
  Future<int> countTickers() async {
    final client = _client();
    final user = client?.auth.currentUser;
    if (client == null || user == null) return 0;
    try {
      final rows = await client
          .from('positions')
          .select('ticker')
          .eq('user_id', user.id)
          .eq('source', 'manual');
      return {for (final r in rows) '${r['ticker']}'.toUpperCase()}.length;
    } on PostgrestException {
      throw const ManualPositionsException();
    }
  }

  /// Borra todas las abiertas cargadas a mano. Lo importado no se toca (la
  /// base además lo impide).
  Future<void> deleteAll() async {
    final client = _client();
    final user = client?.auth.currentUser;
    if (client == null || user == null) return;
    try {
      await client
          .from('positions')
          .delete()
          .eq('user_id', user.id)
          .eq('source', 'manual');
    } on PostgrestException {
      throw const ManualPositionsException();
    }
  }
}

final manualPositionsRepositoryProvider = Provider<ManualPositionsRepository>(
  (ref) => ManualPositionsRepository(
    client: () {
      try {
        return ref.read(supabaseClientProvider);
      } catch (_) {
        return null;
      }
    },
  ),
);
