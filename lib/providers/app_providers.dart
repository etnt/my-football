import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api/football_api_client.dart';
import '../core/api/sportsdb_v2_client.dart';
import '../core/storage/cache_store.dart';
import '../core/storage/secure_key_store.dart';

/// Provides the initialised [SharedPreferences]. Overridden in `main()`.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden');
});

final secureKeyStoreProvider =
    Provider<SecureKeyStore>((ref) => SecureKeyStore());

/// The current API key (loaded from secure storage). `null` means "not set".
final apiKeyProvider =
    AsyncNotifierProvider<ApiKeyNotifier, String?>(ApiKeyNotifier.new);

class ApiKeyNotifier extends AsyncNotifier<String?> {
  @override
  Future<String?> build() => ref.read(secureKeyStoreProvider).read();

  Future<void> setKey(String key) async {
    final trimmed = key.trim();
    await ref.read(secureKeyStoreProvider).save(trimmed);
    await _clearCaches();
    state = AsyncData(trimmed);
  }

  Future<void> clear() async {
    await ref.read(secureKeyStoreProvider).clear();
    await _clearCaches();
    state = const AsyncData(null);
  }

  /// Cached free/Premium responses must not mix, so wipe them on any key change.
  Future<void> _clearCaches() async {
    await CacheStore(ref.read(sharedPreferencesProvider)).clearAll();
  }
}

/// API client rebuilt whenever the key changes.
final footballApiClientProvider = Provider<FootballApiClient>((ref) {
  final key = ref.watch(apiKeyProvider).valueOrNull;
  final client = FootballApiClient(apiKey: key);
  ref.onDispose(client.close);
  return client;
});

/// True when a (Premium) key is stored — unlocks v2 features like livescores.
final isPremiumProvider = Provider<bool>((ref) {
  final key = ref.watch(apiKeyProvider).valueOrNull;
  return (key ?? '').trim().isNotEmpty;
});

/// The v2 client, available only in Premium mode. `null` on the free key.
final sportsDbV2ClientProvider = Provider<SportsDbV2Client?>((ref) {
  final key = ref.watch(apiKeyProvider).valueOrNull?.trim();
  if (key == null || key.isEmpty) return null;
  final client = SportsDbV2Client(apiKey: key);
  ref.onDispose(client.close);
  return client;
});
