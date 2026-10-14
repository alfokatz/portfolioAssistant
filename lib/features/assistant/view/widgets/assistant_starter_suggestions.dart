import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// Una sugerencia inicial: el texto que se pregunta y el ícono de su tipo
/// (cartera, concepto, mercado, inversión).
typedef AssistantStarterSuggestion = ({String label, IconData icon});

/// Las sugerencias del chat vacío, como un grupo de Ajustes: una sola
/// superficie con borde y filas separadas por divisores, no una pila de
/// cajas iguales. El ícono va en el círculo silencioso de las filas
/// (`chip` / `onChip`), así el terracota queda para enviar y no se repite
/// cuatro veces; ver "Quiet Chips" en DESIGN.md.
class AssistantStarterSuggestions extends StatelessWidget {
  const AssistantStarterSuggestions({
    super.key,
    required this.suggestions,
    required this.onSelected,
  });

  final List<AssistantStarterSuggestion> suggestions;

  /// `null` deshabilita todas (turno en curso, auto-typing).
  final ValueChanged<String>? onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final onSelected = this.onSelected;

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        border: Border.all(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (i, s) in suggestions.indexed) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                // Alineado con el texto, como `SettingsDivider`.
                indent: AppDimens.sp16 + _iconBox + AppDimens.sp12,
                endIndent: AppDimens.sp16,
                color: colors.border,
              ),
            _SuggestionRow(
              suggestion: s,
              onTap: onSelected == null ? null : () => onSelected(s.label),
            ),
          ],
        ],
      ),
    );
  }
}

const _iconBox = 32.0;

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({required this.suggestion, required this.onTap});

  final AssistantStarterSuggestion suggestion;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final enabled = onTap != null;

    return Semantics(
      button: true,
      enabled: enabled,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            opacity: enabled ? 1 : 0.5,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AppDimens.touchTarget + AppDimens.sp12,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimens.sp16,
                  vertical: AppDimens.sp12,
                ),
                child: Row(
                  children: [
                    Container(
                      width: _iconBox,
                      height: _iconBox,
                      decoration: BoxDecoration(
                        color: colors.chip,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        suggestion.icon,
                        size: AppDimens.iconSm,
                        color: colors.onChip,
                      ),
                    ),
                    const SizedBox(width: AppDimens.sp12),
                    Expanded(
                      child: Text(
                        suggestion.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppDimens.sp8),
                    // Lo mismo que los chips de seguimiento de las cards:
                    // tocar envía la pregunta, no navega.
                    ExcludeSemantics(
                      child: Icon(
                        Icons.north_east_rounded,
                        size: AppDimens.iconSm,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
