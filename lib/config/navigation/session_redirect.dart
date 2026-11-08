import 'package:portfolio_assistant/presentation/flows/auth/nav/auth_router.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/nav/onboarding_router.dart';

/// En qué punto de la sesión está el usuario. Decide a qué parte de la
/// app puede entrar (ver [SessionRedirect.target]).
enum SessionPhase {
  /// Sin sesión: solo el login.
  signedOut,

  /// Entró con el link de "restablecer contraseña": primero elige una
  /// nueva. La sesión de recovery no habilita el resto de la app.
  recoveringPassword,

  /// Con sesión, sin terminar el onboarding.
  onboarding,

  /// La app completa.
  ready;

  static SessionPhase of({
    required bool authenticated,
    required bool recoveringPassword,
    required bool onboardingDone,
  }) {
    if (!authenticated) return SessionPhase.signedOut;
    if (recoveringPassword) return SessionPhase.recoveringPassword;
    if (!onboardingDone) return SessionPhase.onboarding;
    return SessionPhase.ready;
  }
}

/// El redirect del router como función pura: a dónde mandar a alguien en
/// [phase] que quiere ir a [location]. `null`: puede quedarse.
abstract final class SessionRedirect {
  /// [homePath] es la ruta de la Home ya resuelta (`namedLocation`).
  static String? target(
    SessionPhase phase, {
    required String location,
    required String homePath,
  }) {
    return switch (phase) {
      SessionPhase.signedOut =>
        location == AuthRouter.loginPath ? null : AuthRouter.loginPath,
      SessionPhase.recoveringPassword =>
        location == AuthRouter.resetPasswordPath
            ? null
            : AuthRouter.resetPasswordPath,
      SessionPhase.onboarding =>
        location == OnboardingRouter.path ? null : OnboardingRouter.path,
      SessionPhase.ready => _entryOnly.contains(location) ? homePath : null,
    };
  }

  /// Pantallas de entrada: con la app completa no tienen nada que hacer.
  static const _entryOnly = {
    '/',
    AuthRouter.loginPath,
    AuthRouter.resetPasswordPath,
    OnboardingRouter.path,
  };
}
