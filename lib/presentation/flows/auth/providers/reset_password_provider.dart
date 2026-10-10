import 'package:easy_localization/easy_localization.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';
import 'package:portfolio_assistant/presentation/flows/auth/utils/auth_error_messages.dart';

class ResetPasswordUiState {
  final bool isSaving;
  final bool isCancelling;
  final bool obscurePassword;
  final bool obscureConfirmPassword;

  /// Error del servidor, debajo del botón (como en el login).
  final String? formError;

  const ResetPasswordUiState({
    this.isSaving = false,
    this.isCancelling = false,
    this.obscurePassword = true,
    this.obscureConfirmPassword = true,
    this.formError,
  });

  bool get isBusy => isSaving || isCancelling;

  static const _keep = Object();

  ResetPasswordUiState copyWith({
    bool? isSaving,
    bool? isCancelling,
    bool? obscurePassword,
    bool? obscureConfirmPassword,
    Object? formError = _keep,
  }) {
    return ResetPasswordUiState(
      isSaving: isSaving ?? this.isSaving,
      isCancelling: isCancelling ?? this.isCancelling,
      obscurePassword: obscurePassword ?? this.obscurePassword,
      obscureConfirmPassword:
          obscureConfirmPassword ?? this.obscureConfirmPassword,
      formError: identical(formError, _keep)
          ? this.formError
          : formError as String?,
    );
  }
}

class ResetPasswordController extends StateNotifier<ResetPasswordUiState> {
  ResetPasswordController(this._authService, this._ref)
    : super(const ResetPasswordUiState());

  final SupabaseAuthService _authService;
  final Ref _ref;

  void toggleObscurePassword() =>
      state = state.copyWith(obscurePassword: !state.obscurePassword);

  void toggleObscureConfirmPassword() => state = state.copyWith(
    obscureConfirmPassword: !state.obscureConfirmPassword,
  );

  void clearError() {
    if (state.formError != null) state = state.copyWith(formError: null);
  }

  /// Guarda la contraseña nueva. Al terminar, el router sale de la pantalla
  /// solo (deja de estar en recovery).
  Future<void> save(String password) async {
    if (state.isBusy) return;
    state = state.copyWith(isSaving: true, formError: null);
    try {
      await _authService.updatePassword(password);
      if (!mounted) return;
      _ref.read(alertProvider.notifier).showSuccess(
            message: 'auth_password_updated'.tr(),
          );
      _ref.read(passwordRecoveryProvider.notifier).complete();
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(
        formError: AuthFailure.from(error).messageKey.tr(),
      );
    } finally {
      if (mounted) state = state.copyWith(isSaving: false);
    }
  }

  /// No quiere cambiarla ahora: se cierra la sesión de recovery (no se
  /// deja una sesión abierta que nunca pidió la contraseña).
  Future<void> cancel() async {
    if (state.isBusy) return;
    state = state.copyWith(isCancelling: true, formError: null);
    try {
      await _authService.signOut();
    } catch (_) {
      // signOut ya borró la sesión local aunque falle la llamada al server.
    } finally {
      if (mounted) state = state.copyWith(isCancelling: false);
    }
  }
}

final resetPasswordControllerProvider = StateNotifierProvider.autoDispose<
  ResetPasswordController,
  ResetPasswordUiState
>(
  (ref) => ResetPasswordController(ref.watch(supabaseAuthServiceProvider), ref),
);
