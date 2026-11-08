import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/config/navigation/session_redirect.dart';

void main() {
  const home = '/home';
  const login = '/login';
  const reset = '/reset-password';
  const onboarding = '/onboarding';
  const goals = '/goals';

  String? go(SessionPhase phase, String location) =>
      SessionRedirect.target(phase, location: location, homePath: home);

  group('SessionPhase.of', () {
    test('sin sesión gana sobre todo lo demás', () {
      expect(
        SessionPhase.of(
          authenticated: false,
          recoveringPassword: true,
          onboardingDone: false,
        ),
        SessionPhase.signedOut,
      );
    });

    test('recovery gana sobre el onboarding', () {
      expect(
        SessionPhase.of(
          authenticated: true,
          recoveringPassword: true,
          onboardingDone: false,
        ),
        SessionPhase.recoveringPassword,
      );
    });

    test('onboarding y lista', () {
      expect(
        SessionPhase.of(
          authenticated: true,
          recoveringPassword: false,
          onboardingDone: false,
        ),
        SessionPhase.onboarding,
      );
      expect(
        SessionPhase.of(
          authenticated: true,
          recoveringPassword: false,
          onboardingDone: true,
        ),
        SessionPhase.ready,
      );
    });
  });

  group('SessionRedirect.target', () {
    test('sin sesión: todo va al login', () {
      for (final l in ['/', reset, onboarding, home, goals]) {
        expect(go(SessionPhase.signedOut, l), login, reason: l);
      }
      expect(go(SessionPhase.signedOut, login), isNull);
    });

    test('recuperando contraseña: solo la pantalla de reset', () {
      for (final l in ['/', login, onboarding, home, goals]) {
        expect(go(SessionPhase.recoveringPassword, l), reset, reason: l);
      }
      expect(go(SessionPhase.recoveringPassword, reset), isNull);
    });

    test('onboarding sin terminar: siempre al onboarding', () {
      for (final l in ['/', login, reset, home, goals]) {
        expect(go(SessionPhase.onboarding, l), onboarding, reason: l);
      }
      expect(go(SessionPhase.onboarding, onboarding), isNull);
    });

    test('lista: las pantallas de entrada van a la Home, el resto queda', () {
      for (final l in ['/', login, reset, onboarding]) {
        expect(go(SessionPhase.ready, l), home, reason: l);
      }
      expect(go(SessionPhase.ready, home), isNull);
      expect(go(SessionPhase.ready, goals), isNull);
    });
  });
}
