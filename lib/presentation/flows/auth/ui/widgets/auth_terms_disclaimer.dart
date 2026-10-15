import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:url_launcher/url_launcher.dart';

/// Texto legal con links a términos y política de privacidad.
class AuthTermsDisclaimer extends StatelessWidget {
  const AuthTermsDisclaimer({super.key});

  static const _termsUrl = 'https://portfolioai.app/terms';
  static const _privacyUrl = 'https://portfolioai.app/privacy';

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final baseStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: colors.textSecondary,
          height: 1.45,
        );
    final linkStyle = baseStyle?.copyWith(
      color: colors.accentBlue,
      fontWeight: FontWeight.w600,
    );

    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          TextSpan(text: 'auth_terms_prefix'.tr()),
          TextSpan(
            text: 'auth_terms_link'.tr(),
            style: linkStyle,
            recognizer: TapGestureRecognizer()
              ..onTap = () => _openUrl(_termsUrl),
          ),
          TextSpan(text: 'auth_terms_and'.tr()),
          TextSpan(
            text: 'auth_privacy_link'.tr(),
            style: linkStyle,
            recognizer: TapGestureRecognizer()
              ..onTap = () => _openUrl(_privacyUrl),
          ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
