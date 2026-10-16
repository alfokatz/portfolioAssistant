import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_client_provider.dart';
import 'package:portfolio_assistant/features/watchlist/domain/watchlist_item.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

sealed class WatchlistFailure implements Exception {
  const WatchlistFailure();
}

/// Llegó al tope de su plan (Free: 0). La base corta con
/// `watchlist_limit_reached`.
class WatchlistLimitReached extends WatchlistFailure {
  const WatchlistLimitReached();
}

class WatchlistDuplicate extends WatchlistFailure {
  const WatchlistDuplicate();
}

class WatchlistUnavailable extends WatchlistFailure {
  const WatchlistUnavailable();
}

/// `watchlist_items` en Supabase (RLS: cada usuario la suya).
class WatchlistRepository {
  WatchlistRepository({required SupabaseClient? Function() client})
    : _client = client;

  final SupabaseClient? Function() _client;

  static const _table = 'watchlist_items';
  static const _columns = 'id, symbol, added_price, notify, created_at';

  SupabaseClient? get _signedIn {
    final client = _client();
    if (client == null || client.auth.currentUser == null) return null;
    return client;
  }

  Future<List<WatchlistItem>> list() async {
    final client = _signedIn;
    if (client == null) return const [];
    try {
      final rows = await client
          .from(_table)
          .select(_columns)
          .order('created_at', ascending: false);
      return [
        for (final r in rows)
          if (WatchlistItem.fromRow(Map<String, dynamic>.from(r))
              case final item?)
            item,
      ];
    } on PostgrestException {
      throw const WatchlistUnavailable();
    }
  }

  Future<WatchlistItem> add(String symbol, {double? price}) async {
    final client = _signedIn;
    if (client == null) throw const WatchlistUnavailable();
    try {
      final row =
          await client
              .from(_table)
              .insert({
                'user_id': client.auth.currentUser!.id,
                'symbol': symbol.trim().toUpperCase(),
                if (price != null && price > 0) 'added_price': price,
              })
              .select(_columns)
              .single();
      return WatchlistItem.fromRow(row) ?? (throw const WatchlistUnavailable());
    } on PostgrestException catch (e) {
      if (e.message.contains('watchlist_limit_reached')) {
        throw const WatchlistLimitReached();
      }
      if (e.code == '23505') throw const WatchlistDuplicate();
      throw const WatchlistUnavailable();
    }
  }

  Future<void> setNotify(String id, {required bool notify}) async {
    final client = _signedIn;
    if (client == null) throw const WatchlistUnavailable();
    try {
      await client.from(_table).update({'notify': notify}).eq('id', id);
    } on PostgrestException {
      throw const WatchlistUnavailable();
    }
  }

  Future<void> remove(String id) async {
    final client = _signedIn;
    if (client == null) throw const WatchlistUnavailable();
    try {
      await client.from(_table).delete().eq('id', id);
    } on PostgrestException {
      throw const WatchlistUnavailable();
    }
  }
}

final watchlistRepositoryProvider = Provider<WatchlistRepository>(
  (ref) => WatchlistRepository(
    client: () {
      try {
        return ref.read(supabaseClientProvider);
      } catch (_) {
        return null;
      }
    },
  ),
);
