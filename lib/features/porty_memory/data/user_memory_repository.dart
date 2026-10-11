import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_client_provider.dart';
import 'package:portfolio_assistant/features/porty_memory/domain/user_memory.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// `user_memories` en Supabase (RLS: cada usuario las suyas). El tope por
/// usuario lo controla un trigger, que corta con `user_memory_limit_reached`.
class UserMemoryRepository {
  UserMemoryRepository({required SupabaseClient? Function() client})
    : _client = client;

  final SupabaseClient? Function() _client;

  static const _table = 'user_memories';
  static const _columns = 'id, content, category, source, updated_at';

  SupabaseClient? get _signedIn {
    final client = _client();
    if (client == null || client.auth.currentUser == null) return null;
    return client;
  }

  /// Las más recientes primero.
  Future<List<UserMemory>> list() async {
    final client = _signedIn;
    if (client == null) return const [];
    final rows = await client
        .from(_table)
        .select(_columns)
        .order('updated_at', ascending: false);
    return [
      for (final r in rows) UserMemory.fromRow(Map<String, dynamic>.from(r)),
    ].whereType<UserMemory>().toList();
  }

  Future<UserMemory> create({
    required String content,
    required UserMemoryCategory category,
    required UserMemorySource source,
  }) async {
    final client = _signedIn;
    if (client == null) throw const UserMemoryUnavailable();
    try {
      final row =
          await client
              .from(_table)
              .insert({
                'user_id': client.auth.currentUser!.id,
                'content': _clip(content),
                'category': category.storageValue,
                'source': source.storageValue,
              })
              .select(_columns)
              .single();
      return UserMemory.fromRow(row) ?? (throw const UserMemoryUnavailable());
    } on PostgrestException catch (e) {
      throw _map(e);
    }
  }

  /// Reemplaza el texto (y la categoría) de un dato: cuando algo cambió
  /// ("ahora ahorro 300 por mes") en vez de sumar uno contradictorio.
  Future<UserMemory> update(
    String id, {
    required String content,
    required UserMemoryCategory category,
  }) async {
    final client = _signedIn;
    if (client == null) throw const UserMemoryUnavailable();
    try {
      final row =
          await client
              .from(_table)
              .update({
                'content': _clip(content),
                'category': category.storageValue,
              })
              .eq('id', id)
              .select(_columns)
              .single();
      return UserMemory.fromRow(row) ?? (throw const UserMemoryUnavailable());
    } on PostgrestException catch (e) {
      throw _map(e);
    }
  }

  Future<void> delete(String id) async {
    final client = _signedIn;
    if (client == null) throw const UserMemoryUnavailable();
    await client.from(_table).delete().eq('id', id);
  }

  Future<void> deleteAll() async {
    final client = _signedIn;
    if (client == null) throw const UserMemoryUnavailable();
    await client
        .from(_table)
        .delete()
        .eq('user_id', client.auth.currentUser!.id);
  }

  static String _clip(String content) {
    final trimmed = content.trim();
    return trimmed.length <= UserMemory.maxLength
        ? trimmed
        : trimmed.substring(0, UserMemory.maxLength);
  }

  static UserMemoryFailure _map(PostgrestException e) =>
      e.message.contains('user_memory_limit_reached')
          ? const UserMemoryLimitReached()
          : const UserMemoryUnavailable();
}

final userMemoryRepositoryProvider = Provider<UserMemoryRepository>(
  (ref) => UserMemoryRepository(
    client: () {
      try {
        return ref.read(supabaseClientProvider);
      } catch (_) {
        return null;
      }
    },
  ),
);
