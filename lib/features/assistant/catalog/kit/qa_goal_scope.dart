import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/features/goals/domain/user_goal.dart';

/// Canal para que la card del plan (y la de la compra mensual) guarde la
/// meta en la pestaña Metas sin pasar por el modelo (no cuesta una
/// consulta y no depende de que el modelo entienda "guardala").
///
/// La provee la pantalla del asistente. Sin scope (tests aislados) la card
/// no muestra el botón.
class QaGoalScope extends InheritedWidget {
  const QaGoalScope({
    super.key,
    required this.savedFor,
    required this.existingFor,
    required this.onSave,
    required this.onOpen,
    this.editedPlan,
    this.onPlanEdited,
    required super.child,
  });

  /// La edición que el usuario hizo en la card del plan [planId] (un
  /// resultado recalculado), si la hay. Vive en la conversación: la card
  /// la recupera si se reconstruye y Porty parte de ella.
  final Map<String, Object?>? Function(String planId)? editedPlan;

  /// El usuario editó (o, con `null`, deshizo los cambios de) el plan
  /// [planId] en su card.
  final void Function(String planId, Map<String, Object?>? edited)?
  onPlanEdited;

  /// La meta ya guardada con este `plan_id`, si la hay.
  final UserGoal? Function(String planKey) savedFor;

  /// La meta activa con este nombre (guardar la actualiza).
  final UserGoal? Function(String label) existingFor;

  /// Guarda y devuelve la meta (o `null` si falló: la pantalla avisa).
  final Future<UserGoal?> Function(GoalDraft draft) onSave;
  final ValueChanged<String> onOpen;

  /// Se reconstruye la card cuando cambian las metas (guardada / borrada).
  static QaGoalScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<QaGoalScope>();

  @override
  bool updateShouldNotify(QaGoalScope oldWidget) => true;
}

/// El cierre de la card del plan (y de la compra mensual): Porty propone el
/// plan y el usuario lo confirma para crear la meta en Metas. Si ya hay una
/// meta activa con ese nombre, confirmar la actualiza. Una vez creada,
/// queda "Meta creada · Ver en Metas".
class QaSaveGoalButton extends StatefulWidget {
  const QaSaveGoalButton({super.key, required this.draft});

  final GoalDraft draft;

  @override
  State<QaSaveGoalButton> createState() => _QaSaveGoalButtonState();
}

class _QaSaveGoalButtonState extends State<QaSaveGoalButton> {
  bool _saving = false;
  UserGoal? _justSaved;
  bool _updated = false;

  Future<void> _confirm(QaGoalScope scope, {required bool updates}) async {
    setState(() {
      _saving = true;
      _updated = updates;
    });
    final goal = await scope.onSave(widget.draft);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _justSaved = goal;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scope = QaGoalScope.maybeOf(context);
    final key = widget.draft.planKey;
    if (scope == null) return const SizedBox.shrink();
    final saved = _justSaved ?? (key == null ? null : scope.savedFor(key));
    final updates = scope.existingFor(widget.draft.label) != null;

    final Widget child;
    if (saved != null) {
      child = Material(
        color: QaColors.profit.withValues(alpha: 0.10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => scope.onOpen(saved.id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  color: QaColors.profit,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _justSaved == null
                        ? 'Meta guardada en Metas'
                        : _updated
                        ? 'Meta actualizada en Metas'
                        : 'Meta creada en Metas',
                    style: QaText.label.copyWith(
                      color: QaColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  'Ver',
                  style: QaText.label.copyWith(
                    color: QaColors.accentBlue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: QaColors.accentBlue,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            updates
                ? '¿Te sirve? Confirmá y actualizo tu meta '
                    '"${widget.draft.label}" en Metas.'
                : '¿Te sirve este plan? Confirmalo y creo la meta en Metas: '
                    'ahí vas a ver cuánto llevás y si vas al día.',
            style: QaText.caption,
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _saving ? null : () => _confirm(scope, updates: updates),
            icon:
                _saving
                    ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                    : const Icon(Icons.flag_rounded, size: 18),
            label: Text(
              updates ? 'Confirmar y actualizar meta' : 'Confirmar y crear meta',
              style: QaText.label.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: QaColors.accentBlue,
              foregroundColor: Colors.white,
              disabledBackgroundColor: QaColors.accentBlue.withValues(
                alpha: 0.6,
              ),
              minimumSize: const Size.fromHeight(48),
              shape: const StadiumBorder(),
            ),
          ),
        ],
      );
    }
    return Padding(padding: const EdgeInsets.only(top: 14), child: child);
  }
}
