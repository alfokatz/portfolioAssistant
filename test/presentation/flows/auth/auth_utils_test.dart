import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/presentation/flows/auth/utils/auth_error_messages.dart';
import 'package:portfolio_assistant/presentation/flows/auth/utils/auth_validators.dart';
import 'package:portfolio_assistant/presentation/flows/auth/utils/login_attempt_limiter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('AuthValidators.email', () {
    test('accepts real-world addresses, ignoring case and outer spaces', () {
      for (final email in [
        'ana@mail.com',
        '  Ana.Perez+porty@Mail.co.uk ',
        "o'neil@sub-domain.example.org",
        'x@y.io',
      ]) {
        expect(AuthValidators.email(email), isNull, reason: email);
      }
      expect(AuthValidators.normalizeEmail(' Ana@Mail.COM '), 'ana@mail.com');
    });

    test('rejects what the old `contains("@")` check let through', () {
      for (final email in [
        'ana@',
        '@mail.com',
        'ana@mail',
        'ana@@mail.com',
        'ana mail@x.com',
        'ana..perez@mail.com',
        '.ana@mail.com',
        'ana.@mail.com',
        'ana@-mail.com',
        'ana@mail-.com',
        'ana@mail..com',
        '${'a' * 250}@x.com',
      ]) {
        expect(AuthValidators.email(email), 'auth_email_invalid',
            reason: email);
      }
      expect(AuthValidators.email('   '), 'auth_email_required');
      expect(AuthValidators.email(null), 'auth_email_required');
    });
  });

  group('AuthValidators passwords', () {
    test('sign in only requires a value (old 6-char passwords still work)',
        () {
      expect(AuthValidators.signInPassword(''), 'auth_password_required');
      expect(AuthValidators.signInPassword('abc123'), isNull);
    });

    test('a new password follows the Supabase policy, one error at a time',
        () {
      expect(AuthValidators.newPassword(''), 'auth_password_required');
      expect(AuthValidators.newPassword('Ab1'), 'auth_password_min_length');
      expect(
        AuthValidators.newPassword('secreta123'),
        'auth_password_needs_case',
      );
      expect(
        AuthValidators.newPassword('Secretaaa'),
        'auth_password_needs_digit',
      );
      expect(
        AuthValidators.newPassword(' Secreta123'),
        'auth_password_no_edge_spaces',
      );
      expect(AuthValidators.newPassword('Secreta123'), isNull);
    });

    test('rejects passwords longer than the 72 bytes bcrypt hashes', () {
      expect(AuthValidators.newPassword('Aa1${'x' * 69}'), isNull); // 72
      expect(
        AuthValidators.newPassword('Aa1${'x' * 70}'),
        'auth_password_too_long',
      );
      // Multibyte: 35 × "ñ" (2 bytes c/u) + "Aa1" = 73 bytes.
      expect(
        AuthValidators.newPassword('Aa1${'ñ' * 35}'),
        'auth_password_too_long',
      );
    });

    test('confirmation must match', () {
      expect(
        AuthValidators.confirmPassword('', 'Secreta123'),
        'auth_confirm_password_required',
      );
      expect(
        AuthValidators.confirmPassword('Secreta124', 'Secreta123'),
        'auth_password_mismatch',
      );
      expect(AuthValidators.confirmPassword('Secreta123', 'Secreta123'),
          isNull);
    });

    test('the checklist reports each requirement', () {
      expect(
        PasswordRequirement.values.where((r) => r.isMetBy('secreta')),
        isEmpty,
      );
      expect(
        PasswordRequirement.values.where((r) => r.isMetBy('Secreta1')),
        PasswordRequirement.values,
      );
    });
  });

  test('full name: required, bounded, no control characters', () {
    expect(AuthValidators.fullName('  '), 'auth_full_name_required');
    expect(AuthValidators.fullName('Ana Pérez'), isNull);
    expect(AuthValidators.fullName('a' * 81), 'auth_full_name_too_long');
    expect(AuthValidators.fullName('Ana\nPérez'), 'auth_full_name_invalid');
  });

  group('AuthFailure.from', () {
    test('maps Supabase error codes to localized messages', () {
      AuthFailure of(String code, [String message = 'x']) =>
          AuthFailure.from(AuthException(message, code: code));

      expect(of('invalid_credentials'), AuthFailure.invalidCredentials);
      expect(of('email_not_confirmed'), AuthFailure.emailNotConfirmed);
      expect(of('over_request_rate_limit'), AuthFailure.rateLimited);
      expect(of('over_email_send_rate_limit'), AuthFailure.rateLimited);
      expect(of('user_already_exists'), AuthFailure.signUpFailed);
      expect(of('same_password'), AuthFailure.samePassword);
      expect(of('provider_disabled'), AuthFailure.providerDisabled);
      expect(of('flow_state_expired'), AuthFailure.linkExpired);
      expect(of('bad_oauth_callback'), AuthFailure.oauthFailed);
      expect(of('user_banned'), AuthFailure.userBanned);
    });

    test('falls back to status and message for servers without codes', () {
      expect(
        AuthFailure.from(const AuthException('Invalid login credentials')),
        AuthFailure.invalidCredentials,
      );
      expect(
        AuthFailure.from(const AuthException('Slow down', statusCode: '429')),
        AuthFailure.rateLimited,
      );
      expect(
        AuthFailure.from(
          const AuthException('Code verifier could not be found'),
        ),
        AuthFailure.linkExpired,
      );
    });

    test('network problems read as such; anything else is generic', () {
      expect(
        AuthFailure.from(const SocketException('offline')),
        AuthFailure.network,
      );
      expect(AuthFailure.from(TimeoutException('slow')), AuthFailure.network);
      expect(
        AuthFailure.from(AuthRetryableFetchException()),
        AuthFailure.network,
      );
      expect(
        AuthFailure.from(AuthWeakPasswordException(
          message: 'weak',
          statusCode: '422',
          reasons: const [],
        )),
        AuthFailure.weakPassword,
      );
      expect(AuthFailure.from(StateError('boom')), AuthFailure.unknown);
      expect(
        AuthFailure.from(const AuthException('Database error saving user')),
        AuthFailure.unknown,
      );
    });

    test('every failure has a message key', () {
      for (final failure in AuthFailure.values) {
        expect(failure.messageKey, startsWith('auth_error_'));
      }
    });
  });

  group('LoginAttemptLimiter', () {
    test('locks after 5 failures and doubles the wait, capped', () {
      var now = DateTime(2026, 10, 10, 12);
      final limiter = LoginAttemptLimiter(now: () => now);

      for (var i = 0; i < 4; i++) {
        expect(limiter.registerFailure(), isNull);
        expect(limiter.isLocked, isFalse);
      }
      expect(
        limiter.registerFailure(),
        now.add(const Duration(seconds: 30)),
      );
      expect(limiter.isLocked, isTrue);

      now = now.add(const Duration(seconds: 31));
      expect(limiter.isLocked, isFalse);
      expect(limiter.registerFailure(), now.add(const Duration(minutes: 1)));

      for (var i = 0; i < 10; i++) {
        limiter.registerFailure();
      }
      expect(limiter.lockedUntil, now.add(const Duration(minutes: 15)));
    });

    test('a successful sign-in forgets the failures', () {
      final limiter = LoginAttemptLimiter();
      for (var i = 0; i < 5; i++) {
        limiter.registerFailure();
      }
      expect(limiter.isLocked, isTrue);
      limiter.reset();
      expect(limiter.isLocked, isFalse);
      expect(limiter.registerFailure(), isNull);
    });
  });
}
