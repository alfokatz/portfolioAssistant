import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/domain/entities/investor_profile.dart';
import 'package:portfolio_assistant/domain/repositories/investor_profile_repository.dart';
import 'package:portfolio_assistant/infraestructure/repositories/investor_profile_repository_impl.dart';

/// Estado del perfil respecto de lo que Porty necesita para una sugerencia.
enum InvestorProfileStatus { missing, complete, stale }

class InvestorProfileState {
  const InvestorProfileState({
    this.profile,
    this.isLoading = false,
    this.hasLoaded = false,
  });

  final InvestorProfile? profile;
  final bool isLoading;

  /// `true` después del primer fetch exitoso. Antes de eso `profile == null`
  /// significa "no sé", no "no tiene".
  final bool hasLoaded;

  InvestorProfileStatus statusAt(DateTime now) {
    final current = profile;
    if (current == null) return InvestorProfileStatus.missing;
    return current.isStaleAt(now)
        ? InvestorProfileStatus.stale
        : InvestorProfileStatus.complete;
  }
}

/// Único dueño del perfil en memoria: lo leen la fila de Ajustes, la
/// pantalla del perfil y los motores Invertir/Planificar del asistente.
class InvestorProfileNotifier extends StateNotifier<InvestorProfileState> {
  InvestorProfileNotifier({
    required InvestorProfileRepository repository,
    required SupabaseAuthService authService,
  })  : _repository = repository,
        _authService = authService,
        super(const InvestorProfileState());

  final InvestorProfileRepository _repository;
  final SupabaseAuthService _authService;

  /// Vuelve a leer del servidor. Si falla (sin red), conserva lo último
  /// conocido en vez de pisarlo con "faltante".
  Future<InvestorProfile?> refresh() async {
    if (_authService.currentSession == null) {
      state = const InvestorProfileState(hasLoaded: true);
      return null;
    }
    state = InvestorProfileState(
      profile: state.profile,
      isLoading: true,
      hasLoaded: state.hasLoaded,
    );
    try {
      final profile = await _repository.fetch();
      state = InvestorProfileState(profile: profile, hasLoaded: true);
      return profile;
    } catch (_) {
      state = InvestorProfileState(
        profile: state.profile,
        hasLoaded: state.hasLoaded,
      );
      return state.profile;
    }
  }

  /// Lanza si el guardado falla — la pantalla muestra el error y el perfil
  /// anterior queda intacto.
  Future<void> save({
    required RiskTolerance risk,
    required InvestmentHorizon horizon,
    required InvestmentObjective objective,
  }) async {
    final saved = await _repository.save(
      risk: risk,
      horizon: horizon,
      objective: objective,
    );
    state = InvestorProfileState(profile: saved, hasLoaded: true);
  }
}

final investorProfileProvider =
    StateNotifierProvider<InvestorProfileNotifier, InvestorProfileState>(
  (ref) => InvestorProfileNotifier(
    repository: ref.watch(investorProfileRepositoryProvider),
    authService: ref.watch(supabaseAuthServiceProvider),
  ),
);
