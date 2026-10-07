import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// Control segmentado de la app (Activos / Insights, Todo / Una parte…):
/// riel gris y un único indicador del color de las cards que se desliza de
/// una opción a otra, con la opción activa en negrita.
class SegmentedChoice<T> extends StatelessWidget {
  const SegmentedChoice({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.indicatorKey,
  });

  final List<({T value, String label})> options;

  /// `null`: todavía no se eligió nada (sin indicador).
  final T? selected;
  final ValueChanged<T> onChanged;

  /// Key del indicador (para tests).
  final Key? indicatorKey;

  static const slideDuration = Duration(milliseconds: 220);
  static const height = 44.0;
  static const _inset = 4.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final duration =
        MediaQuery.disableAnimationsOf(context) ? Duration.zero : slideDuration;
    final index = options.indexWhere((o) => o.value == selected);
    final count = options.length;

    return Container(
      height: height,
      padding: const EdgeInsets.all(_inset),
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppDimens.radiusPill),
      ),
      child: Stack(
        children: [
          if (index >= 0)
          AnimatedAlign(
            duration: duration,
            curve: Curves.easeOutCubic,
            // -1 → izquierda, 1 → derecha, repartido entre las opciones.
            alignment: Alignment(
              count == 1 ? 0 : -1 + 2 * index / (count - 1),
              0,
            ),
            child: FractionallySizedBox(
              key: indicatorKey,
              widthFactor: 1 / count,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  // En oscuro la card es más oscura que el riel: el
                  // indicador se aclara un poco para despegarse.
                  color:
                      Theme.of(context).brightness == Brightness.dark
                          ? Color.lerp(
                            colors.surfaceElevated,
                            Colors.white,
                            0.10,
                          )
                          : colors.surfaceCard,
                  borderRadius: BorderRadius.circular(
                    AppDimens.radiusPill - _inset,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 6,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (final option in options)
                Expanded(
                  child: _SegmentLabel(
                    label: option.label,
                    active: option.value == selected,
                    duration: duration,
                    onTap: () {
                      if (option.value == selected) return;
                      PortyHapticsService.maybeOf(context)?.selectionTap();
                      onChanged(option.value);
                    },
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SegmentLabel extends StatelessWidget {
  const _SegmentLabel({
    required this.label,
    required this.active,
    required this.duration,
    required this.onTap,
  });

  final String label;
  final bool active;
  final Duration duration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final base = Theme.of(context).textTheme.labelLarge!;
    return Semantics(
      button: true,
      selected: active,
      child: GestureDetector(
        // `onTap` y no `onTapDown`: dentro de un scroll, el down recién se
        // confirma al soltar (o a los 100 ms) igual que el tap, y así un
        // scroll que arranca sobre el selector no cambia de opción.
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: duration,
            curve: Curves.easeOutCubic,
            style: base.copyWith(
              color: active ? colors.textPrimary : colors.textSecondary,
              fontSize: 14,
              // Peso fijo: interpolar el peso hace "respirar" el ancho del
              // texto durante el cambio.
              fontWeight: FontWeight.w700,
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}
