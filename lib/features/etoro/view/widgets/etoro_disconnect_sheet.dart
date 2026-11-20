import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/etoro/view/widgets/etoro_brand.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// Desconectar eToro: qué pasa con lo importado. Devuelve `true` (conservar
/// como manuales), `false` (borrar de Porty) o `null` (canceló).
///
/// Dos opciones con ícono (la segura viene elegida y marcada como
/// recomendada) y un botón que dice lo que va a pasar: "Desconectar y
/// conservar" en tinta, "Desconectar y borrar" en rojo.
class EtoroDisconnectSheet extends StatefulWidget {
  const EtoroDisconnectSheet({super.key, this.importedCount});

  final int? importedCount;

  static Future<bool?> show(BuildContext context, {int? importedCount}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => EtoroDisconnectSheet(importedCount: importedCount),
    );
  }

  @override
  State<EtoroDisconnectSheet> createState() => _EtoroDisconnectSheetState();
}

class _EtoroDisconnectSheetState extends State<EtoroDisconnectSheet> {
  /// Por defecto, conservar: no perder datos es lo seguro.
  bool _keepAsManual = true;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final count = widget.importedCount;
    final duration =
        MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180);
    final confirmColor = _keepAsManual ? colors.textPrimary : colors.loss;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.pageHorizontal,
          0,
          AppDimens.pageHorizontal,
          AppDimens.sp16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Porty ↔ eToro con el enlace cortado: lo que va a pasar.
            const Center(
              child: EtoroPortyLockup(state: EtoroLinkState.broken, size: 44),
            ),
            const SizedBox(height: AppDimens.sp20),
            Semantics(
              header: true,
              child: Text(
                'etoro_disconnect_title'.tr(),
                textAlign: TextAlign.center,
                style: tt.titleLarge?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            const SizedBox(height: AppDimens.sp6),
            Text(
              count == null
                  ? 'etoro_disconnect_body_generic'.tr()
                  : 'etoro_disconnect_body'.tr(namedArgs: {'count': '$count'}),
              textAlign: TextAlign.center,
              style: tt.bodyMedium?.copyWith(
                color: colors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppDimens.sp24),
            _Option(
              selected: _keepAsManual,
              icon: Icons.inventory_2_outlined,
              title: 'etoro_disconnect_keep_title'.tr(),
              body: 'etoro_disconnect_keep_body'.tr(),
              tag: 'etoro_disconnect_recommended'.tr(),
              onTap: () => setState(() => _keepAsManual = true),
            ),
            const SizedBox(height: AppDimens.sp12),
            _Option(
              selected: !_keepAsManual,
              destructive: true,
              icon: Icons.delete_outline_rounded,
              title: 'etoro_disconnect_delete_title'.tr(),
              body: 'etoro_disconnect_delete_body'.tr(),
              onTap: () => setState(() => _keepAsManual = false),
            ),
            const SizedBox(height: AppDimens.sp24),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: confirmColor),
                duration: duration,
                builder:
                    (context, color, child) => FilledButton(
                      onPressed:
                          () => Navigator.of(context).pop(_keepAsManual),
                      style: FilledButton.styleFrom(
                        backgroundColor: color,
                        foregroundColor: colors.surfaceCard,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppDimens.sp16,
                          vertical: AppDimens.sp12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppDimens.radiusLg,
                          ),
                        ),
                      ),
                      child: child,
                    ),
                child: Text(
                  _keepAsManual
                      ? 'etoro_disconnect_confirm_keep'.tr()
                      : 'etoro_disconnect_confirm_delete'.tr(),
                  textAlign: TextAlign.center,
                  style: tt.titleSmall?.copyWith(
                    color: colors.surfaceCard,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppDimens.sp4),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                foregroundColor: colors.textSecondary,
                minimumSize: const Size.fromHeight(AppDimens.touchTarget),
              ),
              child: Text(
                'cancel'.tr(),
                style: tt.titleSmall?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Una opción: ícono en círculo, título (con una etiqueta opcional),
/// explicación y el check a la derecha. Elegida, el borde y el fondo toman
/// el acento (o el rojo si es la que borra).
class _Option extends StatelessWidget {
  const _Option({
    required this.selected,
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
    this.tag,
    this.destructive = false,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String body;
  final String? tag;
  final bool destructive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final tint = destructive ? colors.loss : colors.accentBlue;
    final tag = this.tag;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppDimens.radiusLg),
          onTap: () {
            PortyHapticsService.maybeOf(context)?.selectionTap();
            onTap();
          },
          child: AnimatedContainer(
            duration:
                MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(AppDimens.sp16),
            decoration: BoxDecoration(
              color:
                  selected
                      ? Color.alphaBlend(
                        tint.withValues(alpha: 0.06),
                        colors.surfaceCard,
                      )
                      : colors.surfaceCard,
              borderRadius: BorderRadius.circular(AppDimens.radiusLg),
              // Mismo grosor elegido o no: el contenido no se mueve.
              border: Border.all(
                color: selected ? tint : colors.border,
                width: 1.5,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 18, color: tint),
                ),
                const SizedBox(width: AppDimens.sp12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: AppDimens.sp8,
                        runSpacing: AppDimens.sp4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            title,
                            style: tt.titleSmall?.copyWith(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (tag != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppDimens.sp6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: colors.profitContainer,
                                borderRadius: BorderRadius.circular(
                                  AppDimens.radiusSm,
                                ),
                              ),
                              child: Text(
                                tag,
                                style: tt.labelSmall?.copyWith(
                                  color: colors.profit,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        body,
                        style: tt.bodySmall?.copyWith(
                          color: colors.textSecondary,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppDimens.sp8),
                AnimatedSwitcher(
                  duration:
                      MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 150),
                  child: Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    key: ValueKey(selected),
                    size: AppDimens.iconLg,
                    color:
                        selected
                            ? tint
                            : colors.textSecondary.withValues(alpha: 0.5),
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
