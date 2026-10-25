import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:url_launcher/url_launcher.dart';

/// Pantalla de bloqueo cuando este build quedó por debajo del mínimo
/// soportado (ver `checkAppUpdate`). Sobria: sin ilustración ni tono de
/// error, un texto y una sola acción. No tiene salida: la versión vieja ya
/// no puede hablar con el servidor.
class AppUpdateRequiredScreen extends StatelessWidget {
  const AppUpdateRequiredScreen({super.key, this.storeUrl});

  final String? storeUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = storeUrl;
    return Material(
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.pageHorizontal + AppDimens.sp8,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.system_update_alt_rounded,
                size: AppDimens.iconLg,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              const SizedBox(height: AppDimens.sp16),
              Text(
                'app_update_required_title'.tr(),
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: AppDimens.sp8),
              Text(
                'app_update_required_body'.tr(),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  height: 1.45,
                ),
              ),
              if (url != null) ...[
                const SizedBox(height: AppDimens.sp24),
                FilledButton(
                  onPressed:
                      () => launchUrl(
                        Uri.parse(url),
                        mode: LaunchMode.externalApplication,
                      ),
                  child: Text('app_update_required_action'.tr()),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
