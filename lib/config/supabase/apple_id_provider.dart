import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Lo que devuelve la hoja nativa de "Iniciar sesión con Apple".
class AppleIdCredential {
  const AppleIdCredential({
    required this.authorizationCode,
    this.identityToken,
    this.givenName,
    this.familyName,
  });

  /// Código de un uso (vence a los 5 minutos). Lo canjea el servidor, por
  /// ejemplo para revocar el acceso al borrar la cuenta.
  final String authorizationCode;

  /// JWT de Apple con el `nonce` hasheado: es lo que valida Supabase.
  final String? identityToken;

  /// Apple manda el nombre solo la primera vez que el usuario autoriza la app.
  final String? givenName;
  final String? familyName;
}

/// Pide la credencial a Apple. Devuelve `null` si el usuario cerró la hoja.
abstract class AppleIdProvider {
  Future<AppleIdCredential?> requestCredential({
    required String hashedNonce,
    required bool withNameAndEmail,
  });
}

/// La hoja del sistema (AuthenticationServices en iOS).
class SystemAppleIdProvider implements AppleIdProvider {
  const SystemAppleIdProvider();

  @override
  Future<AppleIdCredential?> requestCredential({
    required String hashedNonce,
    required bool withNameAndEmail,
  }) async {
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: withNameAndEmail
            ? const [
                AppleIDAuthorizationScopes.email,
                AppleIDAuthorizationScopes.fullName,
              ]
            : const [],
        nonce: hashedNonce,
      );
      return AppleIdCredential(
        authorizationCode: credential.authorizationCode,
        identityToken: credential.identityToken,
        givenName: credential.givenName,
        familyName: credential.familyName,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) return null;
      rethrow;
    }
  }
}

final appleIdProviderProvider = Provider<AppleIdProvider>(
  (ref) => const SystemAppleIdProvider(),
);
