import 'package:easy_localization/easy_localization.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/config/supabase/sign_up_result.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/config/supabase/supabase_error_mapper.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';

class AuthUiState {
  final bool isLoading;
  final bool isSignUpMode;

  const AuthUiState({
    this.isLoading = false,
    this.isSignUpMode = false,
  });

  AuthUiState copyWith({
    bool? isLoading,
    bool? isSignUpMode,
  }) {
    return AuthUiState(
      isLoading: isLoading ?? this.isLoading,
      isSignUpMode: isSignUpMode ?? this.isSignUpMode,
    );
  }
}

class AuthController extends StateNotifier<AuthUiState> {
  AuthController(this._authService, this._ref) : super(const AuthUiState());

  final SupabaseAuthService _authService;
  final Ref _ref;

  void toggleMode() {
    if (state.isLoading) return;
    state = state.copyWith(isSignUpMode: !state.isSignUpMode);
  }

  void setSignInMode() {
    if (state.isLoading || !state.isSignUpMode) return;
    state = state.copyWith(isSignUpMode: false);
  }

  void setSignUpMode() {
    if (state.isLoading || state.isSignUpMode) return;
    state = state.copyWith(isSignUpMode: true);
  }

  Future<void> submitEmail({
    required String email,
    required String password,
    String? fullName,
  }) async {
    if (state.isSignUpMode) {
      final result = await _signUpWithEmail(
        email: email,
        password: password,
        fullName: fullName,
      );
      if (result == null) return;

      switch (result) {
        case SignUpResult.signedIn:
          return;
        case SignUpResult.confirmationEmailSent:
          _ref.read(alertProvider.notifier).showSuccess(
                message: 'auth_sign_up_confirmation_sent'.tr(),
              );
          state = state.copyWith(isSignUpMode: false);
        case SignUpResult.emailAlreadyRegistered:
          _ref.read(alertProvider.notifier).showWarning(
                message: 'auth_email_already_registered'.tr(),
              );
          state = state.copyWith(isSignUpMode: false);
      }
      return;
    }

    _showErrorIfNeeded(
      await signInWithEmail(email: email, password: password),
    );
  }

  Future<void> submitGoogleSignIn() async {
    _showErrorIfNeeded(await signInWithGoogle());
  }

  Future<void> submitAppleSignIn() async {
    _showErrorIfNeeded(await signInWithApple());
  }

  Future<void> requestPasswordReset({required String email}) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty) {
      _ref.read(alertProvider.notifier).showError(
            message: 'auth_email_required'.tr(),
          );
      return;
    }
    if (!trimmed.contains('@')) {
      _ref.read(alertProvider.notifier).showError(
            message: 'auth_email_invalid'.tr(),
          );
      return;
    }

    final error = await _run(() => _authService.resetPassword(email: trimmed));
    if (error != null) {
      _showErrorIfNeeded(error);
      return;
    }

    _ref.read(alertProvider.notifier).showSuccess(
          message: 'auth_reset_password_sent'.tr(),
        );
  }

  void _showErrorIfNeeded(HttpError? error) {
    if (error == null) return;
    _ref.read(alertProvider.notifier).showError(message: error.message);
  }

  Future<HttpError?> signInWithEmail({
    required String email,
    required String password,
  }) {
    return _run(() => _authService.signInWithEmail(
          email: email,
          password: password,
        ));
  }

  Future<SignUpResult?> _signUpWithEmail({
    required String email,
    required String password,
    String? fullName,
  }) async {
    state = state.copyWith(isLoading: true);
    try {
      return await _authService.signUpWithEmail(
        email: email,
        password: password,
        fullName: fullName,
      );
    } catch (error) {
      _showErrorIfNeeded(SupabaseErrorMapper.fromObject(error));
      return null;
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<HttpError?> signInWithGoogle() {
    return _run(_authService.signInWithGoogle);
  }

  Future<HttpError?> signInWithApple() {
    return _run(_authService.signInWithApple);
  }

  Future<HttpError?> signOut() {
    return _run(_authService.signOut);
  }

  Future<HttpError?> _run(Future<void> Function() action) async {
    state = state.copyWith(isLoading: true);
    try {
      await action();
      return null;
    } catch (error) {
      return SupabaseErrorMapper.fromObject(error);
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthUiState>(
  (ref) => AuthController(
    ref.watch(supabaseAuthServiceProvider),
    ref,
  ),
);
