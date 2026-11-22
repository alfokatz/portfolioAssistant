import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// Un tema del selector: su rótulo y si se sigue.
typedef TopicGridItem = ({String id, String label, bool followed});

/// Los temas como bloques en grilla de 2: oscuro (tinta) = lo seguís, claro
/// con borde = no. Tocar un bloque lo sigue o lo deja de seguir. Cada bloque
/// mide al menos 52 px.
class TopicGrid extends StatelessWidget {
  const TopicGrid({super.key, required this.items, required this.onToggle});

  final List<TopicGridItem> items;
  final void Function(String id, bool followed) onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    Widget block(TopicGridItem t) => Semantics(
      button: true,
      toggled: t.followed,
      label: t.label,
      excludeSemantics: true,
      child: AnimatedContainer(
        duration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: t.followed ? colors.textPrimary : colors.surfaceCard,
          borderRadius: BorderRadius.circular(AppDimens.radiusLg),
          border: Border.all(
            color: t.followed ? colors.textPrimary : colors.border,
          ),
        ),
        child: InkWell(
          onTap: () => onToggle(t.id, !t.followed),
          borderRadius: BorderRadius.circular(AppDimens.radiusLg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: AppDimens.sp12,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  t.label,
                  style: tt.titleSmall?.copyWith(
                    fontWeight: t.followed ? FontWeight.w600 : FontWeight.w500,
                    color: t.followed ? colors.surfaceCard : colors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += 2) {
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: block(items[i])),
              const SizedBox(width: AppDimens.sp8),
              Expanded(
                child:
                    i + 1 < items.length
                        ? block(items[i + 1])
                        : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
      if (i + 2 < items.length) rows.add(const SizedBox(height: AppDimens.sp8));
    }
    return Column(children: rows);
  }
}
