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
    required super.child,
  });

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

/// "Guardar en Metas" → "Guardada en Metas · Ver". Al pie de la card del
/// plan y de la compra mensual.
class QaSaveGoalButton extends StatefulWidget {
  const QaSaveGoalButton({super.key, required this.draft});

  final GoalDraft draft;

  @override
  State<QaSaveGoalButton> createState() => _QaSaveGoalButtonState();
}

class _QaSaveGoalButtonState extends State<QaSaveGoalButton> {
  bool _saving = false;
  UserGoal? _justSaved;

  @override
  Widget build(BuildContext context) {
    final scope = QaGoalScope.maybeOf(context);
    final key = widget.draft.planKey;
    if (scope == null) return const SizedBox.shrink();
    final saved = _justSaved ?? (key == null ? null : scope.savedFor(key));
    final updates = scope.existingFor(widget.draft.label) != null;

    final Widget child;
    if (saved != null) {
      child = TextButton.icon(
        onPressed: () => scope.onOpen(saved.id),
        icon: Icon(Icons.check_circle_rounded, color: QaColors.profit, size: 18),
        label: Text(
          'Guardada en Metas · Ver',
          style: QaText.label.copyWith(color: QaColors.textPrimary),
        ),
      );
    } else {
      child = OutlinedButton.icon(
        onPressed:
            _saving
                ? null
                : () async {
                  setState(() => _saving = true);
                  final goal = await scope.onSave(widget.draft);
                  if (!mounted) return;
                  setState(() {
                    _saving = false;
                    _justSaved = goal;
                  });
                },
        icon:
            _saving
                ? SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: QaColors.accentBlue,
                  ),
                )
                : Icon(
                  Icons.bookmark_add_outlined,
                  color: QaColors.accentBlue,
                  size: 18,
                ),
        label: Text(
          updates ? 'Actualizar en Metas' : 'Guardar en Metas',
          style: QaText.label.copyWith(
            color: QaColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(44),
          side: BorderSide(color: QaColors.accentBlue, width: 1.2),
          shape: const StadiumBorder(),
        ),
      );
    }
    return Padding(padding: const EdgeInsets.only(top: 12), child: child);
  }
}
