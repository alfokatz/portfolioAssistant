import 'package:flutter/foundation.dart';
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
    this.draft = const AllocationPlan(),
  });

  final bool loaded;
  final bool saving;
  final AllocationError? error;

  /// Lo último guardado (vacío si nunca armó el plan).
  final AllocationPlan saved;

  /// Lo que está editando en la pantalla.
  final AllocationPlan draft;

  bool get dirty =>
      !mapEquals(saved.targets, draft.targets) ||
      saved.driftThreshold != draft.driftThreshold ||
      saved.notify != draft.notify;

  bool get canSave => dirty && !saving && draft.sumsTo100;

  AllocationState copyWith({
    bool? loaded,
    bool? saving,
    AllocationError? error,
    bool clearError = false,
    AllocationPlan? saved,
    AllocationPlan? draft,
  }) => AllocationState(
    loaded: loaded ?? this.loaded,
    saving: saving ?? this.saving,
    error: clearError ? null : (error ?? this.error),
    saved: saved ?? this.saved,
    draft: draft ?? this.draft,
  );
}

/// El plan de cartera: carga, edición y guardado.
class AllocationNotifier extends StateNotifier<AllocationState> {
  AllocationNotifier(this._repo) : super(const AllocationState());

  final AllocationRepository _repo;

  Future<void> load() async {
    try {
      final plan = await _repo.load() ?? const AllocationPlan();
      if (!mounted) return;
      // Si estaba editando, no le pisa lo que tocó.
      state = state.copyWith(
        loaded: true,
        saved: plan,
        draft: state.dirty ? state.draft : plan,
        clearError: true,
      );
    } on AllocationFailure {
      if (!mounted) return;
      state = state.copyWith(loaded: true, error: AllocationError.unavailable);
    }
  }

  void setTarget(String ticker, double pct) {
    final key = ticker.trim().toUpperCase();
    if (key.isEmpty) return;
    final targets = {...state.draft.targets};
    if (pct <= 0) {
      targets.remove(key);
    } else {
      targets[key] = pct.clamp(0, 100).toDouble();
    }
    _setDraft(state.draft.copyWith(targets: targets));
  }

  /// Arranca (o reemplaza) el plan con los pesos de hoy.
  void startFromCurrent(Map<String, double> values) {
    _setDraft(
      state.draft.copyWith(targets: AllocationMath.fromCurrentWeights(values)),
    );
  }

  /// Escala los objetivos para que sumen 100.
  void normalize() {
    _setDraft(
      state.draft.copyWith(
        targets: AllocationMath.roundTo100(state.draft.targets),
      ),
    );
  }

  void setThreshold(double points) =>
      _setDraft(state.draft.copyWith(driftThreshold: points));

  void setNotify(bool notify) =>
      _setDraft(state.draft.copyWith(notify: notify));

  void discard() => state = state.copyWith(draft: state.saved);

  /// `true` si se guardó.
  Future<bool> save() async {
    if (!state.canSave) return false;
    state = state.copyWith(saving: true, clearError: true);
    try {
      await _repo.save(state.draft);
      if (!mounted) return true;
      state = state.copyWith(saving: false, saved: state.draft);
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

  void _setDraft(AllocationPlan draft) {
    state = state.copyWith(draft: draft, clearError: true);
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
