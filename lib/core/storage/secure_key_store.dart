import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores the API-Football key in the platform secure store (Keychain /
/// Keystore), keeping it out of plaintext preferences and source control.
class SecureKeyStore {
  SecureKeyStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const _keyName = 'api_football_key';

  final FlutterSecureStorage _storage;

  Future<String?> read() => _storage.read(key: _keyName);

  Future<void> save(String key) => _storage.write(key: _keyName, value: key);

  Future<void> clear() => _storage.delete(key: _keyName);
}
