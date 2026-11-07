import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Qué le pasó al pedido de auth, en términos de la UI.
enum AuthFailure {
  invalidCredentials('auth_error_invalid_credentials'),
  emailNotConfirmed('auth_error_email_not_confirmed'),
  rateLimited('auth_error_rate_limited'),
  weakPassword('auth_error_weak_password'),
  samePassword('auth_error_same_password'),
  signUpFailed('auth_error_sign_up_failed'),
  signUpDisabled('auth_error_sign_up_disabled'),
  providerDisabled('auth_error_provider_disabled'),
  linkExpired('auth_error_link_expired'),
  sessionExpired('auth_error_session_expired'),
  userBanned('auth_error_user_banned'),
  oauthFailed('auth_error_oauth_failed'),
  network('auth_error_network'),
  unknown('auth_error_generic');

  const AuthFailure(this.messageKey);

  /// Key de traducción del mensaje que ve el usuario.
  final String messageKey;

  /// Traduce cualquier error de Supabase / red a un caso conocido.
  ///
  /// Nunca se muestra el mensaje crudo del servidor: viene en inglés, puede
  /// filtrar detalles internos y, en algunos casos (ej. "User already
  /// registered"), permite averiguar qué emails tienen cuenta.
  static AuthFailure from(Object error) {
    if (error is AuthRetryableFetchException ||
        error is SocketException ||
        error is TimeoutException ||
        error is http.ClientException ||
        error is HandshakeException) {
      return network;
    }
    if (error is AuthWeakPasswordException) return weakPassword;
    if (error is AuthSessionMissingException) return sessionExpired;
    if (error is AuthPKCEGrantCodeExchangeError) return linkExpired;
    if (error is! AuthException) return unknown;

    final code = error.code;
    final message = error.message.toLowerCase();
    switch (code) {
      case 'invalid_credentials':
        return invalidCredentials;
      case 'email_not_confirmed':
        return emailNotConfirmed;
      case 'over_request_rate_limit':
      case 'over_email_send_rate_limit':
        return rateLimited;
      case 'weak_password':
        return weakPassword;
      case 'same_password':
        return samePassword;
      case 'user_already_exists':
      case 'email_exists':
      case 'email_address_invalid':
      case 'email_address_not_authorized':
        return signUpFailed;
      case 'signup_disabled':
      case 'email_provider_disabled':
        return signUpDisabled;
      case 'provider_disabled':
      case 'oauth_provider_not_supported':
        return providerDisabled;
      case 'flow_state_not_found':
      case 'flow_state_expired':
      case 'bad_code_verifier':
      case 'otp_expired':
        return linkExpired;
      case 'session_not_found':
      case 'refresh_token_not_found':
      case 'refresh_token_already_used':
        return sessionExpired;
      case 'user_banned':
        return userBanned;
      case 'bad_oauth_state':
      case 'bad_oauth_callback':
      case 'provider_email_needs_verification':
        return oauthFailed;
    }

    // Servidores viejos de GoTrue no mandan `code`: se reconoce por el
    // status o el texto.
    if (error.statusCode == '429') return rateLimited;
    if (message.contains('invalid login credentials')) {
      return invalidCredentials;
    }
    if (message.contains('email not confirmed')) return emailNotConfirmed;
    if (message.contains('code verifier') || message.contains('expired')) {
      return linkExpired;
    }
    return unknown;
  }
}
