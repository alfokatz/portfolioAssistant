import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/config/supabase/supabase_client_provider.dart';
import 'package:portfolio_assistant/domain/entities/investor_profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Perfil de inversor en Supabase (tabla `investor_profiles`, una fila por
/// usuario) — mismo lugar que la suscripción y la cuota de consultas, así
/// que sobrevive a un reinstall y se comparte entre dispositivos.
class InvestorProfileSupabaseDataSource {
  static const _table = 'investor_profiles';

  InvestorProfileSupabaseDataSource({
    required SupabaseClient client,
    required SupabaseAuthService authService,
  })  : _client = client,
        _authService = authService;

  final SupabaseClient _client;
  final SupabaseAuthService _authService;

  Future<InvestorProfile?> fetch() async {
    final userId = _authService.requireUserId();
    final row = await _client
        .from(_table)
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null) return null;
    return fromRow(Map<String, dynamic>.from(row));
  }

  Future<InvestorProfile> save({
    required RiskTolerance risk,
    required InvestmentHorizon horizon,
    required InvestmentObjective objective,
    InvestmentExperience? experience,
    DrawdownReaction? drawdownReaction,
  }) async {
    final userId = _authService.requireUserId();
    final core = {
      'user_id': userId,
      'risk_tolerance': risk.storageValue,
      'horizon': horizon.storageValue,
      'objective': objective.storageValue,
    };
    final optional = {
      'experience': experience?.storageValue,
      'drawdown_reaction': drawdownReaction?.storageValue,
    };
    Map<String, dynamic> row;
    try {
      row = await _client
          .from(_table)
          .upsert({...core, ...optional})
          .select()
          .single();
    } on PostgrestException catch (e) {
      // Sin la migración 20261007000000 las columnas opcionales no existen
      // (PGRST204): se guarda lo esencial en vez de perder todo el perfil.
      if (e.code != 'PGRST204') rethrow;
      row = await _client.from(_table).upsert(core).select().single();
    }
    final profile = fromRow(Map<String, dynamic>.from(row));
    if (profile == null) {
      throw StateError('investor_profiles returned an unreadable row');
    }
    return profile;
  }

  /// `null` si la fila tiene algún valor que esta versión de la app no
  /// conoce — se trata como perfil faltante en vez de romper.
  static InvestorProfile? fromRow(Map<String, dynamic> row) {
    final risk = RiskTolerance.fromStorage(row['risk_tolerance'] as String?);
    final horizon = InvestmentHorizon.fromStorage(row['horizon'] as String?);
    final objective =
        InvestmentObjective.fromStorage(row['objective'] as String?);
    final updatedAt = DateTime.tryParse(row['updated_at'] as String? ?? '');
    if (risk == null ||
        horizon == null ||
        objective == null ||
        updatedAt == null) {
      return null;
    }
    return InvestorProfile(
      risk: risk,
      horizon: horizon,
      objective: objective,
      updatedAt: updatedAt,
      // Opcionales: ausentes (perfil viejo, o sin la migración) = null.
      experience: InvestmentExperience.fromStorage(
        row['experience'] as String?,
      ),
      drawdownReaction: DrawdownReaction.fromStorage(
        row['drawdown_reaction'] as String?,
      ),
    );
  }
}

final investorProfileSupabaseDataSourceProvider =
    Provider<InvestorProfileSupabaseDataSource>(
  (ref) => InvestorProfileSupabaseDataSource(
    client: ref.watch(supabaseClientProvider),
    authService: ref.watch(supabaseAuthServiceProvider),
  ),
);
