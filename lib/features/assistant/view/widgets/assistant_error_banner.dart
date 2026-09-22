import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

/// Banner de falla de conexión real (ver `isConnectionFailure` en
/// `gen_ui_error_message.dart`), con un botón de reintentar.
///
/// El texto y el botón van en filas separadas, no lado a lado en una
/// `Row`: "Reintentar" es una palabra larga en español y, compartiendo fila
/// con el texto, le dejaba muy poco ancho al mensaje — envolvía en 8-10
/// líneas angostas e inflaba la card a más de 200px de alto (medido con un
/// `ListTile(trailing: TextButton(...))`, la versión anterior de este
/// banner). Apilarlos evita esa fragilidad sin importar el largo del
/// mensaje, el idioma o el font scaling del usuario — el texto siempre
/// tiene el ancho completo de la card.
class AssistantErrorBanner extends StatelessWidget {
  const AssistantErrorBanner({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PortfolioColors.surfaceCard,
      borderRadius: BorderRadius.circular(AppDimens.radiusMd),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.sp12,
          AppDimens.sp8,
          AppDimens.sp12,
          AppDimens.sp4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: PortfolioColors.textSecondary),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimens.sp8,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: onRetry,
                child: Text('retry'.tr()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
