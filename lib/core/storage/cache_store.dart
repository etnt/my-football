import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A cached entry together with the time it was written.
class CacheEntry {
  const CacheEntry({required this.savedAt, required this.data});

  final DateTime savedAt;
  final Object? data;

  bool isFresh(Duration ttl) => DateTime.now().difference(savedAt) < ttl;
}

/// Simple "JSON + timestamp" cache backed by [SharedPreferences].
///
/// Used to avoid re-fetching data (and burning the daily quota) on every
/// screen open. Swap for Hive/Isar later if richer storage is needed.
class CacheStore {
  CacheStore(this._prefs);

  final SharedPreferences _prefs;

  Future<void> writeJson(String key, Object value) {
    final entry = jsonEncode({
      'ts': DateTime.now().millisecondsSinceEpoch,
      'data': value,
    });
    return _prefs.setString(key, entry);
  }

  CacheEntry? readJson(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return CacheEntry(
        savedAt: DateTime.fromMillisecondsSinceEpoch(map['ts'] as int),
        data: map['data'],
      );
    } catch (_) {
      return null;
    }
  }
}
