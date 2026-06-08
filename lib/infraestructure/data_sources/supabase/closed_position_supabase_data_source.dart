import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/config/supabase/supabase_client_provider.dart';
import 'package:portfolio_assistant/domain/data_sources/closed_position_remote_data_source.dart';
import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/supabase/supabase_portfolio_mapper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ClosedPositionSupabaseDataSource implements ClosedPositionRemoteDataSource {
  static const _table = 'closed_positions';

  final SupabaseClient _client;
  final SupabaseAuthService _authService;

  ClosedPositionSupabaseDataSource({
    required SupabaseClient client,
    required SupabaseAuthService authService,
  })  : _client = client,
        _authService = authService;

  @override
  Future<List<ClosedPosition>> getAll() async {
    final response = await _client
        .from(_table)
        .select()
        .order('closed_at', ascending: false);

    return (response as List)
        .map((row) => SupabasePortfolioMapper.closedPositionFromRow(
              Map<String, dynamic>.from(row as Map),
            ))
        .toList();
  }

  @override
  Future<void> save(
    ClosedPosition position, {
    String? sourcePositionId,
  }) async {
    final userId = _authService.requireUserId();
    await _client.from(_table).insert(
          SupabasePortfolioMapper.closedPositionToRow(
            position: position,
            userId: userId,
            sourcePositionId: sourcePositionId,
          ),
        );
  }
}

final closedPositionRemoteDataSourceProvider =
    Provider<ClosedPositionRemoteDataSource>(
  (ref) => ClosedPositionSupabaseDataSource(
    client: ref.watch(supabaseClientProvider),
    authService: ref.watch(supabaseAuthServiceProvider),
  ),
);
