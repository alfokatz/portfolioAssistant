import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/presentation/base/core/base_stateful_widget.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';
import 'package:portfolio_assistant/presentation/flows/auth/providers/auth_provider.dart';
import 'package:portfolio_assistant/presentation/flows/auth/ui/widgets/auth_footer_decoration.dart';
import 'package:portfolio_assistant/presentation/flows/auth/ui/widgets/auth_footer_link.dart';
import 'package:portfolio_assistant/presentation/flows/auth/ui/widgets/auth_form_card.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_images.dart';
import 'package:portfolio_assistant/presentation/flows/auth/ui/widgets/auth_oauth_divider.dart';
import 'package:portfolio_assistant/presentation/flows/auth/ui/widgets/auth_warm_background.dart';
import 'package:portfolio_assistant/presentation/flows/auth/ui/widgets/auth_welcome_header.dart';
import 'package:portfolio_assistant/presentation/flows/auth/ui/widgets/auth_password_strength_indicator.dart';
import 'package:portfolio_assistant/presentation/flows/auth/ui/widgets/auth_primary_button.dart';
import 'package:portfolio_assistant/presentation/flows/auth/ui/widgets/auth_tab_switcher.dart';
import 'package:portfolio_assistant/presentation/flows/auth/ui/widgets/auth_terms_disclaimer.dart';
import 'package:portfolio_assistant/presentation/flows/auth/ui/widgets/auth_text_field.dart';
import 'package:portfolio_assistant/presentation/flows/auth/ui/widgets/social_sign_in_button.dart';

class LoginScreen extends StatefulHookConsumerWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends BaseStatefulWidget<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  @override
  void dispose() {
    _scrollController.dispose();
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submitForm() async {
    final formState = _formKey.currentState;
    if (formState == null) return;

    if (!formState.validate()) {
      await _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
      return;
    }

    FocusScope.of(context).unfocus();

    await ref.read(authControllerProvider.notifier).submitEmail(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          fullName: ref.read(authControllerProvider).isSignUpMode
              ? _fullNameController.text.trim()
              : null,
        );
  }

  /// Diferir un frame evita que el primer tap solo cierre el teclado/foco
  /// sin ejecutar el envío cuando un campo sigue activo.
  void _onPrimaryButtonPressed() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _submitForm();
    });
  }

  Widget _passwordVisibilityToggle({
    required bool obscure,
    required VoidCallback onToggle,
  }) {
    return IconButton(
      onPressed: onToggle,
      icon: Icon(
        obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        color: PortfolioColors.textSecondary,
        size: 22,
      ),
    );
  }

  @override
  Widget buildView(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final theme = Theme.of(context);
    final isLoading = authState.isLoading;
    final isSignUp = authState.isSignUpMode;
    final authNotifier = ref.read(authControllerProvider.notifier);

    return Scaffold(
      body: AuthWarmBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: AppDimens.mediumMargin,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 32),
                AuthWelcomeHeader(isSignUpMode: isSignUp),
                const SizedBox(height: 40),
                Form(
                  key: _formKey,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  child: AuthFormCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AuthTabSwitcher(
                          isSignUpMode: isSignUp,
                          signInLabel: 'auth_sign_in'.tr(),
                          signUpLabel: 'auth_sign_up_tab'.tr(),
                          enabled: !isLoading,
                          onSignInTap: authNotifier.setSignInMode,
                          onSignUpTap: authNotifier.setSignUpMode,
                        ),
                        const SizedBox(height: AppDimens.mediumMargin),
                        if (isSignUp) ...[
                          AuthTextField(
                            controller: _fullNameController,
                            keyboardType: TextInputType.name,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            hintText: 'auth_full_name_placeholder'.tr(),
                            prefixIcon: Icons.person_outline_rounded,
                            validator: (value) {
                              if ((value?.trim() ?? '').isEmpty) {
                                return 'auth_full_name_required'.tr();
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                        ],
                        AuthTextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          hintText: isSignUp
                              ? 'auth_email_placeholder_sign_up'.tr()
                              : 'auth_email_placeholder'.tr(),
                          prefixIcon: Icons.mail_outline_rounded,
                          validator: (value) {
                            final email = value?.trim() ?? '';
                            if (email.isEmpty) {
                              return 'auth_email_required'.tr();
                            }
                            if (!email.contains('@')) {
                              return 'auth_email_invalid'.tr();
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        AuthTextField(
                          controller: _passwordController,
                          obscureText: authState.obscurePassword,
                          textInputAction: isSignUp
                              ? TextInputAction.next
                              : TextInputAction.done,
                          onFieldSubmitted:
                              isSignUp ? null : (_) => _submitForm(),
                          hintText: isSignUp
                              ? 'auth_password_placeholder'.tr()
                              : '••••••••',
                          prefixIcon: Icons.lock_outline_rounded,
                          suffixIcon: _passwordVisibilityToggle(
                            obscure: authState.obscurePassword,
                            onToggle: authNotifier.toggleObscurePassword,
                          ),
                          validator: (value) {
                            final password = value ?? '';
                            if (password.isEmpty) {
                              return 'auth_password_required'.tr();
                            }
                            if (password.length < 6) {
                              return 'auth_password_min_length'.tr();
                            }
                            return null;
                          },
                        ),
                        if (isSignUp)
                          ValueListenableBuilder<TextEditingValue>(
                            valueListenable: _passwordController,
                            builder: (context, value, _) {
                              return AuthPasswordStrengthIndicator(
                                password: value.text,
                              );
                            },
                          ),
                        if (isSignUp) ...[
                          const SizedBox(height: 12),
                          AuthTextField(
                            controller: _confirmPasswordController,
                            obscureText: authState.obscureConfirmPassword,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _submitForm(),
                            hintText:
                                'auth_confirm_password_placeholder'.tr(),
                            prefixIcon: Icons.lock_reset_rounded,
                            suffixIcon: _passwordVisibilityToggle(
                              obscure: authState.obscureConfirmPassword,
                              onToggle: authNotifier.toggleObscureConfirmPassword,
                            ),
                            validator: (value) {
                              final confirm = value ?? '';
                              if (confirm.isEmpty) {
                                return 'auth_confirm_password_required'.tr();
                              }
                              if (confirm != _passwordController.text) {
                                return 'auth_password_mismatch'.tr();
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: AppDimens.mediumMargin),
                          const AuthTermsDisclaimer(),
                        ],
                        if (!isSignUp) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: isLoading
                                  ? null
                                  : () async {
                                      await authNotifier.requestPasswordReset(
                                        email: _emailController.text,
                                      );
                                    },
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppDimens.sp8,
                                  vertical: AppDimens.sp8,
                                ),
                              ),
                              child: Text(
                                'auth_forgot_password'.tr(),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: PortfolioColors.accentBlue,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: AppDimens.mediumMargin),
                        AuthPrimaryButton(
                          label: isSignUp
                              ? 'auth_sign_up'.tr()
                              : 'auth_sign_in'.tr(),
                          isLoading: isLoading,
                          onPressed:
                              isLoading ? null : _onPrimaryButtonPressed,
                        ),
                        const SizedBox(height: AppDimens.mediumMargin),
                        AuthOauthDivider(label: 'auth_oauth_divider'.tr()),
                        const SizedBox(height: AppDimens.mediumMargin),
                        SocialSignInButton(
                          label: 'auth_continue_google'.tr(),
                          icon: AppImages.googleIcon(
                            width: 22,
                            height: 22,
                          ),
                          onPressed: isLoading
                              ? null
                              : authNotifier.submitGoogleSignIn,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                const AuthFooterDecoration(),
                const SizedBox(height: AppDimens.mediumMargin),
                AuthFooterLink(
                  prefix: isSignUp
                      ? 'auth_footer_has_account'.tr()
                      : 'auth_footer_no_account'.tr(),
                  actionLabel: isSignUp
                      ? 'auth_footer_sign_in'.tr()
                      : 'auth_footer_register'.tr(),
                  enabled: !isLoading,
                  onActionTap: authNotifier.toggleMode,
                ),
                const SizedBox(height: AppDimens.smallMargin),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
