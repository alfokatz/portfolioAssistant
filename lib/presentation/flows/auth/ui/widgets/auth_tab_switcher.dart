import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

class AuthTabSwitcher extends StatelessWidget {
  const AuthTabSwitcher({
    super.key,
    required this.isSignUpMode,
    required this.onSignInTap,
    required this.onSignUpTap,
    required this.signInLabel,
    required this.signUpLabel,
    this.enabled = true,
  });

  final bool isSignUpMode;
  final VoidCallback onSignInTap;
  final VoidCallback onSignUpTap;
  final String signInLabel;
  final String signUpLabel;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    // Flexibles: con texto grande (accesibilidad) o traducciones largas,
    // las pestañas se achican y cortan el texto en vez de desbordar.
    return Row(
      children: [
        Flexible(
          child: _FlatTab(
            label: signInLabel,
            isActive: !isSignUpMode,
            onTap: enabled ? onSignInTap : null,
          ),
        ),
        const SizedBox(width: AppDimens.sp24),
        Flexible(
          child: _FlatTab(
            label: signUpLabel,
            isActive: isSignUpMode,
            onTap: enabled ? onSignUpTap : null,
          ),
        ),
      ],
    );
  }
}

class _FlatTab extends StatelessWidget {
  const _FlatTab({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 220);

    final style = Theme.of(context).textTheme.titleSmall?.copyWith(
          color: isActive ? colors.textPrimary : colors.textSecondary,
          fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
        );

    return Semantics(
      button: true,
      selected: isActive,
      enabled: onTap != null,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppDimens.touchTarget),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: style,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppDimens.sp6),
              AnimatedContainer(
                duration: duration,
                curve: Curves.easeOutCubic,
                height: 2,
                width: isActive ? 28 : 0,
                color: isActive ? colors.textPrimary : Colors.transparent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
