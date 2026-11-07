import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/config/supabase/supabase_redirect_url.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MemoryPkceStorage extends GotrueAsyncStorage {
  final values = <String, String>{};

  @override
  Future<String?> getItem({required String key}) async => values[key];

  @override
  Future<void> setItem({required String key, required String value}) async =>
      values[key] = value;

  @override
  Future<void> removeItem({required String key}) async => values.remove(key);
}

/// Hace de navegador del sistema: guarda la URL que se abrió y devuelve la
/// vuelta que el test elija.
class _FakeBrowser implements OAuthBrowser {
  _FakeBrowser(this.respond);

  final Uri? Function(Uri url) respond;
  Uri? openedUrl;
  String? callbackScheme;

  @override
  Future<Uri?> authenticate({
    required Uri url,
    required String callbackScheme,
  }) async {
    openedUrl = url;
    this.callbackScheme = callbackScheme;
    return respond(url);
  }
}

Map<String, dynamic> _sessionJson() => {
  'access_token': 'access-token',
  'token_type': 'bearer',
  'expires_in': 3600,
  'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
  'refresh_token': 'refresh-token',
  'user': {
    'id': 'user-1',
    'aud': 'authenticated',
    'email': 'ana@mail.com',
    'created_at': '2026-10-01T00:00:00Z',
    'app_metadata': {'provider': 'google'},
    'user_metadata': {},
  },
};

void main() {
  late List<http.Request> requests;
  late _MemoryPkceStorage pkce;
  late SupabaseClient client;

  SupabaseAuthService service(_FakeBrowser browser) =>
      SupabaseAuthService(client, oauthBrowser: browser);

  setUp(() {
    requests = [];
    pkce = _MemoryPkceStorage();
    client = SupabaseClient(
      'https://project.supabase.co',
      'anon-key',
      authOptions: AuthClientOptions(
        autoRefreshToken: false,
        pkceAsyncStorage: pkce,
      ),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/auth/v1/token') {
          return http.Response(
            jsonEncode(_sessionJson()),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 404);
      }),
    );
  });

  tearDown(() => client.dispose());

  group('Google sign-in (OAuth + PKCE in the system browser)', () {
    test('opens Supabase /authorize for Google with the app callback, a '
        'S256 challenge and the account picker', () async {
      final browser = _FakeBrowser((_) => null);
      await service(browser).signInWithGoogle();

      final url = browser.openedUrl!;
      expect(url.host, 'project.supabase.co');
      expect(url.path, '/auth/v1/authorize');
      expect(url.queryParameters['provider'], 'google');
      expect(
        url.queryParameters['redirect_to'],
        SupabaseRedirectUrl.oauthCallback,
      );
      expect(url.queryParameters['code_challenge'], isNotEmpty);
      expect(url.queryParameters['code_challenge_method'], 's256');
      expect(url.queryParameters['prompt'], 'select_account');
      expect(browser.callbackScheme, SupabaseRedirectUrl.oauthScheme);
    });

    test('exchanges the returned code together with the stored verifier and '
        'signs in', () async {
      final browser = _FakeBrowser(
        (_) => Uri.parse('porty-oauth://callback?code=auth-code-123'),
      );
      final events = <AuthChangeEvent>[];
      final sub = client.auth.onAuthStateChange.listen(
        (e) => events.add(e.event),
      );

      final verifierBefore = await pkce.getItem(
        key: 'supabase.auth.token-code-verifier',
      );
      expect(verifierBefore, isNull);

      final signedIn = await service(browser).signInWithGoogle();

      expect(signedIn, isTrue);
      final token = requests.singleWhere(
        (r) => r.url.path == '/auth/v1/token',
      );
      expect(token.url.queryParameters['grant_type'], 'pkce');
      final body = jsonDecode(token.body) as Map<String, dynamic>;
      expect(body['auth_code'], 'auth-code-123');
      expect(body['code_verifier'], isNotEmpty);
      // El verifier es de un solo uso.
      expect(pkce.values, isEmpty);
      expect(client.auth.currentSession?.accessToken, 'access-token');
      await Future<void>.delayed(Duration.zero);
      expect(events, contains(AuthChangeEvent.signedIn));
      await sub.cancel();
    });

    test('closing the browser is not an error and does not sign in', () async {
      final signedIn = await service(_FakeBrowser((_) => null))
          .signInWithGoogle();
      expect(signedIn, isFalse);
      expect(requests, isEmpty);
      expect(client.auth.currentSession, isNull);
    });

    test('declining the Google consent screen counts as a cancel', () async {
      final signedIn = await service(
        _FakeBrowser(
          (_) => Uri.parse(
            'porty-oauth://callback?error=access_denied'
            '&error_description=The+user+denied',
          ),
        ),
      ).signInWithGoogle();
      expect(signedIn, isFalse);
      expect(requests, isEmpty);
    });

    test('a provider error in the callback (query or fragment) throws an '
        'AuthException with its code', () async {
      for (final callback in [
        'porty-oauth://callback?error=server_error'
            '&error_code=provider_disabled&error_description=Disabled',
        'porty-oauth://callback#error=server_error'
            '&error_code=provider_disabled&error_description=Disabled',
      ]) {
        await expectLater(
          service(_FakeBrowser((_) => Uri.parse(callback)))
              .signInWithGoogle(),
          throwsA(
            isA<AuthException>().having(
              (e) => e.code,
              'code',
              'provider_disabled',
            ),
          ),
        );
      }
      expect(client.auth.currentSession, isNull);
    });

    test('a callback without code is rejected', () async {
      await expectLater(
        service(
          _FakeBrowser((_) => Uri.parse('porty-oauth://callback')),
        ).signInWithGoogle(),
        throwsA(
          isA<AuthException>().having(
            (e) => e.code,
            'code',
            'bad_oauth_callback',
          ),
        ),
      );
    });
  });

  test('email sign-up and password reset send the email deep links and a '
      'normalized email', () async {
    final browser = _FakeBrowser((_) => null);
    final auth = service(browser);
    try {
      await auth.signUpWithEmail(
        email: '  Ana@Mail.COM ',
        password: 'Secreta123',
      );
    } catch (_) {
      // El mock responde 404: solo importa el request.
    }
    try {
      await auth.resetPassword(email: ' Ana@Mail.com');
    } catch (_) {}

    final signUp = requests.firstWhere((r) => r.url.path == '/auth/v1/signup');
    expect(
      signUp.url.queryParameters['redirect_to'],
      SupabaseRedirectUrl.emailConfirmationCallback,
    );
    expect(jsonDecode(signUp.body)['email'], 'ana@mail.com');

    final recover = requests.firstWhere(
      (r) => r.url.path == '/auth/v1/recover',
    );
    expect(
      recover.url.queryParameters['redirect_to'],
      SupabaseRedirectUrl.passwordRecoveryCallback,
    );
    expect(jsonDecode(recover.body)['email'], 'ana@mail.com');
  });
}
