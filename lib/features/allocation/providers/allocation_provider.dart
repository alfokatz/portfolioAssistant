import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/allocation/data/allocation_repository.dart';
import 'package:portfolio_assistant/features/allocation/domain/allocation_plan.dart';
import 'package:portfolio_assistant/features/goals/providers/goals_provider.dart';

enum AllocationError { locked, unavailable }

class AllocationState {
  const AllocationState({
    this.loaded = false,
    this.saving = false,
    this.error,
    this.saved = const AllocationPlan(),
  });

  final bool loaded;
  final bool saving;
  final AllocationError? error;

  /// Lo último guardado (vacío si nunca armó el plan). Lo que el usuario
  /// está editando vive en el asistente de pasos, no acá.
  final AllocationPlan saved;

  AllocationState copyWith({
    bool? loaded,
    bool? saving,
    AllocationError? error,
    bool clearError = false,
    AllocationPlan? saved,
  }) => AllocationState(
    loaded: loaded ?? this.loaded,
    saving: saving ?? this.saving,
    error: clearError ? null : (error ?? this.error),
    saved: saved ?? this.saved,
  );
}

/// El plan de cartera: carga y guardado.
class AllocationNotifier extends StateNotifier<AllocationState> {
  AllocationNotifier(this._repo) : super(const AllocationState());

  final AllocationRepository _repo;

  Future<void> load() async {
    try {
      final plan = await _repo.load() ?? const AllocationPlan();
      if (!mounted) return;
      state = state.copyWith(loaded: true, saved: plan, clearError: true);
    } on AllocationFailure {
      if (!mounted) return;
      state = state.copyWith(loaded: true, error: AllocationError.unavailable);
    }
  }

  /// Guarda [plan] (los objetivos tienen que sumar 100). `true` si se
  /// guardó; si no, [AllocationState.error] dice por qué.
  Future<bool> save(AllocationPlan plan) async {
    if (state.saving || !plan.sumsTo100) return false;
    state = state.copyWith(saving: true, clearError: true);
    try {
      await _repo.save(plan);
      if (!mounted) return true;
      state = state.copyWith(saving: false, saved: plan);
      return true;
    } on AllocationLocked {
      if (mounted) {
        state = state.copyWith(saving: false, error: AllocationError.locked);
      }
    } on AllocationFailure {
      if (mounted) {
        state = state.copyWith(
          saving: false,
          error: AllocationError.unavailable,
        );
      }
    }
    return false;
  }
}

final allocationProvider =
    StateNotifierProvider<AllocationNotifier, AllocationState>(
      (ref) => AllocationNotifier(ref.watch(allocationRepositoryProvider)),
    );

/// Lo que más se alejó del plan guardado, si pasa su umbral (para la
/// Home). `null` sin plan o dentro del plan.
final allocationDriftProvider = Provider<AllocationRow?>((ref) {
  final plan = ref.watch(allocationProvider.select((s) => s.saved));
  if (plan.isEmpty) return null;
  final values = ref.watch(goalHoldingsProvider);
  if (values.isEmpty) return null;
  final rows = AllocationMath.rows(values: values, targets: plan.targets);
  final worst = rows.fold<AllocationRow?>(
    null,
    (w, r) => w == null || r.drift.abs() > w.drift.abs() ? r : w,
  );
  if (worst == null || worst.drift.abs() < plan.driftThreshold) return null;
  return worst;
});
