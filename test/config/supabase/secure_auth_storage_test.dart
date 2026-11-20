import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/config/supabase/secure_auth_storage.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _key = 'sb-project-auth-token';
const _storage = FlutterSecureStorage();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  SecureSessionStorage sessionStorage() =>
      SecureSessionStorage(persistSessionKey: _key, storage: _storage);

  group('SecureSessionStorage', () {
    test('moves a session saved by older versions out of SharedPreferences '
        'without signing the user out', () async {
      SharedPreferences.setMockInitialValues({_key: '{"session":1}'});
      FlutterSecureStorage.setMockInitialValues({});

      final storage = sessionStorage();
      await storage.initialize();

      expect(await storage.hasAccessToken(), isTrue);
      expect(await storage.accessToken(), '{"session":1}');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(_key), isFalse);
    });

    test('a fresh install ignores a session left in the Keychain by a '
        'previous install', () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({
        _key: '{"old":1}',
        SecurePkceStorage.storageKey: 'verifier',
      });

      final storage = sessionStorage();
      await storage.initialize();

      expect(await storage.hasAccessToken(), isFalse);
      expect(await _storage.read(key: SecurePkceStorage.storageKey), isNull);
    });

    test('after the first launch it keeps the stored session', () async {
      SharedPreferences.setMockInitialValues({
        SecureSessionStorage.installMarkerKey: true,
      });
      FlutterSecureStorage.setMockInitialValues({_key: '{"current":1}'});

      final storage = sessionStorage();
      await storage.initialize();

      expect(await storage.accessToken(), '{"current":1}');
    });

    test('persists and removes the session in secure storage only', () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final storage = sessionStorage();
      await storage.initialize();

      await storage.persistSession('{"s":2}');
      expect(await _storage.read(key: _key), '{"s":2}');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_key), isNull);

      await storage.removePersistedSession();
      expect(await storage.hasAccessToken(), isFalse);
    });
  });

  test('SecurePkceStorage keeps the verifier under a prefixed key', () async {
    FlutterSecureStorage.setMockInitialValues({});
    const pkce = SecurePkceStorage(storage: _storage);

    await pkce.setItem(key: 'supabase.auth.token-code-verifier', value: 'v');
    expect(await _storage.read(key: SecurePkceStorage.storageKey), 'v');
    expect(
      await pkce.getItem(key: 'supabase.auth.token-code-verifier'),
      'v',
    );
    await pkce.removeItem(key: 'supabase.auth.token-code-verifier');
    expect(await _storage.read(key: SecurePkceStorage.storageKey), isNull);
  });

  test('PasswordRecoveryController follows the recovery link until the '
      'password is changed or the user signs out', () async {
    final events = StreamController<AuthState>.broadcast();
    final controller = PasswordRecoveryController(events.stream);
    Future<void> emit(AuthChangeEvent event) async {
      events.add(AuthState(event, null));
      await Future<void>.delayed(Duration.zero);
    }

    expect(controller.state, isFalse);
    await emit(AuthChangeEvent.passwordRecovery);
    expect(controller.state, isTrue);
    await emit(AuthChangeEvent.tokenRefreshed);
    expect(controller.state, isTrue, reason: 'a refresh keeps it pending');

    controller.complete();
    expect(controller.state, isFalse);

    await emit(AuthChangeEvent.passwordRecovery);
    await emit(AuthChangeEvent.signedOut);
    expect(controller.state, isFalse);

    // Un link vencido llega como error: no rompe nada.
    events.addError(const AuthException('expired'));
    await Future<void>.delayed(Duration.zero);
    expect(controller.state, isFalse);

    controller.dispose();
    await events.close();
  });
}
