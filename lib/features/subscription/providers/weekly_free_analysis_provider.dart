import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/repositories/weekly_free_analysis_repository.dart';
import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';
import 'package:portfolio_assistant/domain/subscription/week_start.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/infraestructure/repositories/weekly_free_analysis_repository_impl.dart';

/// Si el usuario tiene disponible su análisis Gold de cortesía de esta
/// semana. `null` mientras se consulta al servidor (la UI no muestra el
/// texto de "gratis" hasta saberlo, así no aparece y desaparece).
class WeeklyFreeAnalysisNotifier extends StateNotifier<bool?> {
  WeeklyFreeAnalysisNotifier(this._repository, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now,
      super(null);

  final WeeklyFreeAnalysisRepository _repository;
  final DateTime Function() _clock;

  /// Semana de la última consulta: si cambió (pasó el domingo), se vuelve a
  /// preguntar aunque el estado diga "usado".
  String? _week;

  String get currentWeek => weekStartKey(_clock());

  Future<void> refresh({required bool eligible}) async {
    if (!eligible) {
      state = false;
      return;
    }
    final week = currentWeek;
    _week = week;
    final available = await _repository.isAvailable(week);
    if (mounted && _week == week) state = available;
  }

  /// Vuelve a consultar solo si cambió la semana desde la última vez.
  Future<void> refreshIfNewWeek({required bool eligible}) async {
    if (_week != currentWeek) await refresh(eligible: eligible);
  }

  /// Gasta la cortesía de esta semana en el servidor para [ticker].
  Future<bool> consume(String ticker) async {
    final ok = await _repository.consume(currentWeek, ticker: ticker);
    if (mounted) state = false;
    return ok;
  }
}

final weeklyFreeAnalysisProvider =
    StateNotifierProvider<WeeklyFreeAnalysisNotifier, bool?>((ref) {
      final notifier = WeeklyFreeAnalysisNotifier(
        ref.watch(weeklyFreeAnalysisRepositoryProvider),
      );
      bool eligibleFor(SubscriptionState s) =>
          !s.isLoading && PlanMatrix.hasWeeklyFreeAnalysis(s.tier);
      // Se reconsulta cuando cambia el plan (comprar Gold lo apaga).
      ref.listen<SubscriptionState>(subscriptionProvider, (previous, next) {
        if (next.isLoading) return;
        if (previous?.tier != next.tier || previous?.isLoading == true) {
          notifier.refresh(eligible: eligibleFor(next));
        }
      }, fireImmediately: true);
      return notifier;
    });

/// Igual que [weeklyFreeAnalysisProvider], pero sin Supabase (tests, sin
/// sesión) da `false` en vez de romper: la cortesía simplemente no se ofrece.
final weeklyFreeAnalysisAvailableProvider = Provider<bool?>((ref) {
  try {
    return ref.watch(weeklyFreeAnalysisProvider);
  } catch (_) {
    return false;
  }
});
