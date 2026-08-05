import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api/football_api_client.dart';
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
    state = AsyncData(trimmed);
  }

  Future<void> clear() async {
    await ref.read(secureKeyStoreProvider).clear();
    state = const AsyncData(null);
  }
}

/// API client rebuilt whenever the key changes.
final footballApiClientProvider = Provider<FootballApiClient>((ref) {
  final key = ref.watch(apiKeyProvider).valueOrNull;
  final client = FootballApiClient(apiKey: key);
  ref.onDispose(client.close);
  return client;
});
