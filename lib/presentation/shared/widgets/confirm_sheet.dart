import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// Confirmación de la app: una hoja desde abajo, no un diálogo de Material.
/// Mismo lenguaje que "Desconectar eToro": algo arriba que dice de qué se
/// trata, título y explicación centrados, y un botón lleno de 52 px que dice
/// exactamente lo que va a pasar ("Borrar meta", no "Aceptar"). Si destruye
/// algo, el botón va en rojo; si no, en tinta. "Cancelar" queda abajo,
/// callado, para que no compita.
///
/// Devuelve `true` solo si el usuario confirmó (cerrarla o cancelar =
/// `false`).
class ConfirmSheet extends StatelessWidget {
  const ConfirmSheet({
    super.key,
    required this.title,
    required this.confirmLabel,
    this.body,
    this.destructive = true,
    this.leading,
  });

  final String title;
  final String? body;
  final String confirmLabel;
  final bool destructive;

  /// Lo de arriba. Default: Porty, preocupado si la acción destruye algo.
  final Widget? leading;

  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String confirmLabel,
    String? body,
    bool destructive = true,
    Widget? leading,
  }) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder:
          (_) => ConfirmSheet(
            title: title,
            body: body,
            confirmLabel: confirmLabel,
            destructive: destructive,
            leading: leading,
          ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final fill = destructive ? colors.loss : colors.textPrimary;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.pageHorizontal,
          0,
          AppDimens.pageHorizontal,
          AppDimens.sp8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: ExcludeSemantics(
                child:
                    leading ??
                    PortyAvatar(
                      size: 56,
                      state:
                          destructive
                              ? PortyAvatarState.concerned
                              : PortyAvatarState.idle,
                    ),
              ),
            ),
            const SizedBox(height: AppDimens.sp16),
            Semantics(
              header: true,
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: tt.titleLarge?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  height: 1.25,
                ),
              ),
            ),
            if (body case final body?) ...[
              const SizedBox(height: AppDimens.sp8),
              Text(
                body,
                textAlign: TextAlign.center,
                style: tt.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
            const SizedBox(height: AppDimens.sp24),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: () {
                  PortyHapticsService.maybeOf(context)?.selectionTap();
                  Navigator.of(context).pop(true);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: fill,
                  foregroundColor: colors.surfaceCard,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppDimens.radiusLg),
                  ),
                ),
                child: Text(
                  confirmLabel,
                  style: tt.titleSmall?.copyWith(
                    color: colors.surfaceCard,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppDimens.sp4),
            SizedBox(
              height: AppDimens.touchTarget + 4,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: TextButton.styleFrom(
                  foregroundColor: colors.textSecondary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppDimens.radiusLg),
                  ),
                ),
                child: Text(
                  'cancel'.tr(),
                  style: tt.titleSmall?.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
