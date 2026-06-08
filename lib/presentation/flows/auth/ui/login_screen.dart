import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/presentation/base/core/base_stateful_widget.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';
import 'package:portfolio_assistant/presentation/flows/auth/providers/auth_provider.dart';
import 'package:portfolio_assistant/presentation/flows/auth/ui/widgets/auth_footer_decoration.dart';
import 'package:portfolio_assistant/presentation/flows/auth/ui/widgets/auth_footer_link.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_images.dart';
import 'package:portfolio_assistant/presentation/flows/auth/ui/widgets/auth_oauth_divider.dart';
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
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

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
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) {
      await _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
      return;
    }

    await ref.read(authControllerProvider.notifier).submitEmail(
          email: _emailController.text,
          password: _passwordController.text,
          fullName: ref.read(authControllerProvider).isSignUpMode
              ? _fullNameController.text
              : null,
        );
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

    return Scaffold(
      backgroundColor: PortfolioColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: AppDimens.mediumMargin,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Spacer(flex: 2),
                      Text(
                        'auth_title'.tr(),
                        style: theme.textTheme.displayLarge?.copyWith(
                          color: PortfolioColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppDimens.xSmallMargin),
                      Text(
                        'auth_tagline'.tr(),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: PortfolioColors.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppDimens.largeMargin),
                      Form(
                        key: _formKey,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AuthTabSwitcher(
                              isSignUpMode: isSignUp,
                              signInLabel: 'auth_sign_in'.tr(),
                              signUpLabel: 'auth_sign_up_tab'.tr(),
                              enabled: !isLoading,
                              onSignInTap:
                                  ref
                                      .read(authControllerProvider.notifier)
                                      .setSignInMode,
                              onSignUpTap:
                                  ref
                                      .read(authControllerProvider.notifier)
                                      .setSignUpMode,
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
                              hintText:
                                  isSignUp
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
                              obscureText: _obscurePassword,
                              textInputAction:
                                  isSignUp
                                      ? TextInputAction.next
                                      : TextInputAction.done,
                              onFieldSubmitted:
                                  isSignUp ? null : (_) => _submitForm(),
                              hintText:
                                  isSignUp
                                      ? 'auth_password_placeholder'.tr()
                                      : '••••••••',
                              prefixIcon: Icons.lock_outline_rounded,
                              suffixIcon: _passwordVisibilityToggle(
                                obscure: _obscurePassword,
                                onToggle:
                                    () => setState(
                                      () =>
                                          _obscurePassword = !_obscurePassword,
                                    ),
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
                                obscureText: _obscureConfirmPassword,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _submitForm(),
                                hintText:
                                    'auth_confirm_password_placeholder'.tr(),
                                prefixIcon: Icons.lock_reset_rounded,
                                suffixIcon: _passwordVisibilityToggle(
                                  obscure: _obscureConfirmPassword,
                                  onToggle:
                                      () => setState(
                                        () =>
                                            _obscureConfirmPassword =
                                                !_obscureConfirmPassword,
                                      ),
                                ),
                                validator: (value) {
                                  final confirm = value ?? '';
                                  if (confirm.isEmpty) {
                                    return 'auth_confirm_password_required'
                                        .tr();
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
                                  onPressed:
                                      isLoading
                                          ? null
                                          : () async {
                                            await ref
                                                .read(
                                                  authControllerProvider
                                                      .notifier,
                                                )
                                                .requestPasswordReset(
                                                  email: _emailController.text,
                                                );
                                          },
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 4,
                                    ),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
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
                              label:
                                  isSignUp
                                      ? 'auth_sign_up'.tr()
                                      : 'auth_sign_in'.tr(),
                              isLoading: isLoading,
                              onPressed: isLoading ? null : _submitForm,
                            ),
                            const SizedBox(height: AppDimens.mediumMargin),
                            AuthOauthDivider(label: 'auth_oauth_divider'.tr()),
                            const SizedBox(height: AppDimens.mediumMargin),
                            SocialSignInButton(
                              label: 'auth_google'.tr(),
                              icon: AppImages.googleIcon(width: 22, height: 22),
                              onPressed:
                                  isLoading
                                      ? null
                                      : ref
                                          .read(
                                            authControllerProvider.notifier,
                                          )
                                          .submitGoogleSignIn,
                            ),
                          ],
                        ),
                      ),
                      const Spacer(flex: 3),
                      const AuthFooterDecoration(),
                      const SizedBox(height: AppDimens.mediumMargin),
                      AuthFooterLink(
                        prefix:
                            isSignUp
                                ? 'auth_footer_has_account'.tr()
                                : 'auth_footer_no_account'.tr(),
                        actionLabel:
                            isSignUp
                                ? 'auth_footer_sign_in'.tr()
                                : 'auth_footer_register'.tr(),
                        enabled: !isLoading,
                        onActionTap:
                            () =>
                                ref
                                    .read(authControllerProvider.notifier)
                                    .toggleMode(),
                      ),
                      const SizedBox(height: AppDimens.smallMargin),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
