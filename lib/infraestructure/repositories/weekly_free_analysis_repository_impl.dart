import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/config/supabase/supabase_client_provider.dart';
import 'package:portfolio_assistant/domain/repositories/weekly_free_analysis_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// RPCs `weekly_free_analysis_status` / `consume_weekly_free_analysis`
/// (migración 20260930000000_weekly_free_analysis.sql). Nunca lanza.
class WeeklyFreeAnalysisRepositoryImpl implements WeeklyFreeAnalysisRepository {
  WeeklyFreeAnalysisRepositoryImpl({
    required SupabaseClient client,
    required SupabaseAuthService authService,
  }) : _client = client,
       _authService = authService;

  final SupabaseClient _client;
  final SupabaseAuthService _authService;

  @override
  Future<bool> isAvailable(String weekStart) async {
    try {
      _authService.requireUserId();
      final response = await _client.rpc(
        'weekly_free_analysis_status',
        params: {'p_week_start': weekStart},
      );
      return response is Map && response['available'] == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> consume(String weekStart, {String? ticker}) async {
    try {
      _authService.requireUserId();
      final response = await _client.rpc(
        'consume_weekly_free_analysis',
        params: {'p_week_start': weekStart, 'p_ticker': ticker},
      );
      return response is Map && response['ok'] == true;
    } catch (_) {
      return false;
    }
  }
}

final weeklyFreeAnalysisRepositoryProvider =
    Provider<WeeklyFreeAnalysisRepository>(
      (ref) => WeeklyFreeAnalysisRepositoryImpl(
        client: ref.watch(supabaseClientProvider),
        authService: ref.watch(supabaseAuthServiceProvider),
      ),
    );
