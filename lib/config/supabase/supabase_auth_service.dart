import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/sign_up_result.dart';
import 'package:portfolio_assistant/config/supabase/supabase_client_provider.dart';
import 'package:portfolio_assistant/config/supabase/supabase_redirect_url.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Abre la pantalla de login del proveedor (Google, Apple) en el navegador
/// del sistema y devuelve la URL de vuelta, o `null` si el usuario la cerró.
///
/// Navegador del sistema y no un WebView: Google bloquea el login en
/// WebViews (`disallowed_useragent`) y la app no ve nunca la contraseña.
abstract class OAuthBrowser {
  Future<Uri?> authenticate({
    required Uri url,
    required String callbackScheme,
  });
}

/// ASWebAuthenticationSession en iOS/macOS, Auth Tab (o Custom Tabs) en
/// Android.
class SystemOAuthBrowser implements OAuthBrowser {
  const SystemOAuthBrowser();

  @override
  Future<Uri?> authenticate({
    required Uri url,
    required String callbackScheme,
  }) async {
    try {
      final result = await FlutterWebAuth2.authenticate(
        url: url.toString(),
        callbackUrlScheme: callbackScheme,
        // No efímero: si el usuario ya tiene su cuenta de Google en el
        // navegador, la elige sin volver a escribir la contraseña.
        options: const FlutterWebAuth2Options(preferEphemeral: false),
      );
      return Uri.parse(result);
    } on PlatformException catch (e) {
      if (e.code == 'CANCELED') return null;
      rethrow;
    }
  }
}

final oauthBrowserProvider = Provider<OAuthBrowser>(
  (ref) => const SystemOAuthBrowser(),
);

class SupabaseAuthService {
  SupabaseAuthService(this._client, {OAuthBrowser? oauthBrowser})
    : _oauthBrowser = oauthBrowser ?? const SystemOAuthBrowser();

  final SupabaseClient _client;
  final OAuthBrowser _oauthBrowser;

  GoTrueClient get auth => _client.auth;

  Session? get currentSession => _client.auth.currentSession;

  User? get currentUser => _client.auth.currentUser;

  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  String requireUserId() {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('No hay sesión activa. Iniciá sesión para continuar.');
    }
    return user.id;
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    await _client.auth.signInWithPassword(
      email: _normalizeEmail(email),
      password: password,
    );
  }

  /// Con la confirmación de email activa, Supabase responde igual (sin
  /// sesión) exista o no la cuenta, para no revelar qué emails están
  /// registrados; solo cambia que, si ya existía, `identities` viene vacío.
  /// La pantalla trata los dos casos igual.
  Future<SignUpResult> signUpWithEmail({
    required String email,
    required String password,
    String? fullName,
  }) async {
    final response = await _client.auth.signUp(
      email: _normalizeEmail(email),
      password: password,
      emailRedirectTo: SupabaseRedirectUrl.emailConfirmationCallback,
      data: {
        if (fullName != null && fullName.trim().isNotEmpty)
          'full_name': fullName.trim(),
      },
    );

    if (response.session != null) {
      return SignUpResult.signedIn;
    }

    final identities = response.user?.identities;
    if (identities == null || identities.isEmpty) {
      return SignUpResult.emailAlreadyRegistered;
    }

    return SignUpResult.confirmationEmailSent;
  }

  /// Reenvía el email de confirmación del registro.
  Future<void> resendSignUpConfirmation({required String email}) async {
    await _client.auth.resend(
      type: OtpType.signup,
      email: _normalizeEmail(email),
      emailRedirectTo: SupabaseRedirectUrl.emailConfirmationCallback,
    );
  }

  /// Login con Google. Devuelve `false` si el usuario cerró el navegador
  /// sin terminar (no es un error: no se muestra nada).
  Future<bool> signInWithGoogle() => _signInWithOAuth(
    OAuthProvider.google,
    // Deja elegir otra cuenta de Google después de cerrar sesión, en vez de
    // entrar directo con la última.
    queryParams: const {'prompt': 'select_account'},
  );

  Future<bool> signInWithApple() => _signInWithOAuth(OAuthProvider.apple);

  /// OAuth con PKCE:
  /// 1. GoTrue arma la URL de `/authorize` y guarda el code verifier en el
  ///    almacenamiento seguro.
  /// 2. El navegador del sistema hace el login con el proveedor; Supabase
  ///    vuelve a [SupabaseRedirectUrl.oauthCallback] con un `code` de un uso.
  /// 3. Se canjea el `code` + verifier por la sesión. Sin el verifier (que
  ///    nunca sale del dispositivo) un `code` interceptado no sirve.
  Future<bool> _signInWithOAuth(
    OAuthProvider provider, {
    Map<String, String>? queryParams,
  }) async {
    if (kIsWeb) {
      // En web la página entera redirige y supabase_flutter toma la sesión
      // de la URL al volver.
      return _client.auth.signInWithOAuth(provider, queryParams: queryParams);
    }

    final oauth = await _client.auth.getOAuthSignInUrl(
      provider: provider,
      redirectTo: SupabaseRedirectUrl.oauthCallback,
      queryParams: queryParams,
    );
    final callback = await _oauthBrowser.authenticate(
      url: Uri.parse(oauth.url),
      callbackScheme: SupabaseRedirectUrl.oauthScheme,
    );
    if (callback == null) return false;

    final params = oauthCallbackParams(callback);
    final errorDescription = params['error_description'];
    final error = params['error'];
    if (errorDescription != null || error != null) {
      // El usuario rechazó el consentimiento en Google: es una cancelación.
      if (error == 'access_denied') return false;
      throw AuthException(
        errorDescription ?? error!,
        code: params['error_code'] ?? error,
      );
    }

    final code = params['code'];
    if (code == null || code.isEmpty) {
      throw const AuthException(
        'Missing OAuth code',
        code: 'bad_oauth_callback',
      );
    }
    await _client.auth.exchangeCodeForSession(code);
    return true;
  }

  /// Los parámetros pueden volver en la query (PKCE) o en el fragmento
  /// (errores de algunos proveedores).
  static Map<String, String> oauthCallbackParams(Uri uri) {
    final fragment =
        uri.fragment.isEmpty ? <String, String>{} : Uri.splitQueryString(uri.fragment);
    return {...fragment, ...uri.queryParameters};
  }

  /// Cambia el nombre que se muestra (el mismo `full_name` de la metadata
  /// que se guarda al registrarse). Devuelve el usuario actualizado.
  Future<User?> updateFullName(String fullName) async {
    final response = await _client.auth.updateUser(
      UserAttributes(data: {'full_name': fullName.trim()}),
    );
    return response.user;
  }

  /// Supabase responde igual exista o no la cuenta: no revela qué emails
  /// están registrados.
  Future<void> resetPassword({required String email}) async {
    await _client.auth.resetPasswordForEmail(
      _normalizeEmail(email),
      redirectTo: SupabaseRedirectUrl.passwordRecoveryCallback,
    );
  }

  /// Contraseña nueva desde el link de recuperación (la sesión de recovery
  /// la habilita). Cierra las demás sesiones: si alguien más tenía acceso a
  /// la cuenta, lo pierde.
  Future<void> updatePassword(String newPassword) async {
    await _client.auth.updateUser(UserAttributes(password: newPassword));
    try {
      await _client.auth.signOut(scope: SignOutScope.others);
    } catch (_) {
      // La contraseña ya cambió; que falle cerrar las otras sesiones no
      // tiene que bloquear al usuario (vencen solas con el refresh token).
    }
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  static String _normalizeEmail(String email) => email.trim().toLowerCase();
}

final supabaseAuthServiceProvider = Provider<SupabaseAuthService>(
  (ref) => SupabaseAuthService(
    ref.watch(supabaseClientProvider),
    oauthBrowser: ref.watch(oauthBrowserProvider),
  ),
);

final authSessionProvider = StreamProvider<Session?>(
  (ref) => ref
      .watch(supabaseAuthServiceProvider)
      .onAuthStateChange
      .map((event) => event.session),
);

final isAuthenticatedProvider = Provider<bool>((ref) {
  ref.watch(authSessionProvider);
  return ref.read(supabaseAuthServiceProvider).currentSession != null;
});

/// `true` mientras el usuario entró con el link de "restablecer contraseña"
/// y todavía no eligió una nueva. El router lo manda a esa pantalla y no lo
/// deja ir a otro lado hasta que la cambie o cierre sesión.
///
/// `onAuthStateChange` repite el último evento al suscribirse, así que el
/// `passwordRecovery` no se pierde aunque llegue (por deep link en frío)
/// antes de que se cree este provider.
final passwordRecoveryProvider =
    StateNotifierProvider<PasswordRecoveryController, bool>(
      (ref) => PasswordRecoveryController(
        ref.watch(supabaseAuthServiceProvider).onAuthStateChange,
      ),
    );

class PasswordRecoveryController extends StateNotifier<bool> {
  PasswordRecoveryController(Stream<AuthState> authEvents) : super(false) {
    _subscription = authEvents.listen(
      (event) {
        switch (event.event) {
          case AuthChangeEvent.passwordRecovery:
            state = true;
          case AuthChangeEvent.signedOut:
            state = false;
          default:
            break;
        }
      },
      // Los errores de deep links (link vencido) los muestra el login.
      onError: (Object _) {},
    );
  }

  late final StreamSubscription<AuthState> _subscription;

  /// La contraseña nueva ya quedó guardada.
  void complete() => state = false;

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
