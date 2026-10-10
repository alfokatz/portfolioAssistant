import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Almacenamiento seguro de la app (Keychain en iOS, Keystore + prefs
/// cifradas en Android). Lo comparten la sesión de Supabase y
/// `PreferencesManager`.
const appSecureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
  iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
);

/// Sesión de Supabase (access + refresh token) en el Keychain / Keystore en
/// vez de en SharedPreferences, que en Android es un XML legible con root o
/// desde un backup.
///
/// Al iniciar:
/// - Instalación nueva: borra cualquier sesión que haya quedado en el
///   Keychain (en iOS sobrevive a desinstalar la app) para no entrar con la
///   cuenta de una instalación anterior.
/// - Migración: si la sesión estaba en SharedPreferences (versiones
///   anteriores), la mueve acá y la borra de allá, sin cerrar la sesión.
class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage({
    required this.persistSessionKey,
    FlutterSecureStorage storage = appSecureStorage,
    Future<SharedPreferences> Function()? preferences,
  }) : _storage = storage,
       _preferences = preferences ?? SharedPreferences.getInstance;

  final String persistSessionKey;
  final FlutterSecureStorage _storage;
  final Future<SharedPreferences> Function() _preferences;

  /// Marca en SharedPreferences (se borra al desinstalar, a diferencia del
  /// Keychain) de que esta instalación ya inicializó el almacenamiento.
  static const installMarkerKey = 'auth_secure_storage_ready';

  @override
  Future<void> initialize() async {
    final prefs = await _preferences();
    if (prefs.getBool(installMarkerKey) ?? false) return;

    await _storage.delete(key: persistSessionKey);
    await _storage.delete(key: SecurePkceStorage.storageKey);

    final legacy = prefs.getString(persistSessionKey);
    if (legacy != null) {
      await _storage.write(key: persistSessionKey, value: legacy);
      await prefs.remove(persistSessionKey);
    }
    await prefs.setBool(installMarkerKey, true);
  }

  @override
  Future<bool> hasAccessToken() =>
      _storage.containsKey(key: persistSessionKey);

  @override
  Future<String?> accessToken() => _storage.read(key: persistSessionKey);

  @override
  Future<void> removePersistedSession() =>
      _storage.delete(key: persistSessionKey);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(key: persistSessionKey, value: persistSessionString);
}

/// Code verifier del flujo PKCE (OAuth, confirmación de email, reset de
/// contraseña). Vive lo que dura el flujo, pero es lo que vuelve inútil un
/// `code` interceptado: también va al almacenamiento seguro.
///
/// GoTrue usa una sola key para el verifier; [storageKey] la prefija para
/// no chocar con otras entradas del Keychain.
class SecurePkceStorage extends GotrueAsyncStorage {
  const SecurePkceStorage({FlutterSecureStorage storage = appSecureStorage})
    : _storage = storage;

  final FlutterSecureStorage _storage;

  static const _prefix = 'porty-pkce-';

  /// Key con la que queda el verifier de GoTrue (`supabase.auth.token-code-verifier`).
  static const storageKey = '${_prefix}supabase.auth.token-code-verifier';

  @override
  Future<String?> getItem({required String key}) =>
      _storage.read(key: '$_prefix$key');

  @override
  Future<void> setItem({required String key, required String value}) =>
      _storage.write(key: '$_prefix$key', value: value);

  @override
  Future<void> removeItem({required String key}) =>
      _storage.delete(key: '$_prefix$key');
}
