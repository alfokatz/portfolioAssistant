import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/presentation/base/core/base_stateful_widget.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/auth/providers/reset_password_provider.dart';
import 'package:portfolio_assistant/presentation/flows/auth/ui/widgets/auth_password_requirements.dart';
import 'package:portfolio_assistant/presentation/flows/auth/ui/widgets/auth_password_strength_indicator.dart';
import 'package:portfolio_assistant/presentation/flows/auth/ui/widgets/auth_primary_button.dart';
import 'package:portfolio_assistant/presentation/flows/auth/ui/widgets/auth_text_field.dart';
import 'package:portfolio_assistant/presentation/flows/auth/utils/auth_validators.dart';
import 'package:portfolio_assistant/presentation/shared/loading/button_spinner.dart';

/// Contraseña nueva después de abrir el link de "restablecer contraseña".
///
/// Misma familia visual que el login: Porty arriba (más chico, es un paso
/// intermedio), campos de auth, CTA charcoal y errores en texto loss. El
/// router no deja salir de acá hasta guardarla o cancelar (cierra sesión).
class ResetPasswordScreen extends StatefulHookConsumerWidget {
  const ResetPasswordScreen({super.key});

  static const saveButtonKey = ValueKey('reset_password_save');
  static const cancelButtonKey = ValueKey('reset_password_cancel');
  static const formErrorKey = ValueKey('reset_password_form_error');

  static const avatarSize = 64.0;

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState
    extends BaseStatefulWidget<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _confirmFocus = FocusNode();

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  PortyHapticsService get _haptics => ref.read(portyHapticsServiceProvider);

  Future<void> _save() async {
    final form = _formKey.currentState;
    if (form == null) return;
    if (!form.validate()) {
      _haptics.authFailed();
      return;
    }
    await ref
        .read(resetPasswordControllerProvider.notifier)
        .save(_passwordController.text);
  }

  void _onChanged(String _) =>
      ref.read(resetPasswordControllerProvider.notifier).clearError();

  Widget _visibilityToggle({
    required bool obscure,
    required VoidCallback onToggle,
  }) {
    return IconButton(
      onPressed: onToggle,
      tooltip: obscure ? 'auth_show_password'.tr() : 'auth_hide_password'.tr(),
      icon: Icon(
        obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        color: context.customColors.textSecondary,
        size: AppDimens.iconMd,
      ),
    );
  }

  @override
  Widget buildView(BuildContext context) {
    ref.listen<String?>(
      resetPasswordControllerProvider.select((s) => s.formError),
      (previous, next) {
        if (next != null && next != previous) _haptics.authFailed();
      },
    );
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final state = ref.watch(resetPasswordControllerProvider);
    final controller = ref.read(resetPasswordControllerProvider.notifier);
    final email = ref.watch(supabaseAuthServiceProvider).currentUser?.email;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(
            AppDimens.pageHorizontal,
            AppDimens.sp32,
            AppDimens.pageHorizontal,
            AppDimens.sp32,
          ),
          child: AutofillGroup(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const PortyAvatar(
                        size: ResetPasswordScreen.avatarSize,
                        animated: true,
                      ),
                      const SizedBox(width: AppDimens.sp12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Semantics(
                              header: true,
                              child: Text(
                                'auth_reset_title'.tr(),
                                style: tt.titleLarge?.copyWith(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                  height: 1.2,
                                  letterSpacing: -0.5,
                                  color: colors.textPrimary,
                                ),
                              ),
                            ),
                            if (email != null)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: AppDimens.sp2,
                                ),
                                child: Text(
                                  email,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: tt.bodyMedium?.copyWith(
                                    color: colors.textSecondary,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppDimens.sp24),
                  Text(
                    'auth_reset_greeting'.tr(),
                    style: tt.bodyLarge?.copyWith(
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                      letterSpacing: -0.2,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppDimens.sp28),
                  AuthTextField(
                    controller: _passwordController,
                    obscureText: state.obscurePassword,
                    autocorrect: false,
                    enableSuggestions: false,
                    maxLength: 128,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.newPassword],
                    hintText: 'auth_new_password_placeholder'.tr(),
                    prefixIcon: Icons.lock_outline_rounded,
                    onChanged: _onChanged,
                    onFieldSubmitted: (_) => _confirmFocus.requestFocus(),
                    suffixIcon: _visibilityToggle(
                      obscure: state.obscurePassword,
                      onToggle: controller.toggleObscurePassword,
                    ),
                    validator: (value) => AuthValidators.newPassword(
                      value,
                    )?.tr(
                      namedArgs: {
                        'min': '${AuthValidators.passwordMinLength}',
                      },
                    ),
                  ),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _passwordController,
                    builder: (context, value, _) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AuthPasswordStrengthIndicator(password: value.text),
                        AuthPasswordRequirements(password: value.text),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppDimens.sp12),
                  AuthTextField(
                    controller: _confirmController,
                    focusNode: _confirmFocus,
                    obscureText: state.obscureConfirmPassword,
                    autocorrect: false,
                    enableSuggestions: false,
                    maxLength: 128,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.newPassword],
                    hintText: 'auth_confirm_password_placeholder'.tr(),
                    prefixIcon: Icons.lock_reset_rounded,
                    onChanged: _onChanged,
                    onFieldSubmitted: (_) => _save(),
                    suffixIcon: _visibilityToggle(
                      obscure: state.obscureConfirmPassword,
                      onToggle: controller.toggleObscureConfirmPassword,
                    ),
                    validator: (value) => AuthValidators.confirmPassword(
                      value,
                      _passwordController.text,
                    )?.tr(),
                  ),
                  const SizedBox(height: AppDimens.sp24),
                  AuthPrimaryButton(
                    key: ResetPasswordScreen.saveButtonKey,
                    label: 'auth_reset_save'.tr(),
                    isLoading: state.isSaving,
                    onPressed: state.isBusy ? null : _save,
                  ),
                  if (state.formError case final error?)
                    Padding(
                      padding: const EdgeInsets.only(top: AppDimens.sp12),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          error,
                          key: ResetPasswordScreen.formErrorKey,
                          textAlign: TextAlign.center,
                          style: tt.bodySmall?.copyWith(
                            color: colors.loss,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: AppDimens.sp8),
                  TextButton(
                    key: ResetPasswordScreen.cancelButtonKey,
                    onPressed: state.isBusy ? null : controller.cancel,
                    style: TextButton.styleFrom(
                      foregroundColor: colors.textSecondary,
                      minimumSize: const Size.fromHeight(AppDimens.touchTarget),
                    ),
                    child: state.isCancelling
                        ? ButtonSpinner.small(color: colors.textSecondary)
                        : Text(
                            'auth_reset_cancel'.tr(),
                            style: tt.bodyMedium?.copyWith(
                              color: colors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
