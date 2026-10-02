import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/presentation/base/core/base_stateful_widget.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_images.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/auth/providers/auth_provider.dart';
import 'package:portfolio_assistant/presentation/flows/auth/ui/widgets/apple_sign_in_button.dart';
import 'package:portfolio_assistant/presentation/flows/auth/ui/widgets/auth_oauth_divider.dart';
import 'package:portfolio_assistant/presentation/flows/auth/ui/widgets/auth_password_strength_indicator.dart';
import 'package:portfolio_assistant/presentation/flows/auth/ui/widgets/auth_porty_header.dart';
import 'package:portfolio_assistant/presentation/flows/auth/ui/widgets/auth_primary_button.dart';
import 'package:portfolio_assistant/presentation/flows/auth/ui/widgets/auth_tab_switcher.dart';
import 'package:portfolio_assistant/presentation/flows/auth/ui/widgets/auth_terms_disclaimer.dart';
import 'package:portfolio_assistant/presentation/flows/auth/ui/widgets/auth_text_field.dart';
import 'package:portfolio_assistant/presentation/flows/auth/ui/widgets/social_sign_in_button.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/motion_aware_size.dart';

class LoginScreen extends StatefulHookConsumerWidget {
  const LoginScreen({super.key});

  static const primaryButtonKey = ValueKey('auth_primary_button');
  static const formErrorKey = ValueKey('auth_form_error');

  /// Cambios de layout de la pantalla: alto del formulario al cambiar de
  /// pestaña y compactado del bloque de Porty con el teclado.
  static const motionDuration = Duration(milliseconds: 220);

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
  final _fullNameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmPasswordFocus = FocusNode();

  @override
  void dispose() {
    _scrollController.dispose();
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _fullNameFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmPasswordFocus.dispose();
    super.dispose();
  }

  PortyHapticsService get _haptics => ref.read(portyHapticsServiceProvider);

  Future<void> _submitForm() async {
    final formState = _formKey.currentState;
    if (formState == null) return;

    if (!formState.validate()) {
      _haptics.authFailed();
      final reduceMotion = MediaQuery.disableAnimationsOf(context);
      if (_scrollController.hasClients) {
        await _scrollController.animateTo(
          0,
          duration:
              reduceMotion ? Duration.zero : const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      }
      return;
    }

    // Sin unfocus: cerrar el teclado acá re-expandiría el bloque de Porty en
    // medio del spinner. Al entrar, la pantalla se va con el fade; si falla,
    // el usuario sigue escribiendo donde estaba. (El AutofillGroup confirma
    // la contraseña para el llavero de iOS al desmontarse.)
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

  void _onTabTap(VoidCallback select) {
    _haptics.selectionTap();
    select();
  }

  void _onFieldChanged(String _) =>
      ref.read(authControllerProvider.notifier).clearErrors();

  Widget _passwordVisibilityToggle({
    required bool obscure,
    required VoidCallback onToggle,
  }) {
    final colors = context.customColors;

    return IconButton(
      onPressed: onToggle,
      tooltip: obscure ? 'auth_show_password'.tr() : 'auth_hide_password'.tr(),
      icon: Icon(
        obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        color: colors.textSecondary,
        size: AppDimens.iconMd,
      ),
    );
  }

  void _listenForFeedback() {
    // Un error nuevo (del servidor o del email al pedir el reset) vibra una
    // vez; los de validación vibran en _submitForm.
    ref.listen<(String?, String?)>(
      authControllerProvider.select((s) => (s.formError, s.emailError)),
      (previous, next) {
        final newForm = next.$1 != null && next.$1 != previous?.$1;
        final newEmail = next.$2 != null && next.$2 != previous?.$2;
        if (newForm || newEmail) _haptics.authFailed();
      },
    );
    // Cualquier camino que termine en sesión (email, registro o la vuelta
    // de OAuth) confirma con un toque antes del fade a la app.
    ref.listen<AsyncValue<Object?>>(authSessionProvider, (previous, next) {
      if (previous?.valueOrNull == null && next.valueOrNull != null) {
        _haptics.authSucceeded();
      }
    });
  }

  @override
  Widget buildView(BuildContext context) {
    _listenForFeedback();
    final colors = context.customColors;
    final authState = ref.watch(authControllerProvider);
    final showApple = ref.watch(appleSignInAvailableProvider);
    final isLoading = authState.isLoading;
    final isSignUp = authState.isSignUpMode;
    final authNotifier = ref.read(authControllerProvider.notifier);
    // Teclado abierto: Porty se compacta para que los campos y el botón
    // entren sin scroll en un iPhone SE. Se lee acá, arriba del Scaffold,
    // porque el Scaffold le saca el inset al body.
    final compact = MediaQuery.viewInsetsOf(context).bottom > 0;

    // Scaffold transparente (tema): el fondo con el halo lo pinta la ruta
    // (ver FadeThroughPage / RouteBackground), igual que el resto de la app.
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          controller: _scrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(
            AppDimens.pageHorizontal,
            0,
            AppDimens.pageHorizontal,
            AppDimens.sp32,
          ),
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Gap(compact ? AppDimens.sp12 : AppDimens.sp32),
                AuthPortyHeader(isSignUpMode: isSignUp, compact: compact),
                _Gap(compact ? AppDimens.sp16 : AppDimens.sp32),
                Form(
                  key: _formKey,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  child: MotionAwareSize(
                    duration: LoginScreen.motionDuration,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AuthTabSwitcher(
                          isSignUpMode: isSignUp,
                          signInLabel: 'auth_sign_in'.tr(),
                          signUpLabel: 'auth_sign_up_tab'.tr(),
                          enabled: !isLoading,
                          onSignInTap: () =>
                              _onTabTap(authNotifier.setSignInMode),
                          onSignUpTap: () =>
                              _onTabTap(authNotifier.setSignUpMode),
                        ),
                        _Gap(compact ? AppDimens.sp12 : AppDimens.sp24),
                        if (isSignUp) ...[
                          _FadeIn(
                            child: AuthTextField(
                              controller: _fullNameController,
                              focusNode: _fullNameFocus,
                              keyboardType: TextInputType.name,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.name],
                              autocorrect: false,
                              hintText: 'auth_full_name_placeholder'.tr(),
                              prefixIcon: Icons.person_outline_rounded,
                              onChanged: _onFieldChanged,
                              onFieldSubmitted: (_) =>
                                  _emailFocus.requestFocus(),
                              validator: (value) {
                                if ((value?.trim() ?? '').isEmpty) {
                                  return 'auth_full_name_required'.tr();
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(height: AppDimens.sp12),
                        ],
                        AuthTextField(
                          controller: _emailController,
                          focusNode: _emailFocus,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.email],
                          autocorrect: false,
                          hintText: isSignUp
                              ? 'auth_email_placeholder_sign_up'.tr()
                              : 'auth_email_placeholder'.tr(),
                          prefixIcon: Icons.mail_outline_rounded,
                          forceErrorText: authState.emailError,
                          onChanged: _onFieldChanged,
                          onFieldSubmitted: (_) =>
                              _passwordFocus.requestFocus(),
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
                        const SizedBox(height: AppDimens.sp12),
                        AuthTextField(
                          controller: _passwordController,
                          focusNode: _passwordFocus,
                          obscureText: authState.obscurePassword,
                          textInputAction: isSignUp
                              ? TextInputAction.next
                              : TextInputAction.done,
                          autofillHints: [
                            isSignUp
                                ? AutofillHints.newPassword
                                : AutofillHints.password,
                          ],
                          onChanged: _onFieldChanged,
                          onFieldSubmitted: isSignUp
                              ? (_) => _confirmPasswordFocus.requestFocus()
                              : (_) => _submitForm(),
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
                        if (isSignUp) ...[
                          ValueListenableBuilder<TextEditingValue>(
                            valueListenable: _passwordController,
                            builder: (context, value, _) {
                              return AuthPasswordStrengthIndicator(
                                password: value.text,
                              );
                            },
                          ),
                          const SizedBox(height: AppDimens.sp12),
                          _FadeIn(
                            child: AuthTextField(
                              controller: _confirmPasswordController,
                              focusNode: _confirmPasswordFocus,
                              obscureText: authState.obscureConfirmPassword,
                              textInputAction: TextInputAction.done,
                              autofillHints: const [
                                AutofillHints.newPassword,
                              ],
                              onChanged: _onFieldChanged,
                              onFieldSubmitted: (_) => _submitForm(),
                              hintText:
                                  'auth_confirm_password_placeholder'.tr(),
                              prefixIcon: Icons.lock_reset_rounded,
                              suffixIcon: _passwordVisibilityToggle(
                                obscure: authState.obscureConfirmPassword,
                                onToggle:
                                    authNotifier.toggleObscureConfirmPassword,
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
                          ),
                          const SizedBox(height: AppDimens.sp20),
                          const _FadeIn(child: AuthTermsDisclaimer()),
                          const SizedBox(height: AppDimens.sp24),
                        ],
                        if (!isSignUp) ...[
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
                                foregroundColor: colors.accentBlue,
                                minimumSize: const Size(
                                  AppDimens.touchTarget,
                                  AppDimens.touchTarget,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppDimens.sp8,
                                ),
                              ),
                              child: Text(
                                'auth_forgot_password'.tr(),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: colors.accentBlue,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                          ),
                          const SizedBox(height: AppDimens.sp8),
                        ],
                        AuthPrimaryButton(
                          key: LoginScreen.primaryButtonKey,
                          label: isSignUp
                              ? 'auth_sign_up'.tr()
                              : 'auth_sign_in'.tr(),
                          isLoading: isLoading,
                          onPressed:
                              isLoading ? null : _onPrimaryButtonPressed,
                        ),
                        if (authState.formError case final error?)
                          _FadeIn(
                            key: ValueKey(error),
                            child: _FormError(message: error),
                          ),
                        const SizedBox(height: AppDimens.sp24),
                        AuthOauthDivider(label: 'auth_oauth_divider'.tr()),
                        const SizedBox(height: AppDimens.sp24),
                        // Apple arriba de Google en iOS (HIG); oculto en
                        // Android y mientras no esté configurado.
                        if (showApple) ...[
                          AppleSignInButton(
                            label: 'auth_continue_apple'.tr(),
                            onPressed: isLoading
                                ? null
                                : authNotifier.submitAppleSignIn,
                          ),
                          const SizedBox(height: AppDimens.sp12),
                        ],
                        SocialSignInButton(
                          label: 'auth_continue_google'.tr(),
                          icon: AppImages.googleIcon(
                            width: AppDimens.iconMd,
                            height: AppDimens.iconMd,
                          ),
                          onPressed: isLoading
                              ? null
                              : authNotifier.submitGoogleSignIn,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Espacio vertical que se anima al compactar con el teclado.
class _Gap extends StatelessWidget {
  const _Gap(this.height);

  final double height;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : LoginScreen.motionDuration,
      curve: Curves.easeOutCubic,
      height: height,
    );
  }
}

/// Fade de entrada para lo que aparece al cambiar de pestaña (los campos de
/// registro, un error nuevo); el alto lo anima el [MotionAwareSize] de
/// afuera.
class _FadeIn extends StatelessWidget {
  const _FadeIn({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: LoginScreen.motionDuration,
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(opacity: value, child: child),
      child: child,
    );
  }
}

/// Error del servidor debajo del botón: texto en loss, sin diálogo ni
/// snackbar. `liveRegion` para que VoiceOver lo lea al aparecer.
class _FormError extends StatelessWidget {
  const _FormError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Padding(
      padding: const EdgeInsets.only(top: AppDimens.sp12),
      child: Semantics(
        liveRegion: true,
        child: Text(
          message,
          key: LoginScreen.formErrorKey,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.loss,
                height: 1.4,
              ),
        ),
      ),
    );
  }
}
