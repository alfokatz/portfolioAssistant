import 'dart:async';

import 'package:clock/clock.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/config/supabase/auth_providers_config.dart';
import 'package:portfolio_assistant/config/supabase/sign_up_result.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/config/supabase/supabase_error_mapper.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';
import 'package:portfolio_assistant/presentation/flows/auth/utils/auth_error_messages.dart';
import 'package:portfolio_assistant/presentation/flows/auth/utils/auth_validators.dart';
import 'package:portfolio_assistant/presentation/flows/auth/utils/login_attempt_limiter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState;

/// Qué acción está en curso: cada botón muestra su propio spinner y todos
/// quedan deshabilitados.
enum AuthAction { email, google, apple, passwordReset, resend }

/// Por qué se muestra "Revisá tu email".
enum PendingConfirmationReason {
  /// Se acaba de registrar (o el email ya tenía cuenta: se muestra lo mismo
  /// para no revelar qué emails están registrados).
  signedUp,

  /// Intentó entrar con una cuenta que todavía no confirmó.
  notConfirmed,
}

class AuthUiState {
  final AuthAction? activeAction;
  final bool isSignUpMode;
  final bool obscurePassword;
  final bool obscureConfirmPassword;

  /// Error del servidor (credenciales, red, etc.): va en texto debajo del
  /// botón principal, nunca en un diálogo ni en un snackbar.
  final String? formError;

  /// Error del email al pedir "¿Olvidaste tu contraseña?" sin un email
  /// válido: se muestra debajo del campo, como un error de validación.
  final String? emailError;

  /// Email al que se mandó la confirmación: con valor, la pantalla muestra
  /// "Revisá tu email" en vez del formulario.
  final String? pendingConfirmationEmail;
  final PendingConfirmationReason pendingConfirmationReason;

  /// Bloqueo por demasiados intentos fallidos (ver [LoginAttemptLimiter]).
  final DateTime? lockedUntil;

  /// Hasta cuándo no se puede volver a pedir el email de confirmación o de
  /// reset (el rate limit de emails de Supabase es bajo).
  final DateTime? resendAvailableAt;
  final DateTime? passwordResetAvailableAt;

  const AuthUiState({
    this.activeAction,
    this.isSignUpMode = false,
    this.obscurePassword = true,
    this.obscureConfirmPassword = true,
    this.formError,
    this.emailError,
    this.pendingConfirmationEmail,
    this.pendingConfirmationReason = PendingConfirmationReason.signedUp,
    this.lockedUntil,
    this.resendAvailableAt,
    this.passwordResetAvailableAt,
  });

  bool get isLoading => activeAction != null;

  static const _keep = Object();

  AuthUiState copyWith({
    Object? activeAction = _keep,
    bool? isSignUpMode,
    bool? obscurePassword,
    bool? obscureConfirmPassword,
    Object? formError = _keep,
    Object? emailError = _keep,
    Object? pendingConfirmationEmail = _keep,
    PendingConfirmationReason? pendingConfirmationReason,
    Object? lockedUntil = _keep,
    Object? resendAvailableAt = _keep,
    Object? passwordResetAvailableAt = _keep,
  }) {
    T? pick<T>(Object? value, T? current) =>
        identical(value, _keep) ? current : value as T?;

    return AuthUiState(
      activeAction: pick(activeAction, this.activeAction),
      isSignUpMode: isSignUpMode ?? this.isSignUpMode,
      obscurePassword: obscurePassword ?? this.obscurePassword,
      obscureConfirmPassword:
          obscureConfirmPassword ?? this.obscureConfirmPassword,
      formError: pick(formError, this.formError),
      emailError: pick(emailError, this.emailError),
      pendingConfirmationEmail: pick(
        pendingConfirmationEmail,
        this.pendingConfirmationEmail,
      ),
      pendingConfirmationReason:
          pendingConfirmationReason ?? this.pendingConfirmationReason,
      lockedUntil: pick(lockedUntil, this.lockedUntil),
      resendAvailableAt: pick(resendAvailableAt, this.resendAvailableAt),
      passwordResetAvailableAt: pick(
        passwordResetAvailableAt,
        this.passwordResetAvailableAt,
      ),
    );
  }
}

class AuthController extends StateNotifier<AuthUiState> {
  AuthController(
    this._authService,
    this._ref, {
    LoginAttemptLimiter? limiter,
    DateTime Function()? now,
  }) : _now = now ?? clock.now,
       _limiter = limiter ?? LoginAttemptLimiter(now: now),
       super(const AuthUiState()) {
    // Un link de email vencido o ya usado (confirmación o reset) llega como
    // error del stream de auth: se muestra en el login.
    _authErrors = _authService.onAuthStateChange.listen(
      (AuthState _) {},
      onError: (Object error) {
        if (!mounted) return;
        state = state.copyWith(
          formError: AuthFailure.linkExpired.messageKey.tr(),
        );
      },
    );
  }

  /// Espera entre emails de confirmación / reset. Coincide con el mínimo
  /// por defecto de Supabase (`max_frequency`) para que no responda 429.
  static const emailCooldown = Duration(seconds: 60);

  final SupabaseAuthService _authService;
  final Ref _ref;
  final LoginAttemptLimiter _limiter;
  final DateTime Function() _now;
  late final StreamSubscription<AuthState> _authErrors;

  @override
  void dispose() {
    unawaited(_authErrors.cancel());
    super.dispose();
  }

  void toggleMode() {
    if (state.isSignUpMode) {
      setSignInMode();
    } else {
      setSignUpMode();
    }
  }

  void setSignInMode() {
    if (state.isLoading || !state.isSignUpMode) return;
    state = state.copyWith(
      isSignUpMode: false,
      formError: null,
      emailError: null,
    );
  }

  void setSignUpMode() {
    if (state.isLoading || state.isSignUpMode) return;
    state = state.copyWith(
      isSignUpMode: true,
      formError: null,
      emailError: null,
    );
  }

  /// El usuario volvió a escribir: el error anterior ya no aplica (salvo el
  /// del bloqueo, que sigue vigente hasta que venza).
  void clearErrors() {
    if (state.formError == null && state.emailError == null) return;
    if (_limiter.isLocked) {
      state = state.copyWith(emailError: null);
      return;
    }
    state = state.copyWith(formError: null, emailError: null);
  }

  void toggleObscurePassword() {
    state = state.copyWith(obscurePassword: !state.obscurePassword);
  }

  void toggleObscureConfirmPassword() {
    state = state.copyWith(
      obscureConfirmPassword: !state.obscureConfirmPassword,
    );
  }

  Future<void> submitEmail({
    required String email,
    required String password,
    String? fullName,
  }) async {
    if (state.isLoading) return;
    final normalized = AuthValidators.normalizeEmail(email);

    if (state.isSignUpMode) {
      final result = await _guard(
        AuthAction.email,
        () => _authService.signUpWithEmail(
          email: normalized,
          password: password,
          fullName: fullName,
        ),
      );
      if (result == null) return;

      switch (result) {
        case SignUpResult.signedIn:
          return;
        // Mismo mensaje en los dos casos: no se revela si el email ya tenía
        // una cuenta (el que es dueño del email se entera por el correo).
        case SignUpResult.confirmationEmailSent:
        case SignUpResult.emailAlreadyRegistered:
          _showPendingConfirmation(
            normalized,
            PendingConfirmationReason.signedUp,
          );
      }
      return;
    }

    if (_limiter.isLocked) {
      _showLockout();
      return;
    }

    final ok = await _guard(
      AuthAction.email,
      () async {
        await _authService.signInWithEmail(
          email: normalized,
          password: password,
        );
        return true;
      },
      onFailure: (failure) {
        switch (failure) {
          case AuthFailure.invalidCredentials:
            if (_limiter.registerFailure() != null) {
              _showLockout();
              return true;
            }
            return false;
          case AuthFailure.emailNotConfirmed:
            _showPendingConfirmation(
              normalized,
              PendingConfirmationReason.notConfirmed,
              // No se mandó nada nuevo: puede reenviarlo ya.
              startCooldown: false,
            );
            return true;
          default:
            return false;
        }
      },
    );
    if (ok != null) _limiter.reset();
  }

  Future<void> submitGoogleSignIn() async {
    if (state.isLoading) return;
    await _guard(AuthAction.google, _authService.signInWithGoogle);
  }

  Future<void> submitAppleSignIn() async {
    if (state.isLoading) return;
    await _guard(AuthAction.apple, _authService.signInWithApple);
  }

  Future<void> requestPasswordReset({required String email}) async {
    if (state.isLoading) return;
    final error = AuthValidators.email(email);
    if (error != null) {
      state = state.copyWith(emailError: error.tr(), formError: null);
      return;
    }
    if (_isCoolingDown(state.passwordResetAvailableAt)) return;

    final ok = await _guard(
      AuthAction.passwordReset,
      () async {
        await _authService.resetPassword(email: email);
        return true;
      },
    );
    if (ok == null) return;

    state = state.copyWith(
      passwordResetAvailableAt: _now().add(emailCooldown),
    );
    _ref.read(alertProvider.notifier).showSuccess(
          message: 'auth_reset_password_sent'.tr(),
        );
  }

  /// Reenvía el email de "confirmá tu cuenta" (pantalla de email
  /// pendiente).
  Future<void> resendConfirmation() async {
    final email = state.pendingConfirmationEmail;
    if (email == null || state.isLoading) return;
    if (_isCoolingDown(state.resendAvailableAt)) return;

    final ok = await _guard(
      AuthAction.resend,
      () async {
        await _authService.resendSignUpConfirmation(email: email);
        return true;
      },
    );
    if (ok == null) return;

    state = state.copyWith(resendAvailableAt: _now().add(emailCooldown));
    _ref.read(alertProvider.notifier).showSuccess(
          message: 'auth_confirmation_resent'.tr(),
        );
  }

  /// "Volver a iniciar sesión" desde la pantalla de email pendiente.
  void leavePendingConfirmation() {
    if (state.isLoading) return;
    state = state.copyWith(
      pendingConfirmationEmail: null,
      isSignUpMode: false,
      formError: null,
      emailError: null,
    );
  }

  Future<HttpError?> signOut() async {
    try {
      await _authService.signOut();
      return null;
    } catch (error) {
      return SupabaseErrorMapper.fromObject(error);
    }
  }

  void _showPendingConfirmation(
    String email,
    PendingConfirmationReason reason, {
    bool startCooldown = true,
  }) {
    state = state.copyWith(
      pendingConfirmationEmail: email,
      pendingConfirmationReason: reason,
      formError: null,
      emailError: null,
      resendAvailableAt: startCooldown ? _now().add(emailCooldown) : null,
    );
  }

  void _showLockout() {
    state = state.copyWith(
      lockedUntil: _limiter.lockedUntil,
      formError: 'auth_error_too_many_attempts'.tr(),
    );
  }

  bool _isCoolingDown(DateTime? availableAt) =>
      availableAt != null && _now().isBefore(availableAt);

  /// Corre [run] con su spinner. Devuelve el resultado (las acciones sin
  /// valor devuelven `true`), o `null` si falló (el error ya quedó en el estado). [onFailure] puede manejar un
  /// caso particular: si devuelve `true`, no se muestra el mensaje genérico.
  Future<T?> _guard<T>(
    AuthAction action,
    Future<T> Function() run, {
    bool Function(AuthFailure failure)? onFailure,
  }) async {
    state = state.copyWith(
      activeAction: action,
      formError: null,
      emailError: null,
    );
    try {
      return await run();
    } catch (error) {
      if (!mounted) return null;
      final failure = AuthFailure.from(error);
      final handled = onFailure?.call(failure) ?? false;
      if (!handled) {
        state = state.copyWith(formError: failure.messageKey.tr());
      }
      return null;
    } finally {
      if (mounted) state = state.copyWith(activeAction: null);
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

/// Si el login muestra "Continuar con Apple". Provider (y no la constante
/// directa) para que los tests y los screenshots puedan prenderlo.
final appleSignInAvailableProvider = Provider<bool>(
  (ref) => AuthProvidersConfig.showsAppleSignIn(defaultTargetPlatform),
);
