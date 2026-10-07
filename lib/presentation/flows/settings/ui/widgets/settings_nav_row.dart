import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// Una fila de Ajustes. La etiqueta va siempre en una línea. Un [value]
/// corto ("Español", "Claro") va a la derecha; uno largo ("Agresivo ·
/// Mediano plazo…") va como [subtitle], debajo de la etiqueta, para que
/// ninguno de los dos se corte.
class SettingsNavRow extends StatelessWidget {
  const SettingsNavRow({
    super.key,
    required this.icon,
    required this.label,
    this.value,
    this.subtitle,
    this.onTap,
    this.showChevron = true,
  });

  final IconData icon;
  final String label;
  final String? value;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.sp16,
            vertical: 14,
          ),
          child: Row(
            children: [
              _SettingsIconBox(icon: icon),
              const SizedBox(width: AppDimens.sp12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.textSecondary,
                              height: 1.35,
                            ),
                      ),
                  ],
                ),
              ),
              if (value != null) ...[
                const SizedBox(width: AppDimens.sp8),
                Text(
                  value!,
                  maxLines: 1,
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.textSecondary,
                      ),
                ),
                const SizedBox(width: AppDimens.sp4),
              ],
              if (showChevron && onTap != null)
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: colors.textSecondary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsToggleRow extends StatelessWidget {
  const SettingsToggleRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.sp16,
        vertical: AppDimens.sp6,
      ),
      child: Row(
        children: [
          _SettingsIconBox(icon: icon),
          const SizedBox(width: AppDimens.sp12),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeTrackColor: colors.accentBlue,
            activeThumbColor: colors.surfaceCard,
          ),
        ],
      ),
    );
  }
}

/// El ícono en un círculo teñido, como los encabezados de las cards.
class _SettingsIconBox extends StatelessWidget {
  const _SettingsIconBox({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: colors.accentBlue.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        size: 18,
        color: colors.accentBlue,
      ),
    );
  }
}
