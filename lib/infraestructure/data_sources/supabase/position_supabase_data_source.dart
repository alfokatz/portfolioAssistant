import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/config/supabase/supabase_client_provider.dart';
import 'package:portfolio_assistant/domain/data_sources/position_remote_data_source.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/supabase/supabase_portfolio_mapper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PositionSupabaseDataSource implements PositionRemoteDataSource {
  static const _table = 'positions';

  final SupabaseClient _client;
  final SupabaseAuthService _authService;

  PositionSupabaseDataSource({
    required SupabaseClient client,
    required SupabaseAuthService authService,
  })  : _client = client,
        _authService = authService;

  @override
  Future<List<Position>> getAll() async {
    final response = await _client
        .from(_table)
        .select()
        .order('purchase_date', ascending: false);

    return (response as List)
        .map((row) => SupabasePortfolioMapper.positionFromRow(
              Map<String, dynamic>.from(row as Map),
            ))
        .toList();
  }

  @override
  Future<Position?> getById(String id) async {
    final response = await _client
        .from(_table)
        .select()
        .eq('id', id)
        .maybeSingle();

    if (response == null) return null;
    return SupabasePortfolioMapper.positionFromRow(
      Map<String, dynamic>.from(response),
    );
  }

  @override
  Future<void> save(Position position) async {
    final userId = _authService.requireUserId();
    await _client.from(_table).upsert(
          SupabasePortfolioMapper.positionToRow(
            position: position,
            userId: userId,
          ),
        );
  }

  @override
  Future<void> delete(String id) async {
    await _client.from(_table).delete().eq('id', id);
  }

  @override
  Future<void> deleteByTicker(String ticker) async {
    await _client.from(_table).delete().eq('ticker', ticker);
  }
}

final positionRemoteDataSourceProvider = Provider<PositionRemoteDataSource>(
  (ref) => PositionSupabaseDataSource(
    client: ref.watch(supabaseClientProvider),
    authService: ref.watch(supabaseAuthServiceProvider),
  ),
);
