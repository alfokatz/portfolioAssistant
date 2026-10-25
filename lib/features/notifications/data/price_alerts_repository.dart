import 'dart:convert';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_client_provider.dart';
import 'package:portfolio_assistant/features/notifications/domain/price_alert.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// `price_alerts` en Supabase (RLS: cada usuario las suyas). El tope por
/// plan lo controla un trigger, que corta con `alert_limit_reached`.
class PriceAlertsRepository {
  PriceAlertsRepository({required SupabaseClient? Function() client})
    : _client = client;

  final SupabaseClient? Function() _client;

  static const _columns =
      'id, symbol, condition, target, reference_price, repeat, status, '
      'paused_reason, last_price, triggered_at, triggered_price, created_at';

  SupabaseClient? get _signedIn {
    final client = _client();
    if (client == null || client.auth.currentUser == null) return null;
    return client;
  }

  Future<List<PriceAlert>> list() async {
    final client = _signedIn;
    if (client == null) return const [];
    final rows = await client
        .from('price_alerts')
        .select(_columns)
        .order('created_at', ascending: false);
    return [
      for (final r in rows) PriceAlert.fromRow(Map<String, dynamic>.from(r)),
    ];
  }

  Future<PriceAlert> create(PriceAlertDraft draft) async {
    final client = _signedIn;
    if (client == null) throw const PriceAlertNetworkError();
    try {
      final row =
          await client
              .from('price_alerts')
              .insert({
                'user_id': client.auth.currentUser!.id,
                'symbol': draft.symbol.trim().toUpperCase(),
                'condition': draft.condition.storage,
                'target': draft.target,
                'reference_price': draft.referencePrice,
                'repeat': draft.repeatDaily ? 'daily' : 'once',
                'source': draft.source,
              })
              .select(_columns)
              .single();
      return PriceAlert.fromRow(row);
    } on PostgrestException catch (e) {
      throw mapError(e);
    }
  }

  /// Activa (o rearma una cumplida) o pausa.
  Future<void> setActive(String id, {required bool active}) async {
    final client = _signedIn;
    if (client == null) throw const PriceAlertNetworkError();
    try {
      await client
          .from('price_alerts')
          .update({'status': active ? 'active' : 'paused'})
          .eq('id', id);
    } on PostgrestException catch (e) {
      throw mapError(e);
    }
  }

  Future<void> delete(String id) async {
    final client = _signedIn;
    if (client == null) throw const PriceAlertNetworkError();
    await client.from('price_alerts').delete().eq('id', id);
  }

  static PriceAlertFailure mapError(PostgrestException e) {
    if (e.message.contains('alert_limit_reached')) {
      int? limit;
      try {
        final details = jsonDecode('${e.details ?? ''}');
        if (details is Map && details['limit'] is num) {
          limit = (details['limit'] as num).toInt();
        }
      } catch (_) {}
      return PriceAlertLimitReached(limit);
    }
    // 23514: check (símbolo o objetivo inválido).
    if (e.code == '23514' || e.code == '22023') return const PriceAlertInvalid();
    return const PriceAlertNetworkError();
  }
}

final priceAlertsRepositoryProvider = Provider<PriceAlertsRepository>(
  (ref) => PriceAlertsRepository(
    client: () {
      try {
        return ref.read(supabaseClientProvider);
      } catch (_) {
        return null;
      }
    },
  ),
);
