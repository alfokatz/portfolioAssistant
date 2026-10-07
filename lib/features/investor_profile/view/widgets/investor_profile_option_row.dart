import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// Una respuesta del perfil de inversor, como fila dentro de la card de su
/// pregunta (igual que las filas de Ajustes). Elegida = fondo apenas
/// teñido y un check terracota; sin bordes por fila.
class InvestorProfileOptionRow extends StatelessWidget {
  const InvestorProfileOptionRow({
    super.key,
    required this.label,
    this.description,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final String? description;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final textTheme = Theme.of(context).textTheme;
    final description = this.description;

    return Semantics(
      button: true,
      selected: isSelected,
      inMutuallyExclusiveGroup: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            color:
                isSelected
                    ? colors.accentBlue.withValues(alpha: 0.08)
                    : Colors.transparent,
            constraints: const BoxConstraints(minHeight: AppDimens.touchTarget),
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimens.cardPadding,
              vertical: AppDimens.sp12,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: textTheme.bodyLarge?.copyWith(
                          color: colors.textPrimary,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                      if (description != null) ...[
                        const SizedBox(height: AppDimens.sp2),
                        Text(
                          description,
                          style: textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppDimens.sp12),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: isSelected ? 1 : 0,
                  child: Icon(
                    Icons.check_rounded,
                    size: AppDimens.iconMd,
                    color: colors.accentBlue,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
