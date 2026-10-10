import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/auth/providers/auth_provider.dart';
import 'package:portfolio_assistant/presentation/flows/auth/ui/widgets/auth_countdown.dart';
import 'package:portfolio_assistant/presentation/flows/auth/ui/widgets/auth_primary_button.dart';
import 'package:portfolio_assistant/presentation/shared/loading/button_spinner.dart';

/// "Revisá tu email": reemplaza al formulario después de registrarse (o al
/// intentar entrar sin haber confirmado la cuenta). Fila editorial plana,
/// sin card: ícono, título, a qué email se mandó y qué hacer.
///
/// El CTA principal vuelve a iniciar sesión; reenviar es secundario y
/// respeta la espera entre emails.
class AuthCheckEmailPanel extends StatelessWidget {
  const AuthCheckEmailPanel({
    super.key,
    required this.email,
    required this.reason,
    required this.resendAvailableAt,
    required this.isResending,
    required this.enabled,
    required this.onResend,
    required this.onBackToSignIn,
  });

  final String email;
  final PendingConfirmationReason reason;
  final DateTime? resendAvailableAt;
  final bool isResending;
  final bool enabled;
  final VoidCallback onResend;
  final VoidCallback onBackToSignIn;

  static const resendButtonKey = ValueKey('auth_resend_confirmation');
  static const backButtonKey = ValueKey('auth_back_to_sign_in');

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final bodyStyle = tt.bodyMedium?.copyWith(
      color: colors.textSecondary,
      height: 1.5,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: AppDimens.touchTarget,
              height: AppDimens.touchTarget,
              decoration: BoxDecoration(
                color: colors.surfaceElevated,
                borderRadius: BorderRadius.circular(AppDimens.radiusMd),
              ),
              child: Icon(
                Icons.mark_email_unread_outlined,
                color: colors.accentBlue,
                size: AppDimens.iconLg,
              ),
            ),
            const SizedBox(width: AppDimens.sp12),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  'auth_check_email_title'.tr(),
                  style: tt.titleLarge?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppDimens.sp16),
        Text.rich(
          TextSpan(
            style: bodyStyle,
            children: [
              TextSpan(
                text: switch (reason) {
                  PendingConfirmationReason.signedUp =>
                    'auth_check_email_sent_prefix'.tr(),
                  PendingConfirmationReason.notConfirmed =>
                    'auth_check_email_not_confirmed_prefix'.tr(),
                },
              ),
              TextSpan(
                text: email,
                style: bodyStyle?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              TextSpan(text: 'auth_check_email_sent_suffix'.tr()),
            ],
          ),
        ),
        const SizedBox(height: AppDimens.sp8),
        Text('auth_check_email_hint'.tr(), style: bodyStyle),
        const SizedBox(height: AppDimens.sp28),
        AuthPrimaryButton(
          key: backButtonKey,
          label: 'auth_back_to_sign_in'.tr(),
          onPressed: enabled ? onBackToSignIn : null,
        ),
        const SizedBox(height: AppDimens.sp8),
        AuthCountdown(
          until: resendAvailableAt,
          builder: (context, remaining) {
            final waiting = remaining != null;
            final label = waiting
                ? 'auth_resend_in'.tr(
                    namedArgs: {'time': AuthCountdown.format(remaining)},
                  )
                : 'auth_resend_confirmation'.tr();
            return TextButton(
              key: resendButtonKey,
              onPressed: !enabled || waiting ? null : onResend,
              style: TextButton.styleFrom(
                foregroundColor: colors.accentBlue,
                disabledForegroundColor: colors.textSecondary,
                minimumSize: const Size.fromHeight(AppDimens.touchTarget),
              ),
              child: isResending
                  ? ButtonSpinner.small(color: colors.accentBlue)
                  : Text(
                      label,
                      style: tt.bodyMedium?.copyWith(
                        color: waiting
                            ? colors.textSecondary
                            : colors.accentBlue,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
            );
          },
        ),
      ],
    );
  }
}
