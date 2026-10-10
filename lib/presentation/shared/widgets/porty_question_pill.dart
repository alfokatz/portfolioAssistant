import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// Pregunta lista para Porty: pastilla con la chispa terracota (la misma de
/// "Seguí con Porty" del informe). Al tocarla, [onTap] abre el chat.
class PortyQuestionPill extends StatelessWidget {
  const PortyQuestionPill({
    super.key,
    required this.question,
    required this.onTap,
  });

  final String question;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Semantics(
      button: true,
      child: Material(
        color: colors.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusPill),
          side: BorderSide(color: colors.accentBlue.withValues(alpha: 0.45)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            PortyHapticsService.maybeOf(context)?.selectionTap();
            onTap();
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppDimens.touchTarget),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.sp16,
                vertical: AppDimens.sp8,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PortySpark(size: 12, color: colors.accentBlue),
                  const SizedBox(width: AppDimens.sp6),
                  Flexible(
                    child: Text(
                      question,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
