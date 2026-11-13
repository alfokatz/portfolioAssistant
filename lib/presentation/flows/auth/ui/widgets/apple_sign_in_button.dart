import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/flows/auth/ui/widgets/social_sign_in_button.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart' show AppleLogoPainter;

/// "Continuar con Apple" con el estilo de las Human Interface Guidelines:
/// negro con logo y texto blancos en light, blanco con negro en dark (Apple
/// pide el estilo que contraste con el fondo). Mismo alto, radio y tipografía
/// que el botón de Google para que el par se lea como un solo bloque.
///
/// Los colores son los de Apple, no tokens de la app: la guía no permite
/// teñir el botón con el color de marca. El logo es el trazado oficial de la
/// manzana (el `AppleLogoPainter` del paquete sign_in_with_apple), no el
/// ícono de Material, que la revisión de la App Store no acepta.
class AppleSignInButton extends StatelessWidget {
  const AppleSignInButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? Colors.white : Colors.black;
    final foreground = dark ? Colors.black : Colors.white;

    return SizedBox(
      height: SocialSignInButton.height,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          disabledBackgroundColor: background.withValues(alpha: 0.4),
          disabledForegroundColor: foreground.withValues(alpha: 0.7),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusLg),
          ),
          padding: const EdgeInsets.symmetric(horizontal: AppDimens.sp12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              // Proporción del logo de Apple (25 de ancho por 31 de alto).
              width: AppDimens.iconLg * 25 / 31,
              height: AppDimens.iconLg,
              child: CustomPaint(
                painter: AppleLogoPainter(color: foreground),
              ),
            ),
            const SizedBox(width: AppDimens.sp8),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
