import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/widgets/position_primary_button.dart';

/// Una pantalla que no tiene nada que mostrar (no encontrada, error de
/// carga): Porty con la expresión que corresponde, un título, una línea que
/// explica y, si hay, qué hacer. Mismo armado que el estado vacío de
/// posiciones cerradas.
class PortyStatusMessage extends StatelessWidget {
  const PortyStatusMessage({
    super.key,
    required this.title,
    required this.body,
    this.mood = PortyAvatarState.concerned,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String title;
  final String body;
  final PortyAvatarState mood;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final action = actionLabel;
    final secondary = secondaryLabel;
    return Align(
      // Un poco arriba del centro: centrado exacto se ve "caído".
      alignment: const Alignment(0, -0.25),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: AppDimens.sp40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: PortyAvatar(size: 64, state: mood, animated: true),
            ),
            const SizedBox(height: AppDimens.sp20),
            Semantics(
              header: true,
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: tt.titleMedium?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            const SizedBox(height: AppDimens.sp8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: tt.bodyMedium?.copyWith(
                color: colors.textSecondary,
                height: 1.5,
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: AppDimens.sp24),
              PositionPrimaryButton(label: action, onPressed: onAction),
            ],
            if (secondary != null) ...[
              const SizedBox(height: AppDimens.sp8),
              TextButton(
                onPressed: onSecondary,
                style: TextButton.styleFrom(
                  foregroundColor: colors.textSecondary,
                  minimumSize: const Size(0, 44),
                ),
                child: Text(
                  secondary,
                  style: tt.titleSmall?.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
