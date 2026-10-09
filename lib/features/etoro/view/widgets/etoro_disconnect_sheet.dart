import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// Desconectar eToro: qué pasa con lo importado. Devuelve `true` (conservar
/// como manuales), `false` (borrar de Porty) o `null` (canceló).
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
    return SafeArea(
      child: Padding(
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
            Semantics(
              header: true,
              child: Text(
                'etoro_disconnect_title'.tr(),
                style: tt.titleLarge?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: AppDimens.sp8),
            Text(
              count == null
                  ? 'etoro_disconnect_body_generic'.tr()
                  : 'etoro_disconnect_body'.tr(namedArgs: {'count': '$count'}),
              style: tt.bodyMedium?.copyWith(
                color: colors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppDimens.sp20),
            _Option(
              selected: _keepAsManual,
              title: 'etoro_disconnect_keep_title'.tr(),
              body: 'etoro_disconnect_keep_body'.tr(),
              onTap: () => setState(() => _keepAsManual = true),
            ),
            const SizedBox(height: AppDimens.sp12),
            _Option(
              selected: !_keepAsManual,
              title: 'etoro_disconnect_delete_title'.tr(),
              body: 'etoro_disconnect_delete_body'.tr(),
              onTap: () => setState(() => _keepAsManual = false),
            ),
            const SizedBox(height: AppDimens.sp24),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(_keepAsManual),
                style: FilledButton.styleFrom(
                  backgroundColor: colors.textPrimary,
                  foregroundColor: colors.surfaceCard,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppDimens.radiusLg),
                  ),
                ),
                child: Text(
                  'etoro_disconnect_confirm'.tr(),
                  style: tt.titleSmall?.copyWith(
                    color: colors.surfaceCard,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppDimens.sp8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                foregroundColor: colors.textSecondary,
                minimumSize: const Size.fromHeight(AppDimens.touchTarget),
              ),
              child: Text('cancel'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opción tipo radio, plana: borde de acento cuando está elegida.
class _Option extends StatelessWidget {
  const _Option({
    required this.selected,
    required this.title,
    required this.body,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
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
            color: colors.surfaceCard,
            borderRadius: BorderRadius.circular(AppDimens.radiusLg),
            // Mismo grosor elegido o no: el contenido no se mueve.
            border: Border.all(
              color: selected ? colors.accentWarm : colors.border,
              width: 1.5,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: AppDimens.iconMd,
                color: selected ? colors.accentWarm : colors.textSecondary,
              ),
              const SizedBox(width: AppDimens.sp12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: tt.titleSmall?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
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
            ],
          ),
        ),
      ),
    );
  }
}
