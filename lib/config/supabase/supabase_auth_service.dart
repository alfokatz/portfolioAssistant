import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/sign_up_result.dart';
import 'package:portfolio_assistant/config/supabase/supabase_client_provider.dart';
import 'package:portfolio_assistant/config/supabase/supabase_redirect_url.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseAuthService {
  SupabaseAuthService(this._client);

  final SupabaseClient _client;

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
      email: email.trim(),
      password: password,
    );
  }

  Future<SignUpResult> signUpWithEmail({
    required String email,
    required String password,
    String? fullName,
  }) async {
    final response = await _client.auth.signUp(
      email: email.trim(),
      password: password,
      emailRedirectTo: SupabaseRedirectUrl.oauthCallback,
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

  Future<void> signInWithGoogle() async {
    await _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: SupabaseRedirectUrl.oauthCallback,
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
  }

  Future<void> signInWithApple() async {
    await _client.auth.signInWithOAuth(
      OAuthProvider.apple,
      redirectTo: SupabaseRedirectUrl.oauthCallback,
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
  }

  Future<void> resetPassword({required String email}) async {
    await _client.auth.resetPasswordForEmail(
      email.trim(),
      redirectTo: SupabaseRedirectUrl.passwordRecoveryCallback,
    );
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }
}

final supabaseAuthServiceProvider = Provider<SupabaseAuthService>(
  (ref) => SupabaseAuthService(ref.watch(supabaseClientProvider)),
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
