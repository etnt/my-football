import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores the optional TheSportsDB Premium key in the platform secure store
/// (Keychain / Keystore), keeping it out of plaintext preferences and source
/// control. When unset, the client falls back to the shared free key.
class SecureKeyStore {
  SecureKeyStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const _keyName = 'thesportsdb_api_key';

  final FlutterSecureStorage _storage;

  Future<String?> read() => _storage.read(key: _keyName);

  Future<void> save(String key) => _storage.write(key: _keyName, value: key);

  Future<void> clear() => _storage.delete(key: _keyName);
}
