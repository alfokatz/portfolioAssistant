// Screenshots del login y del registro (formulario, requisitos de la
// contraseña, "Revisá tu email", bloqueo por intentos, error de Google) y de
// la pantalla de contraseña nueva, con fuentes y textos reales. No corre en
// la suite normal (escribe PNGs):
//
//   RUN_SCREENSHOTS=1 SCREENSHOTS_OUT=/tmp/shots \
//     flutter test test/screenshots/auth_screenshots_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
// Viene con el SDK (y con easy_localization); solo para estos screenshots.
// ignore: depend_on_referenced_packages
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/sign_up_result.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:portfolio_assistant/presentation/flows/auth/providers/auth_provider.dart';
import 'package:portfolio_assistant/presentation/flows/auth/ui/login_screen.dart';
import 'package:portfolio_assistant/presentation/flows/auth/ui/reset_password_screen.dart';
import 'package:portfolio_assistant/presentation/flows/auth/ui/widgets/auth_porty_header.dart';
import 'package:portfolio_assistant/presentation/flows/auth/ui/widgets/social_sign_in_button.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/app_background_gradient.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _out = Platform.environment['SCREENSHOTS_OUT'] ?? 'build/screenshots';
final _enabled = Platform.environment['RUN_SCREENSHOTS'] == '1';

const _size = Size(402, 874);
const _dpr = 3.0;

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(
        File(f).readAsBytes().then((b) => ByteData.view(b.buffer)),
      );
    }
    await loader.load();
  }

  final sdk =
      Platform.environment['FLUTTER_ROOT'] ??
      '${Platform.environment['HOME']}/Development/flutter';
  await load('MaterialIcons', [
    '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ]);
  const weights = {'Regular': 400, 'Medium': 500, 'SemiBold': 600, 'Bold': 700};
  for (final MapEntry(key: name, value: w) in weights.entries) {
    final file = 'assets/fonts/PlusJakartaSans-$name.ttf';
    await load('PlusJakartaSans_${w == 400 ? 'regular' : w}', [file]);
    await load('Plus Jakarta Sans', [file]);
  }
}

class _FakeAuth implements SupabaseAuthService {
  Object? signInError;
  Object? googleError;

  @override
  Stream<AuthState> get onAuthStateChange => const Stream.empty();

  @override
  Session? get currentSession => null;

  @override
  User? get currentUser => const User(
    id: 'u1',
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    email: 'ana.perez@gmail.com',
    createdAt: '2026-10-01T00:00:00Z',
  );

  @override
  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    if (signInError case final error?) throw error;
  }

  @override
  Future<SignUpResult> signUpWithEmail({
    required String email,
    required String password,
    String? fullName,
  }) async => SignUpResult.confirmationEmailSent;

  @override
  Future<bool> signInWithGoogle() async {
    if (googleError case final error?) throw error;
    return false;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(Brightness brightness, Widget home, _FakeAuth auth) {
  final container = ProviderContainer();
  final theme = container.read(
    brightness == Brightness.light
        ? themeDataLightProvider
        : themeDataDarkProvider,
  );
  container.dispose();
  return ProviderScope(
    overrides: [
      supabaseAuthServiceProvider.overrideWithValue(auth),
      appleSignInAvailableProvider.overrideWithValue(false),
      portyHapticsServiceProvider.overrideWithValue(
        PortyHapticsService(enabled: false, performer: (_) async {}),
      ),
      // El saludo ya escrito: sin typewriter a medias en la foto.
      authGreetingPlayedProvider.overrideWith((ref) => true),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('es', 'ES')],
      locale: const Locale('es', 'ES'),
      builder:
          (context, child) => Stack(
            children: [
              const Positioned.fill(child: AppBackgroundGradient()),
              child!,
            ],
          ),
      home: home,
    ),
  );
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundary,
  String name,
) async {
  final render =
      boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image =
      (await tester.runAsync(() => render.toImage(pixelRatio: _dpr)))!;
  final bytes =
      (await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.png),
      ))!;
  File('$_out/$name.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes.buffer.asUint8List());
}

void main() {
  setUpAll(() async {
    if (!_enabled) return;
    PortyAvatar.ambientMotion = false;
    GoogleFonts.config.allowRuntimeFetching = false;
    final es =
        jsonDecode(File('assets/translations/es-ES.json').readAsStringSync())
            as Map<String, dynamic>;
    Localization.load(const Locale('es', 'ES'), translations: Translations(es));
    await _loadFonts();
  });

  Future<void> setUp(WidgetTester tester, Brightness brightness) async {
    tester.view.physicalSize = _size * _dpr;
    tester.view.devicePixelRatio = _dpr;
    tester.view.padding = const FakeViewPadding(top: 47 * _dpr);
    tester.view.viewPadding = const FakeViewPadding(top: 47 * _dpr);
    tester.platformDispatcher.platformBrightnessTestValue = brightness;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  }

  /// Fuentes y SVG se cargan fuera del reloj falso. Sin pumpAndSettle: las
  /// cuentas regresivas tickean.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  Finder fields() => find.byType(TextFormField);

  Future<void> submit(WidgetTester tester) async {
    await tester.tap(find.byKey(LoginScreen.primaryButtonKey));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  for (final brightness in Brightness.values) {
    final b = brightness.name;

    Future<GlobalKey> open(
      WidgetTester tester,
      Widget home, [
      _FakeAuth? auth,
    ]) async {
      await setUp(tester, brightness);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: _app(brightness, home, auth ?? _FakeAuth()),
        ),
      );
      await settle(tester);
      return boundary;
    }

    testWidgets('auth_sign_up_requirements_$b', (tester) async {
      final boundary = await open(tester, const LoginScreen());
      await tester.tap(find.text('Registrarse'));
      await settle(tester);
      await tester.enterText(fields().at(0), 'Ana Pérez');
      await tester.enterText(fields().at(1), 'ana.perez@gmail.com');
      await tester.enterText(fields().at(2), 'secreta12');
      await settle(tester);
      await _capture(tester, boundary, 'auth_sign_up_requirements_$b');
    }, skip: !_enabled);

    testWidgets('auth_check_email_$b', (tester) async {
      final boundary = await open(tester, const LoginScreen());
      await tester.tap(find.text('Registrarse'));
      await settle(tester);
      await tester.enterText(fields().at(0), 'Ana Pérez');
      await tester.enterText(fields().at(1), 'ana.perez@gmail.com');
      await tester.enterText(fields().at(2), 'Secreta123');
      await tester.enterText(fields().at(3), 'Secreta123');
      await submit(tester);
      await settle(tester);
      await _capture(tester, boundary, 'auth_check_email_$b');
    }, skip: !_enabled);

    testWidgets('auth_locked_$b', (tester) async {
      final auth = _FakeAuth()
        ..signInError = const AuthException(
          'Invalid login credentials',
          code: 'invalid_credentials',
        );
      final boundary = await open(tester, const LoginScreen(), auth);
      await tester.enterText(fields().at(0), 'ana.perez@gmail.com');
      for (var i = 0; i < 5; i++) {
        await tester.enterText(fields().at(1), 'incorrecta$i');
        await submit(tester);
      }
      await settle(tester);
      await _capture(tester, boundary, 'auth_locked_$b');
    }, skip: !_enabled);

    testWidgets('auth_google_error_$b', (tester) async {
      final auth = _FakeAuth()
        ..googleError = const SocketException('offline');
      final boundary = await open(tester, const LoginScreen(), auth);
      await tester.tap(find.byType(SocialSignInButton));
      await settle(tester);
      await _capture(tester, boundary, 'auth_google_error_$b');
    }, skip: !_enabled);

    testWidgets('auth_reset_password_$b', (tester) async {
      final boundary = await open(tester, const ResetPasswordScreen());
      await tester.enterText(fields().at(0), 'Nueva2026');
      await settle(tester);
      await _capture(tester, boundary, 'auth_reset_password_$b');
    }, skip: !_enabled);
  }
}
