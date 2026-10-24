import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_client_provider.dart';
import 'package:portfolio_assistant/features/porty_memory/domain/porty_topic.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// `porty_topics` en Supabase (RLS: cada usuario los suyos). Se escribe solo
/// por `porty_topics_touch`, que actualiza los repetidos y deja los 50 más
/// recientes.
class PortyTopicsRepository {
  PortyTopicsRepository({required SupabaseClient? Function() client})
    : _client = client;

  final SupabaseClient? Function() _client;

  static const _table = 'porty_topics';

  SupabaseClient? get _signedIn {
    final client = _client();
    if (client == null || client.auth.currentUser == null) return null;
    return client;
  }

  /// Los más recientes primero. Sin sesión, nada.
  Future<List<PortyTopic>> list() async {
    final client = _signedIn;
    if (client == null) return const [];
    final rows = await client
        .from(_table)
        .select('ticker, question, price_at, held, last_asked_at, times')
        .order('last_asked_at', ascending: false);
    return [
      for (final r in rows) PortyTopic.fromRow(Map<String, dynamic>.from(r)),
    ].whereType<PortyTopic>().toList();
  }

  Future<void> touch(List<PortyTopicDraft> drafts) async {
    final client = _signedIn;
    if (client == null || drafts.isEmpty) return;
    await client.rpc(
      'porty_topics_touch',
      params: {
        'p_topics': [for (final d in drafts) d.toJson()],
      },
    );
  }

  Future<void> delete(String ticker) async {
    final client = _signedIn;
    if (client == null) return;
    await client.from(_table).delete().eq('ticker', ticker);
  }

  Future<void> deleteAll() async {
    final client = _signedIn;
    if (client == null) return;
    await client
        .from(_table)
        .delete()
        .eq('user_id', client.auth.currentUser!.id);
  }
}

final portyTopicsRepositoryProvider = Provider<PortyTopicsRepository>(
  (ref) => PortyTopicsRepository(
    // Sin Supabase inicializado (tests de otras pantallas): sin sesión.
    client: () {
      try {
        return ref.read(supabaseClientProvider);
      } catch (_) {
        return null;
      }
    },
  ),
);
