import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/sign_up_result.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:portfolio_assistant/presentation/flows/auth/providers/auth_provider.dart';
import 'package:portfolio_assistant/presentation/flows/auth/ui/login_screen.dart';
import 'package:portfolio_assistant/presentation/flows/auth/ui/reset_password_screen.dart';
import 'package:portfolio_assistant/presentation/flows/auth/ui/widgets/auth_check_email_panel.dart';
import 'package:portfolio_assistant/presentation/flows/auth/ui/widgets/auth_password_requirements.dart';
import 'package:portfolio_assistant/presentation/flows/auth/ui/widgets/social_sign_in_button.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Sin easy_localization cargado, `.tr()` devuelve la key: los textos se
/// buscan por key.
class _FakeAuthService implements SupabaseAuthService {
  final events = StreamController<AuthState>.broadcast();
  final calls = <String>[];

  SignUpResult signUpResult = SignUpResult.confirmationEmailSent;
  Object? signInError;
  Object? googleError;
  bool googleCompletes = false;
  Object? updatePasswordError;

  @override
  Stream<AuthState> get onAuthStateChange => events.stream;

  @override
  Session? get currentSession => null;

  @override
  User? get currentUser => const User(
    id: 'u1',
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    email: 'ana@mail.com',
    createdAt: '2026-10-01T00:00:00Z',
  );

  @override
  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    calls.add('signIn:$email');
    if (signInError case final error?) throw error;
  }

  @override
  Future<SignUpResult> signUpWithEmail({
    required String email,
    required String password,
    String? fullName,
  }) async {
    calls.add('signUp:$email:$fullName');
    return signUpResult;
  }

  @override
  Future<void> resendSignUpConfirmation({required String email}) async {
    calls.add('resend:$email');
  }

  @override
  Future<bool> signInWithGoogle() async {
    calls.add('google');
    if (googleError case final error?) throw error;
    return googleCompletes;
  }

  @override
  Future<void> resetPassword({required String email}) async {
    calls.add('reset:$email');
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    calls.add('updatePassword:$newPassword');
    if (updatePasswordError case final error?) throw error;
  }

  @override
  Future<void> signOut() async => calls.add('signOut');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Harness {
  _Harness()
    : auth = _FakeAuthService(),
      haptics = [] {
    container = ProviderContainer(
      overrides: [
        supabaseAuthServiceProvider.overrideWithValue(auth),
        portyHapticsServiceProvider.overrideWithValue(
          PortyHapticsService(
            enabled: true,
            performer: (pattern) async => haptics.add(pattern),
          ),
        ),
        appleSignInAvailableProvider.overrideWithValue(false),
      ],
    );
  }

  final _FakeAuthService auth;
  final List<PortyHapticPattern> haptics;
  late final ProviderContainer container;

  Widget app(Widget home) {
    final theme = ProviderContainer().read(themeDataLightProvider);
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: home,
      ),
    );
  }
}

void _useTallPhone(WidgetTester tester) {
  // Alto de sobra: el registro entero (y el checklist) sin scroll.
  tester.view.physicalSize = const Size(400, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Finder get _fields => find.byType(TextFormField);
Finder get _button => find.byKey(LoginScreen.primaryButtonKey);

Future<void> _tapPrimary(WidgetTester tester) async {
  await tester.tap(_button);
  await tester.pump(); // post-frame del tap
  await tester.pump();
}

/// Los toasts de éxito se esconden solos con un timer (AlertProvider).
Future<void> _flushAlerts(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 400));

String? _formError(WidgetTester tester) {
  final finder = find.byKey(LoginScreen.formErrorKey);
  if (finder.evaluate().isEmpty) return null;
  return tester.widget<Text>(finder).data;
}

void main() {
  setUpAll(() => PortyAvatar.ambientMotion = false);
  tearDownAll(() => PortyAvatar.ambientMotion = true);

  group('sign up', () {
    Future<void> fillSignUp(WidgetTester tester, {String? password}) async {
      await tester.tap(find.text('auth_sign_up_tab'));
      await tester.pumpAndSettle();
      await tester.enterText(_fields.at(0), 'Ana Pérez');
      await tester.enterText(_fields.at(1), '  Ana@Mail.com ');
      await tester.enterText(_fields.at(2), password ?? 'Secreta123');
      await tester.enterText(_fields.at(3), password ?? 'Secreta123');
      await tester.pump();
    }

    testWidgets('enforces the password policy with a live checklist', (
      tester,
    ) async {
      _useTallPhone(tester);
      final h = _Harness();
      await tester.pumpWidget(h.app(const LoginScreen()));
      await fillSignUp(tester, password: 'secreta');

      expect(find.byType(AuthPasswordRequirements), findsOneWidget);
      expect(find.text('auth_password_req_length'), findsOneWidget);
      expect(find.text('auth_password_req_case'), findsOneWidget);
      expect(find.text('auth_password_req_digit'), findsOneWidget);

      await _tapPrimary(tester);
      await tester.pumpAndSettle();
      expect(find.text('auth_password_min_length'), findsOneWidget);
      expect(h.auth.calls, isEmpty);
    });

    for (final result in [
      SignUpResult.confirmationEmailSent,
      SignUpResult.emailAlreadyRegistered,
    ]) {
      testWidgets('$result shows the same "check your email" screen '
          '(no account enumeration)', (tester) async {
        _useTallPhone(tester);
        final h = _Harness()..auth.signUpResult = result;
        await tester.pumpWidget(h.app(const LoginScreen()));
        await fillSignUp(tester);

        await _tapPrimary(tester);
        await tester.pump();

        expect(h.auth.calls, ['signUp:ana@mail.com:Ana Pérez']);
        expect(find.byType(AuthCheckEmailPanel), findsOneWidget);
        expect(find.text('auth_check_email_title'), findsOneWidget);
        expect(find.textContaining('ana@mail.com', findRichText: true),
            findsOneWidget);
        expect(find.byType(Form), findsNothing);

        // Reenviar espera el cooldown de emails.
        final resend = tester.widget<TextButton>(
          find.byKey(AuthCheckEmailPanel.resendButtonKey),
        );
        expect(resend.onPressed, isNull);
        expect(find.text('auth_resend_in'), findsOneWidget);
        await tester.pump(AuthController.emailCooldown);
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('auth_resend_confirmation'), findsOneWidget);
        await tester.tap(find.byKey(AuthCheckEmailPanel.resendButtonKey));
        await tester.pump();
        expect(h.auth.calls.last, 'resend:ana@mail.com');

        await tester.tap(find.byKey(AuthCheckEmailPanel.backButtonKey));
        await tester.pump();
        expect(find.byType(Form), findsOneWidget);
        expect(find.text('auth_forgot_password'), findsOneWidget);
        // Las contraseñas no quedan cargadas al volver.
        expect(
          tester.widget<EditableText>(find.byType(EditableText).at(1))
              .controller
              .text,
          isEmpty,
        );
        await _flushAlerts(tester);
      });
    }
  });

  group('sign in', () {
    testWidgets('locks the form after 5 wrong passwords, with a countdown', (
      tester,
    ) async {
      _useTallPhone(tester);
      final h = _Harness()
        ..auth.signInError = const AuthException(
          'Invalid login credentials',
          code: 'invalid_credentials',
        );
      await tester.pumpWidget(h.app(const LoginScreen()));
      await tester.enterText(_fields.at(0), 'ana@mail.com');

      for (var i = 0; i < 5; i++) {
        await tester.enterText(_fields.at(1), 'mala$i');
        await _tapPrimary(tester);
        await tester.pump();
      }

      expect(h.auth.calls.length, 5);
      expect(_formError(tester), 'auth_error_too_many_attempts');
      expect(find.text('auth_locked_retry_in'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.descendant(of: _button, matching: find.byType(FilledButton)),
      );
      expect(button.onPressed, isNull);

      // Escribir no levanta el bloqueo.
      await tester.enterText(_fields.at(1), 'otra');
      await tester.pump();
      expect(_formError(tester), 'auth_error_too_many_attempts');

      // A los 30 s se puede volver a intentar.
      await tester.pump(const Duration(seconds: 31));
      expect(find.text('auth_sign_in'), findsWidgets);
      h.auth.signInError = null;
      await _tapPrimary(tester);
      await tester.pump();
      expect(h.auth.calls.length, 6);
    });

    testWidgets('an unconfirmed account goes to "check your email" with '
        'resend available right away', (tester) async {
      _useTallPhone(tester);
      final h = _Harness()
        ..auth.signInError = const AuthException(
          'Email not confirmed',
          code: 'email_not_confirmed',
        );
      await tester.pumpWidget(h.app(const LoginScreen()));
      await tester.enterText(_fields.at(0), 'ana@mail.com');
      await tester.enterText(_fields.at(1), 'Secreta123');
      await _tapPrimary(tester);
      await tester.pump();

      expect(find.byType(AuthCheckEmailPanel), findsOneWidget);
      expect(
        find.textContaining(
          'auth_check_email_not_confirmed_prefix',
          findRichText: true,
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(AuthCheckEmailPanel.resendButtonKey));
      await tester.pump();
      expect(h.auth.calls.last, 'resend:ana@mail.com');
      await _flushAlerts(tester);
    });

    testWidgets('server messages are never shown raw', (tester) async {
      _useTallPhone(tester);
      final h = _Harness()
        ..auth.signInError = const AuthException(
          'Database error querying schema',
          statusCode: '500',
        );
      await tester.pumpWidget(h.app(const LoginScreen()));
      await tester.enterText(_fields.at(0), 'ana@mail.com');
      await tester.enterText(_fields.at(1), 'Secreta123');
      await _tapPrimary(tester);
      await tester.pump();

      expect(_formError(tester), 'auth_error_generic');
    });

    testWidgets('an expired email link shows up in the login', (
      tester,
    ) async {
      _useTallPhone(tester);
      final h = _Harness();
      await tester.pumpWidget(h.app(const LoginScreen()));
      h.auth.events.addError(
        const AuthException('Flow state expired', code: 'flow_state_expired'),
      );
      await tester.pump();
      expect(_formError(tester), 'auth_error_link_expired');
    });
  });

  group('forgot password', () {
    testWidgets('validates the email, then sends once per minute', (
      tester,
    ) async {
      _useTallPhone(tester);
      final h = _Harness();
      await tester.pumpWidget(h.app(const LoginScreen()));

      await tester.enterText(_fields.at(0), 'ana@mail');
      await tester.tap(find.byKey(LoginScreen.forgotPasswordKey));
      await tester.pump();
      expect(find.text('auth_email_invalid'), findsOneWidget);
      expect(h.auth.calls, isEmpty);

      await tester.enterText(_fields.at(0), 'ana@mail.com');
      await tester.tap(find.byKey(LoginScreen.forgotPasswordKey));
      await tester.pump();
      expect(h.auth.calls, ['reset:ana@mail.com']);
      expect(find.text('auth_reset_again_in'), findsOneWidget);

      await tester.pump(const Duration(seconds: 61));
      expect(find.text('auth_forgot_password'), findsOneWidget);
    });
  });

  group('Google', () {
    testWidgets('closing the browser is silent', (tester) async {
      _useTallPhone(tester);
      final h = _Harness();
      await tester.pumpWidget(h.app(const LoginScreen()));
      await tester.tap(find.byType(SocialSignInButton));
      await tester.pump();

      expect(h.auth.calls, ['google']);
      expect(_formError(tester), isNull);
      expect(h.haptics, isEmpty);
    });

    testWidgets('a provider error shows a friendly message', (tester) async {
      _useTallPhone(tester);
      final h = _Harness()
        ..auth.googleError = const AuthException(
          'Unsupported provider: provider is not enabled',
          code: 'provider_disabled',
        );
      await tester.pumpWidget(h.app(const LoginScreen()));
      await tester.tap(find.byType(SocialSignInButton));
      await tester.pump();

      expect(_formError(tester), 'auth_error_provider_disabled');
      expect(h.haptics, [PortyHapticPattern.doubleLight]);
    });
  });

  group('ResetPasswordScreen', () {
    testWidgets('requires a policy-compliant, confirmed password', (
      tester,
    ) async {
      _useTallPhone(tester);
      final h = _Harness();
      await tester.pumpWidget(h.app(const ResetPasswordScreen()));
      expect(find.text('ana@mail.com'), findsOneWidget);

      await tester.enterText(_fields.at(0), 'Secreta1');
      await tester.enterText(_fields.at(1), 'Secreta2');
      await tester.tap(find.byKey(ResetPasswordScreen.saveButtonKey));
      await tester.pump();

      expect(find.text('auth_password_mismatch'), findsOneWidget);
      expect(h.auth.calls, isEmpty);
      expect(h.haptics, [PortyHapticPattern.doubleLight]);
    });

    testWidgets('saving the new password ends the recovery', (tester) async {
      _useTallPhone(tester);
      final h = _Harness();
      final recovery = h.container.read(passwordRecoveryProvider.notifier);
      h.auth.events.add(const AuthState(AuthChangeEvent.passwordRecovery, null));
      await tester.pumpWidget(h.app(const ResetPasswordScreen()));
      await tester.pump();
      expect(recovery.state, isTrue);

      await tester.enterText(_fields.at(0), 'Nueva1234');
      await tester.enterText(_fields.at(1), 'Nueva1234');
      await tester.tap(find.byKey(ResetPasswordScreen.saveButtonKey));
      await tester.pump();

      expect(h.auth.calls, ['updatePassword:Nueva1234']);
      expect(recovery.state, isFalse);
      await _flushAlerts(tester);
    });

    testWidgets('a rejected password stays on screen with the reason', (
      tester,
    ) async {
      _useTallPhone(tester);
      final h = _Harness()
        ..auth.updatePasswordError = const AuthException(
          'New password should be different',
          code: 'same_password',
        );
      await tester.pumpWidget(h.app(const ResetPasswordScreen()));
      await tester.enterText(_fields.at(0), 'Nueva1234');
      await tester.enterText(_fields.at(1), 'Nueva1234');
      await tester.tap(find.byKey(ResetPasswordScreen.saveButtonKey));
      await tester.pump();

      final error = tester.widget<Text>(
        find.byKey(ResetPasswordScreen.formErrorKey),
      );
      expect(error.data, 'auth_error_same_password');
    });

    testWidgets('"not now" signs out instead of leaving the recovery session '
        'open', (tester) async {
      _useTallPhone(tester);
      final h = _Harness();
      await tester.pumpWidget(h.app(const ResetPasswordScreen()));
      await tester.tap(find.byKey(ResetPasswordScreen.cancelButtonKey));
      await tester.pump();
      expect(h.auth.calls, ['signOut']);
    });
  });
}
