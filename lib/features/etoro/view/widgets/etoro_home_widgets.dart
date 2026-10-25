import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/etoro/nav/etoro_router.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// "Conectar eToro" como alternativa a cargar a mano (Home vacía,
/// onboarding). Secundario: borde, sin relleno; lo principal sigue siendo
/// agregar una posición. Abre la pantalla de eToro, que explica qué hace
/// Porty con la cuenta antes de pedir nada (y el paywall si hace falta).
class EtoroConnectButton extends StatelessWidget {
  const EtoroConnectButton({super.key});

  static void open(BuildContext context) {
    PortyHapticsService.maybeOf(context)?.selectionTap();
    context.pushNamed(EtoroRouter.connectionRouteName);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton.icon(
        onPressed: () => open(context),
        icon: const Icon(Icons.link_rounded, size: AppDimens.iconMd),
        label: Text('etoro_connect_cta'.tr()),
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.textPrimary,
          side: BorderSide(color: colors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusLg),
          ),
          textStyle: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// Aviso en la Home cuando eToro cerró el acceso: lo importado sigue en
/// pantalla, pero no se actualiza hasta reconectar. Fila plana con borde,
/// como el aviso de cotizaciones; nunca un diálogo.
class EtoroReconnectBanner extends StatelessWidget {
  const EtoroReconnectBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pageHorizontal,
        0,
        AppDimens.pageHorizontal,
        AppDimens.sp16,
      ),
      child: Semantics(
        container: true,
        liveRegion: true,
        child: Container(
          padding: const EdgeInsets.fromLTRB(
            AppDimens.sp16,
            AppDimens.sp12,
            AppDimens.sp8,
            AppDimens.sp12,
          ),
          decoration: BoxDecoration(
            color: colors.surfaceCard,
            borderRadius: BorderRadius.circular(AppDimens.radiusLg),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              // Porty preocupado: lo importado sigue, pero no se actualiza.
              const ExcludeSemantics(
                child: PortyAvatar(size: 32, state: PortyAvatarState.concerned),
              ),
              const SizedBox(width: AppDimens.sp12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'etoro_reconnect_title'.tr(),
                      style: tt.bodyMedium?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'etoro_home_reconnect_body'.tr(),
                      style: tt.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => EtoroConnectButton.open(context),
                style: TextButton.styleFrom(
                  foregroundColor: colors.textPrimary,
                  minimumSize: const Size(
                    AppDimens.touchTarget,
                    AppDimens.touchTarget,
                  ),
                  textStyle: tt.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: Text('etoro_reconnect_short'.tr()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
