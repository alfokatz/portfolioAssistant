import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/config/supabase/supabase_client_provider.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/report_week.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/weekly_report_claim.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Dónde se reserva y guarda el informe de cada semana.
abstract class WeeklyReportStore {
  Future<WeeklyReportClaim> claim(ReportWeek week);
  Future<bool> complete(ReportWeek week, Map<String, Object?> payload);
  Future<void> fail(ReportWeek week);
}

/// RPCs del informe semanal: `claim_weekly_report`, `complete_weekly_report`
/// y `fail_weekly_report` (migración 20261002120000_weekly_reports.sql).
/// Nunca lanza.
class WeeklyReportRepository implements WeeklyReportStore {
  WeeklyReportRepository({
    required SupabaseClient client,
    required SupabaseAuthService authService,
  }) : _client = client,
       _authService = authService;

  final SupabaseClient _client;
  final SupabaseAuthService _authService;

  @override
  Future<WeeklyReportClaim> claim(ReportWeek week) async {
    try {
      _authService.requireUserId();
      final response = await _client.rpc(
        'claim_weekly_report',
        params: {'p_week_start': week.key},
      );
      return WeeklyReportClaim.parse(response);
    } catch (_) {
      return const ClaimUnavailable();
    }
  }

  /// `false` si el servidor no lo aceptó (sin claim, payload inválido).
  @override
  Future<bool> complete(ReportWeek week, Map<String, Object?> payload) async {
    try {
      _authService.requireUserId();
      final response = await _client.rpc(
        'complete_weekly_report',
        params: {'p_week_start': week.key, 'p_payload': payload},
      );
      return response is Map && response['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Libera el claim para reintentar sin esperar a que venza.
  @override
  Future<void> fail(ReportWeek week) async {
    try {
      _authService.requireUserId();
      await _client.rpc(
        'fail_weekly_report',
        params: {'p_week_start': week.key},
      );
    } catch (_) {
      // Si no llega, el claim vence solo a los 2 minutos.
    }
  }
}

final weeklyReportRepositoryProvider = Provider<WeeklyReportStore>(
  (ref) => WeeklyReportRepository(
    client: ref.watch(supabaseClientProvider),
    authService: ref.watch(supabaseAuthServiceProvider),
  ),
);
