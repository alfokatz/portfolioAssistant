import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/sign_up_result.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/typewriter_text.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:portfolio_assistant/presentation/flows/auth/providers/auth_provider.dart';
import 'package:portfolio_assistant/presentation/flows/auth/ui/login_screen.dart';
import 'package:portfolio_assistant/presentation/flows/auth/ui/widgets/apple_sign_in_button.dart';
import 'package:portfolio_assistant/presentation/flows/auth/ui/widgets/auth_porty_header.dart';
import 'package:portfolio_assistant/presentation/flows/auth/ui/widgets/social_sign_in_button.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Sin easy_localization cargado, `.tr()` devuelve la key: los textos se
/// buscan por key.
const _signInGreeting = 'auth_greeting_sign_in';
const _signUpGreeting = 'auth_greeting_sign_up';

/// iPhone SE (2.ª/3.ª gen.) en puntos, con su status bar.
const _seSize = Size(375, 667);
const _seStatusBar = 20.0;

/// Teclado de email de iOS en un SE: 216 de teclas + 44 de la barra de
/// sugerencias / autofill.
const _seKeyboard = 260.0;

class _FakeAuthService implements SupabaseAuthService {
  final sessions = StreamController<AuthState>.broadcast();
  Completer<void>? pendingSignIn;

  @override
  Stream<AuthState> get onAuthStateChange => sessions.stream;

  @override
  Session? get currentSession => null;

  @override
  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) {
    return (pendingSignIn = Completer<void>()).future;
  }

  @override
  Future<SignUpResult> signUpWithEmail({
    required String email,
    required String password,
    String? fullName,
  }) async => SignUpResult.confirmationEmailSent;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Harness {
  _Harness({bool appleAvailable = false})
    : container = ProviderContainer(
        overrides: [
          supabaseAuthServiceProvider.overrideWithValue(auth),
          portyHapticsServiceProvider.overrideWithValue(
            PortyHapticsService(
              enabled: true,
              performer: (pattern) async => haptics.add(pattern),
            ),
          ),
          appleSignInAvailableProvider.overrideWithValue(appleAvailable),
        ],
      );

  static final auth = _FakeAuthService();
  static final haptics = <PortyHapticPattern>[];
  final ProviderContainer container;

  Widget app({bool reduceMotion = false, Widget? child}) {
    final theme = ProviderContainer().read(themeDataLightProvider);
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: theme,
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(disableAnimations: reduceMotion),
              child: child!,
            ),
        home: child ?? const LoginScreen(),
      ),
    );
  }
}

void _useSmallIPhone(WidgetTester tester) {
  tester.view.physicalSize = _seSize;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: _seStatusBar);
  tester.view.viewPadding = const FakeViewPadding(top: _seStatusBar);
  addTearDown(tester.view.reset);
}

/// Lo que el typewriter muestra ahora (no el texto invisible que reserva
/// el alto del saludo).
String _typedGreeting(WidgetTester tester) {
  final typed = find.descendant(
    of: find.byType(TypewriterText),
    matching: find.byType(Text),
  );
  return tester.widget<Text>(typed).data!;
}

double _avatarSize(WidgetTester tester) =>
    tester.getSize(find.byType(PortyAvatar)).width;

PortyFrame _avatarFrame(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.descendant(
      of: find.byType(PortyAvatar),
      matching: find.byType(CustomPaint),
    ),
  );
  return (paint.painter! as PortyAvatarPainter).frame;
}

Finder get _form => find.byType(Form);
Finder get _button => find.byKey(LoginScreen.primaryButtonKey);

Future<void> _fillValidCredentials(WidgetTester tester) async {
  await tester.enterText(find.byType(TextFormField).at(0), 'ana@mail.com');
  await tester.enterText(find.byType(TextFormField).at(1), 'secreta123');
}

void main() {
  // Porty respira en el login sin parar: sin esto `pumpAndSettle` no
  // terminaría nunca. Su movimiento se prueba en porty_avatar_test.
  setUpAll(() => PortyAvatar.ambientMotion = false);
  tearDownAll(() => PortyAvatar.ambientMotion = true);
  setUp(_Harness.haptics.clear);

  testWidgets('shows Porty (the chat avatar, bigger) and its greeting, '
      'typed in under a second, with a single way to sign up', (tester) async {
    _useSmallIPhone(tester);
    final harness = _Harness();
    await tester.pumpWidget(harness.app());

    expect(find.byType(PortyAvatar), findsOneWidget);
    expect(_avatarSize(tester), AuthPortyHeader.avatarSize);
    expect(find.text('portfolio_qa_title'), findsOneWidget); // "Porty"
    expect(find.text('auth_porty_tagline'), findsOneWidget);

    expect(_typedGreeting(tester), isEmpty);
    // Frames de 16 ms, como en el device: el delay y el tipeo corren juntos.
    var elapsed = 0;
    Future<void> runFor(int ms) async {
      for (final end = elapsed + ms; elapsed < end; elapsed += 16) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    await runFor(480);
    final midway = _typedGreeting(tester);
    expect(midway, isNotEmpty);
    expect(midway.length, lessThan(_signInGreeting.length));

    await runFor(1000 - 480 - 16); // termina antes del segundo
    expect(_typedGreeting(tester), _signInGreeting);

    // Registrarse solo desde la pestaña: el link del pie ya no está.
    expect(find.text('auth_footer_register'), findsNothing);
    expect(find.text('auth_sign_up_tab'), findsOneWidget);
  });

  testWidgets('the greeting reserves its final height while it types, so '
      'the form below never moves', (tester) async {
    _useSmallIPhone(tester);
    await tester.pumpWidget(_Harness().app());
    final top = tester.getTopLeft(_form).dy;
    for (var ms = 0; ms < 1000; ms += 50) {
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.getTopLeft(_form).dy, top, reason: 'moved at ${ms}ms');
    }
  });

  testWidgets('switching tabs swaps the greeting and animates the form '
      'height', (tester) async {
    _useSmallIPhone(tester);
    await tester.pumpWidget(_Harness().app());
    await tester.pumpAndSettle();
    final signInHeight = tester.getSize(_form).height;

    await tester.tap(find.text('auth_sign_up_tab'));
    await tester.pump();
    await tester.pump(LoginScreen.motionDuration ~/ 2);
    final midHeight = tester.getSize(_form).height;
    await tester.pumpAndSettle();
    final signUpHeight = tester.getSize(_form).height;

    expect(signUpHeight, greaterThan(signInHeight));
    expect(midHeight, greaterThan(signInHeight));
    expect(midHeight, lessThan(signUpHeight));

    // Solo lo que está en escena (onstage) cuenta para find.text.
    expect(find.text(_signUpGreeting), findsWidgets);
    expect(find.text(_signInGreeting), findsNothing);
    expect(_Harness.haptics, [PortyHapticPattern.selection]);

    await tester.tap(find.text('auth_sign_in'));
    await tester.pumpAndSettle();
    expect(find.text(_signInGreeting), findsWidgets);
    expect(find.text(_signUpGreeting), findsNothing);
    expect(tester.getSize(_form).height, signInHeight);
  });

  testWidgets('with the keyboard open on an iPhone SE the inputs and the '
      'sign-in button stay visible without scrolling', (tester) async {
    _useSmallIPhone(tester);
    await tester.pumpWidget(_Harness().app());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextFormField).first);
    tester.view.viewInsets = const FakeViewPadding(bottom: _seKeyboard);
    await tester.pumpAndSettle();

    final visibleBottom = _seSize.height - _seKeyboard;
    expect(_avatarSize(tester), AuthPortyHeader.compactAvatarSize);
    for (final field in find.byType(TextFormField).evaluate()) {
      final rect = tester.getRect(find.byWidget(field.widget));
      expect(rect.top, greaterThanOrEqualTo(_seStatusBar));
      expect(rect.bottom, lessThanOrEqualTo(visibleBottom));
    }
    expect(tester.getRect(_button).bottom, lessThanOrEqualTo(visibleBottom));
    expect(
      tester.getRect(find.text('auth_forgot_password')).bottom,
      lessThanOrEqualTo(visibleBottom),
    );
    final scrollable = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(SingleChildScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(scrollable.position.pixels, 0);

    // Al cerrar el teclado Porty vuelve a su tamaño.
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();
    expect(_avatarSize(tester), AuthPortyHeader.avatarSize);
  });

  testWidgets('loading keeps the button size; a server error shows inline '
      'with an error haptic, never a snackbar', (tester) async {
    _useSmallIPhone(tester);
    await tester.pumpWidget(_Harness().app());
    await tester.pumpAndSettle();
    final idleSize = tester.getSize(_button);

    await _fillValidCredentials(tester);
    await tester.tap(_button);
    await tester.pump(); // post-frame del tap
    await tester.pump();

    // El spinner aparece recién si la espera pasa de 300 ms (una acción
    // rápida no titila).
    Finder spinner() => find.descendant(
      of: _button,
      matching: find.byType(CircularProgressIndicator),
    );
    expect(spinner(), findsNothing);
    await tester.pump(const Duration(milliseconds: 300));
    expect(spinner(), findsOneWidget);
    expect(tester.getSize(_button), idleSize);

    _Harness.auth.pendingSignIn!.completeError(
      const AuthException('Credenciales inválidas'),
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(_button), idleSize);
    final error = tester.widget<Text>(find.byKey(LoginScreen.formErrorKey));
    expect(error.data, isNotEmpty);
    expect(
      tester.getTopLeft(find.byKey(LoginScreen.formErrorKey)).dy,
      greaterThan(tester.getBottomLeft(_button).dy),
    );
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(Dialog), findsNothing);
    expect(_Harness.haptics, [PortyHapticPattern.doubleLight]);

    // Volver a escribir limpia el error.
    await tester.enterText(find.byType(TextFormField).at(1), 'otra123');
    await tester.pumpAndSettle();
    expect(find.byKey(LoginScreen.formErrorKey), findsNothing);
  });

  testWidgets('validation errors stay under their field and vibrate once', (
    tester,
  ) async {
    _useSmallIPhone(tester);
    await tester.pumpWidget(_Harness().app());
    await tester.pumpAndSettle();

    await tester.tap(_button);
    await tester.pumpAndSettle();

    expect(find.text('auth_email_required'), findsOneWidget);
    expect(find.text('auth_password_required'), findsOneWidget);
    expect(_Harness.haptics, [PortyHapticPattern.doubleLight]);
  });

  testWidgets('"next" moves from email to password and "done" submits', (
    tester,
  ) async {
    _useSmallIPhone(tester);
    await tester.pumpWidget(_Harness().app());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'ana@mail.com');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();
    final password = tester.widget<EditableText>(
      find.descendant(
        of: find.byType(TextFormField).at(1),
        matching: find.byType(EditableText),
      ),
    );
    expect(password.focusNode.hasFocus, isTrue);
    expect(password.autofillHints, [AutofillHints.password]);

    await tester.enterText(find.byType(TextFormField).at(1), 'secreta123');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(_Harness.auth.pendingSignIn, isNotNull);
    expect(_Harness.auth.pendingSignIn!.isCompleted, isFalse);
    _Harness.auth.pendingSignIn!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('sign-up asks the keychain for a new password', (tester) async {
    _useSmallIPhone(tester);
    await tester.pumpWidget(_Harness().app());
    await tester.tap(find.text('auth_sign_up_tab'));
    await tester.pumpAndSettle();

    final hints =
        tester
            .widgetList<EditableText>(find.byType(EditableText))
            .map((e) => e.autofillHints)
            .toList();
    expect(hints, [
      [AutofillHints.name],
      [AutofillHints.email],
      [AutofillHints.newPassword],
      [AutofillHints.newPassword],
    ]);
  });

  testWidgets('entering the app gives a light success haptic', (tester) async {
    _useSmallIPhone(tester);
    await tester.pumpWidget(_Harness().app());
    await tester.pumpAndSettle();

    _Harness.auth.sessions.add(
      const AuthState(AuthChangeEvent.signedOut, null),
    );
    await tester.pump();
    _Harness.auth.sessions.add(
      AuthState(
        AuthChangeEvent.signedIn,
        Session(
          accessToken: 'token',
          tokenType: 'bearer',
          user: const User(
            id: 'u1',
            appMetadata: {},
            userMetadata: {},
            aud: 'authenticated',
            createdAt: '2026-09-30T00:00:00Z',
          ),
        ),
      ),
    );
    await tester.pump();
    expect(_Harness.haptics, [PortyHapticPattern.light]);
  });

  testWidgets('with reduce motion everything is in its final state on the '
      'first frame', (tester) async {
    _useSmallIPhone(tester);
    await tester.pumpWidget(_Harness().app(reduceMotion: true));

    expect(_typedGreeting(tester), _signInGreeting);
    expect(_avatarSize(tester), AuthPortyHeader.avatarSize);
    expect(find.byType(AnimatedSize), findsNothing);
    // Sin entrada ni movimiento: Porty quieto, entero, desde el primer frame.
    expect(_avatarFrame(tester), const PortyFrame.still(PortyAvatarState.idle));

    await tester.tap(find.text('auth_sign_up_tab'));
    await tester.pump();
    expect(find.text(_signUpGreeting), findsWidgets);
    final heightAfterOneFrame = tester.getSize(_form).height;
    await tester.pumpAndSettle();
    expect(tester.getSize(_form).height, heightAfterOneFrame);

    await tester.tap(find.byType(TextFormField).first);
    tester.view.viewInsets = const FakeViewPadding(bottom: _seKeyboard);
    await tester.pump();
    expect(_avatarSize(tester), AuthPortyHeader.compactAvatarSize);
  });

  testWidgets('the greeting is typed once per session: coming back to the '
      'login shows it already written', (tester) async {
    _useSmallIPhone(tester);
    final harness = _Harness();
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();
    expect(_typedGreeting(tester), _signInGreeting);

    // Sale del login (ej. entra a la app) y vuelve (cierra sesión).
    await tester.pumpWidget(harness.app(child: const SizedBox()));
    await tester.pumpWidget(harness.app());

    expect(find.byType(TypewriterText), findsNothing);
    expect(find.text(_signInGreeting), findsOneWidget);
    // La entrada del avatar tampoco se repite: entero desde el primer frame.
    final frame = _avatarFrame(tester);
    expect(frame.opacity, 1);
    expect(frame.scale, 1);
  });

  testWidgets('no Apple button while Sign in with Apple is not set up', (
    tester,
  ) async {
    _useSmallIPhone(tester);
    await tester.pumpWidget(_Harness().app());
    expect(find.byType(AppleSignInButton), findsNothing);
  });

  testWidgets('when available, Apple sits above Google with the same height', (
    tester,
  ) async {
    _useSmallIPhone(tester);
    await tester.pumpWidget(_Harness(appleAvailable: true).app());
    await tester.pumpAndSettle();
    final apple = tester.getRect(find.byType(AppleSignInButton));
    final google = tester.getRect(find.byType(SocialSignInButton));
    expect(apple.bottom, lessThan(google.top));
    expect(apple.height, google.height);
    expect(apple.width, google.width);
  });
}
