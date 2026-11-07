import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/shared/loading/button_spinner.dart';

/// Botón secundario para OAuth (Google): superficie de card + borde
/// Whisper, como los inputs de auth. Sin relleno gris: el único bloque con
/// fondo propio del formulario es el CTA primario.
class SocialSignInButton extends StatelessWidget {
  const SocialSignInButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final Widget icon;
  final VoidCallback? onPressed;

  /// Mientras el login con el proveedor está abierto en el navegador: el
  /// spinner reemplaza al contenido (mismo tamaño de botón).
  final bool loading;

  /// Mismo alto para Google y Apple.
  static const height = AppDimens.touchTarget + AppDimens.sp4;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;

    return SizedBox(
      height: height,
      child: LoadingButtonContent(
        loading: loading,
        spinnerColor: colors.textPrimary,
        builder:
            (context, showSpinner, child) => OutlinedButton(
              onPressed:
                  showSpinner || onPressed == null
                      ? null
                      : loading
                      ? () {}
                      : onPressed,
              style: OutlinedButton.styleFrom(
                backgroundColor: colors.surfaceCard,
                foregroundColor: colors.textPrimary,
                side: BorderSide(color: colors.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppDimens.radiusLg),
                ),
                padding: const EdgeInsets.symmetric(horizontal: AppDimens.sp12),
              ),
              child: child,
            ),
        label: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(width: AppDimens.sp8),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
